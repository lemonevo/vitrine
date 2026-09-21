import XCTest
import Foundation
@testable import Prizm

/// The Unix socket layer, exercised against a real socket.
///
/// Everything below the socket is already covered without one. These tests exist for what only a
/// real `connect` can show: that the path is bound, that a client's bytes come back as a framed
/// answer, that two answers arrive in the order asked, and that stopping removes the file — which
/// is what decides whether `ssh` finds the agent or hangs on a stale path.
final class SSHAgentServerTests: XCTestCase {

    /// A private directory per test: `start()` refuses to bind inside a directory anyone can write
    /// to, and `FileManager.default.temporaryDirectory` alone is the process-wide `T/`.
    /// Short on purpose: `sun_path` allows 104 bytes and this machine's `T/` already uses 53 of
    /// them, so a UUID-named directory puts the whole path past the limit and every test fails with
    /// `.pathTooLong` — a real constraint, not something to work around in the server.
    private func socketPath(inPermissions permissions: Int = 0o700) throws -> (path: String, root: String) {
        let suffix = String(UUID().uuidString.prefix(8))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pa-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: permissions])
        return (root.appendingPathComponent("a.sock").path, root.path)
    }

    // MARK: - Client

    /// Named `openClient` rather than `connect` so the call below resolves to `Darwin.connect`.
    private func openClient(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TestFailure.couldNotCreateSocket }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = [UInt8](path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() where index < raw.count - 1 {
                raw[index] = byte
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                connect(fd, socketPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            throw TestFailure.couldNotConnect(path: path, code: errno)
        }

        // Without this a test that is wrong would hang rather than fail, and a hang in a suite is
        // reported as a timeout with no indication of which assertion never arrived.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    /// Reads one framed message: four bytes of length, then the body.
    private func readMessage(from fd: Int32) throws -> Data {
        var header = Data()
        while header.count < 4 {
            var chunk = [UInt8](repeating: 0, count: 4 - header.count)
            let count = recv(fd, &chunk, chunk.count, 0)
            if count <= 0 { throw TestFailure.connectionClosed }
            header.append(contentsOf: chunk[0..<count])
        }
        let start  = header.startIndex
        let length = Int(UInt32(header[start])     << 24 |
                         UInt32(header[start + 1]) << 16 |
                         UInt32(header[start + 2]) << 8  |
                         UInt32(header[start + 3]))

        var body = Data()
        while body.count < length {
            var chunk = [UInt8](repeating: 0, count: length - body.count)
            let count = recv(fd, &chunk, chunk.count, 0)
            if count <= 0 { throw TestFailure.connectionClosed }
            body.append(contentsOf: chunk[0..<count])
        }
        return header + body
    }

    /// The answer's message type — the byte after the length.
    private func messageType(of answer: Data) -> UInt8? {
        guard answer.count >= 5 else { return nil }
        return answer[answer.startIndex + 4]
    }

    private enum TestFailure: Error, LocalizedError {
        case couldNotCreateSocket
        case couldNotConnect(path: String, code: Int32)
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .couldNotCreateSocket:                 return "the test could not create a socket"
            case .couldNotConnect(let path, let code):  return "could not connect to \(path) (\(code))"
            case .connectionClosed:                     return "the connection closed before a message arrived"
            }
        }
    }

    // MARK: - Start and stop

    func testStart_bindsTheSocketAtThePath() throws {
        let (path, _) = try socketPath()
        let server = SSHAgentServer(socketPath: path) { _, _ in SSHWireWriter.failure() }
        defer { server.stop() }

        try server.start()

        XCTAssertTrue(server.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    /// A second start is a no-op rather than an error: Settings can toggle the switch faster than
    /// a start completes, and "address already in use" there would read as a broken agent.
    func testStart_isIdempotent() throws {
        let (path, _) = try socketPath()
        let server = SSHAgentServer(socketPath: path) { _, _ in SSHWireWriter.failure() }
        defer { server.stop() }

        try server.start()
        XCTAssertNoThrow(try server.start())
        XCTAssertTrue(server.isRunning)
    }

    func testStop_removesTheSocketFileAndRefusesConnections() throws {
        let (path, _) = try socketPath()
        let server = SSHAgentServer(socketPath: path) { _, _ in SSHWireWriter.failure() }
        try server.start()
        server.stop()

        XCTAssertFalse(server.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertThrowsError(try openClient(to: path))
    }

    /// The permissions check is the one thing standing between the agent and another account on the
    /// machine asking Prizm to sign with these keys.
    func testStart_refusesADirectoryThatIsNotPrivate() throws {
        let (path, _) = try socketPath(inPermissions: 0o755)
        let server = SSHAgentServer(socketPath: path) { _, _ in SSHWireWriter.failure() }
        defer { server.stop() }

        do {
            try server.start()
            XCTFail("binding inside a world-readable directory should be refused")
        } catch let error as SSHAgentSocketError {
            guard case .directoryUnusable = error else {
                return XCTFail("expected .directoryUnusable, got \(error)")
            }
        }
        XCTAssertFalse(server.isRunning)
    }

    func testStart_refusesAPathLongerThanTheSocketLimit() throws {
        let path = "/" + String(repeating: "a", count: 200) + "/agent.sock"
        let server = SSHAgentServer(socketPath: path) { _, _ in SSHWireWriter.failure() }
        defer { server.stop() }

        XCTAssertThrowsError(try server.start()) { error in
            guard case SSHAgentSocketError.pathTooLong = error else {
                return XCTFail("expected .pathTooLong, got \(error)")
            }
        }
    }

    // MARK: - Round trip

    func testClient_receivesTheAnswerToItsRequest() throws {
        let (path, _) = try socketPath()
        let blob    = Data("public-key-blob".utf8)
        let server  = SSHAgentServer(socketPath: path) { _, _ in
            SSHWireWriter.identitiesAnswer([(blob: blob, comment: "Deploy Key")])
        }
        defer { server.stop() }
        try server.start()

        let fd = try openClient(to: path)
        defer { close(fd) }

        var request = SSHWireWriter.message(type: .requestIdentities)
        let sent = request.withUnsafeMutableBytes { raw in send(fd, raw.baseAddress, raw.count, 0) }
        XCTAssertEqual(sent, request.count)

        let answer = try readMessage(from: fd)
        XCTAssertEqual(messageType(of: answer), SSHAgentMessage.identitiesAnswer.rawValue)

        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        _ = try reader.readByte()
        XCTAssertEqual(try reader.readUInt32(), 1)
        XCTAssertEqual(try reader.readString(), blob)
        XCTAssertEqual(String(decoding: try reader.readString(), as: UTF8.self), "Deploy Key")
    }

    /// Two requests on one connection come back in order.
    ///
    /// The responder is slow for the first request, which is what would expose the opposite: a
    /// server that answered each request on its own task would let the second finish first, and a
    /// client pipelining two sign requests would blame the key for a signature it cannot verify.
    func testClient_receivesAnswersInTheOrderAsked() async throws {
        let (path, _) = try socketPath()
        let order = Order()
        let server = SSHAgentServer(socketPath: path) { _, _ in
            let number = await order.next()
            if number == 1 { try? await Task.sleep(nanoseconds: 200_000_000) }
            return SSHWireWriter.identitiesAnswer([(blob: Data(), comment: "\(number)")])
        }
        defer { server.stop() }
        try server.start()

        let fd = try openClient(to: path)
        defer { close(fd) }

        var request = SSHWireWriter.message(type: .requestIdentities)
        for _ in 0..<2 {
            _ = request.withUnsafeMutableBytes { raw in send(fd, raw.baseAddress, raw.count, 0) }
        }

        var comments: [String] = []
        for _ in 0..<2 {
            let answer = try readMessage(from: fd)
            var reader = SSHWireReader(answer)
            _ = try reader.readUInt32()
            _ = try reader.readByte()
            _ = try reader.readUInt32()
            _ = try reader.readString()
            comments.append(String(decoding: try reader.readString(), as: UTF8.self))
        }
        XCTAssertEqual(comments, ["1", "2"])
    }

    /// Two clients at once, each answered on its own connection.
    func testServer_servesMoreThanOneClient() throws {
        let (path, _) = try socketPath()
        let server = SSHAgentServer(socketPath: path) { _, _ in
            SSHWireWriter.identitiesAnswer([(blob: Data(), comment: "key")])
        }
        defer { server.stop() }
        try server.start()

        for _ in 0..<2 {
            let fd = try openClient(to: path)
            defer { close(fd) }
            var request = SSHWireWriter.message(type: .requestIdentities)
            _ = request.withUnsafeMutableBytes { raw in send(fd, raw.baseAddress, raw.count, 0) }
            let answer = try readMessage(from: fd)
            XCTAssertEqual(messageType(of: answer), SSHAgentMessage.identitiesAnswer.rawValue)
        }
    }

    /// A peer that disconnects mid-message must not take the server down with it.
    func testServer_survivesAClientThatDisconnectsMidMessage() throws {
        let (path, _) = try socketPath()
        let server = SSHAgentServer(socketPath: path) { _, _ in SSHWireWriter.failure() }
        defer { server.stop() }
        try server.start()

        let fd = try openClient(to: path)
        var partial = Data([0x00, 0x00, 0x00, 0x40, SSHAgentMessage.signRequest.rawValue])
        _ = partial.withUnsafeMutableBytes { raw in send(fd, raw.baseAddress, raw.count, 0) }
        close(fd)

        // The server must still answer the next client.
        let second = try openClient(to: path)
        defer { close(second) }
        var request = SSHWireWriter.message(type: .requestIdentities)
        _ = request.withUnsafeMutableBytes { raw in send(second, raw.baseAddress, raw.count, 0) }
        let answer = try readMessage(from: second)
        XCTAssertEqual(messageType(of: answer), SSHAgentMessage.failure.rawValue)
    }

    /// The documented location, asserted rather than assumed: a path that changes between the
    /// Settings text and the bind would leave the user exporting a socket that does not exist.
    func testDefaultPath_isUnderTheUsersLibraryAndShortEnoughToBind() {
        let path = SSHAgentSocketLocation.defaultPath()
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/Prizm/ssh-agent/agent.sock"),
                      "unexpected socket location: \(path)")
        XCTAssertTrue(path.count < 103, "too long to bind: \(path)")
    }
}

/// Counts requests from the responder closure, which runs off the test's actor.
private actor Order {
    private var value = 0
    func next() -> Int { value += 1; return value }
}
