import Foundation
import os.log

// MARK: - SSHAgentSocketError

/// Why the agent could not be made reachable.
///
/// Each case carries what it needs to be *explained*, because the spec's scenario is not "the agent
/// fails" but "the agent reports that it is unavailable **and why**". An agent that silently serves
/// nobody looks, to the user, like an agent protecting them — so a failure that reaches the UI as
/// "unavailable" without a reason is worse than no failure message at all.
nonisolated enum SSHAgentSocketError: Error, LocalizedError, Equatable {

    /// The process is sandboxed, so a socket under the real home directory cannot be reached by
    /// `ssh` even though binding one inside the container succeeds.
    ///
    /// Detected before binding, on purpose: the bind *would* succeed, and an agent that comes up
    /// green while no client can find it is the one outcome the spec singles out as unacceptable.
    case sandboxed

    /// The socket directory could not be created, or exists and is not private to the user.
    case directoryUnusable(path: String, reason: String)

    /// `sun_path` is 104 bytes. A path longer than this cannot be bound at all, and the failure
    /// from `bind` would be `ENAMETOOLONG` — a name that tells the user nothing about the cause.
    case pathTooLong(path: String, limit: Int)

    case socketCreationFailed(code: Int32)
    case bindFailed(path: String, code: Int32)
    case listenFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .sandboxed:
            return L("Prizm is running sandboxed. A sandboxed app can only create sockets inside its own container, which ssh cannot reach, so the agent cannot be used in this build.")
        case .directoryUnusable(let path, let reason):
            return L("Prizm could not prepare a private directory for the agent socket at %@: %@", path, reason)
        case .pathTooLong(let path, let limit):
            return L("The socket path is too long (%lld characters is the maximum): %@",
                     Int64(limit), path)
        case .socketCreationFailed(let code):
            return L("Prizm could not create the agent socket (error %lld).", Int64(code))
        case .bindFailed(let path, let code):
            return L("Prizm could not bind the agent socket at %@ (error %lld). Another agent may already be listening there.",
                     path, Int64(code))
        case .listenFailed(let code):
            return L("Prizm could not listen on the agent socket (error %lld).", Int64(code))
        }
    }
}

// MARK: - SSHAgentSocketLocation

/// Where the socket goes, and why there.
nonisolated enum SSHAgentSocketLocation {

    /// `~/Library/Application Support/Prizm/ssh-agent/agent.sock`.
    ///
    /// A stable path rather than a per-launch temporary one, because `SSH_AUTH_SOCK` has to be
    /// exported in the user's shell and a path that changes on every launch would have to be
    /// re-exported every time. The cost of stability is a stale socket file after a crash, handled
    /// in `SSHAgentServer.start` by removing only a file that is a socket.
    static func defaultPath() -> String {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Prizm/ssh-agent", isDirectory: true)
            .appendingPathComponent("agent.sock")
            .path
    }

    /// `~` as the *real* home, not the sandbox container's.
    ///
    /// `FileManager.default.homeDirectoryForCurrentUser` resolves to the container under the App
    /// Sandbox, which is exactly the case the caller needs to detect rather than silently use.
    private static var homeDirectory: URL {
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Creates the socket's directory with `0700`, or refuses.
    ///
    /// The directory is created rather than the socket alone being dropped into an existing one,
    /// because the socket inherits no permissions of its own that matter — a directory writable by
    /// others would let anyone replace the socket and collect signature requests.
    static func prepareDirectory(containing path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let manager   = FileManager.default

        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory,
                                         withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        }

        guard let attributes = try? manager.attributesOfItem(atPath: directory.path) else {
            throw SSHAgentSocketError.directoryUnusable(
                path: directory.path, reason: L("the directory could not be created"))
        }
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else {
            // An existing directory Prizm did not create, or one someone widened. Refusing is the
            // whole point: binding there would hand every signature request to whoever can write.
            throw SSHAgentSocketError.directoryUnusable(
                path: directory.path, reason: L("the directory is not private to this user"))
        }
    }
}

// MARK: - SSHAgentServer

/// Listens on a Unix socket and answers agent messages.
///
/// This is the only part of the agent that owns a file descriptor, and it owns nothing else: the
/// identities, the gate and the signing all arrive as the `respond` closure. That is what lets the
/// protocol be tested without a socket and the socket be tested without a vault.
///
/// `@unchecked Sendable` with all mutable state confined to `queue`: every read and write of
/// `listenFD`, `listenSource` and `connections` happens on that one serial queue, and `isRunning`
/// goes through `queue.sync` rather than reading the field directly.
nonisolated final class SSHAgentServer: @unchecked Sendable {

    /// The largest message accepted. `ssh` sends a signature request a few hundred bytes long; a
    /// peer claiming more than this is not speaking the protocol, and growing the buffer to
    /// accommodate a claimed length is how a small allocation becomes a large one.
    static let maximumMessageLength = 4 * 1024 * 1024

    let socketPath: String

    private let respond: @Sendable (Data) async -> Data
    private let queue   = DispatchQueue(label: "com.prizm.ssh-agent", qos: .userInitiated)
    private let logger  = Logger(subsystem: "com.prizm", category: "SSHAgent")

    private var listenFD:     Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var connections:  [Int32: Connection] = [:]

    init(socketPath: String, respond: @escaping @Sendable (Data) async -> Data) {
        self.socketPath = socketPath
        self.respond    = respond
    }

    deinit { stop() }

    // MARK: - Lifecycle

    /// Whether the listener is up. Read through `queue` — the field is written there.
    var isRunning: Bool { queue.sync { listenFD >= 0 } }

    /// Binds, listens, and returns. Idempotent: a second call while running does nothing, because
    /// Settings can toggle the switch faster than a start can complete.
    ///
    /// - Throws: `SSHAgentSocketError` naming the obstruction. A start that fails leaves nothing
    ///   behind — no descriptor, no socket file, no accept loop — so a retry is a retry and not a
    ///   second attempt to bind an address already in use.
    func start() throws {
        try queue.sync {
            guard listenFD < 0 else { return }
            do {
                try startOnQueue()
            } catch {
                stopOnQueue()
                throw error
            }
        }
    }

    /// Stops listening, closes every connection and removes the socket file.
    ///
    /// Connections are closed rather than drained: a client waiting on a signature whose grant was
    /// revoked by a lock must not receive it, and the only way to guarantee that is to close.
    func stop() {
        queue.sync { stopOnQueue() }
    }

    // MARK: - Queue-confined implementation

    private func startOnQueue() throws {
        // Checked before binding, not after. Under the sandbox the bind would succeed and `ssh`
        // would never find the socket, which is the one failure this file exists to make visible.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            throw SSHAgentSocketError.sandboxed
        }

        // Checked before the directory is created: a path that can never be bound should not leave
        // a directory behind on the way to failing.
        let pathBytes = [UInt8](socketPath.utf8)
        // 104 bytes including the terminator.
        guard pathBytes.count + 1 <= 104 else {
            throw SSHAgentSocketError.pathTooLong(path: socketPath, limit: 103)
        }

        try SSHAgentSocketLocation.prepareDirectory(containing: socketPath)

        // Only a socket is removed. Unlinking a path that happens to be a regular file — because
        // the user, or an older build, put something there — would destroy data to no purpose.
        var existing = stat()
        if lstat(socketPath, &existing) == 0, (existing.st_mode & S_IFMT) == S_IFSOCK {
            unlink(socketPath)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SSHAgentSocketError.socketCreationFailed(code: errno) }

        // Non-blocking, because the accept loop below calls `accept` until it is told there is
        // nothing left. On a blocking descriptor that call waits for the *next* connection, which
        // would wedge the server's queue on the first client to connect — an agent that answers
        // exactly one request and then stops forever.
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let code = errno
            close(fd)
            throw SSHAgentSocketError.socketCreationFailed(code: code)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() where index < raw.count - 1 {
                raw[index] = byte
            }
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                bind(fd, socketPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SSHAgentSocketError.bindFailed(path: socketPath, code: code)
        }

        // The socket's own permissions: readable only by the user, so no other account on the
        // machine can ask Prizm to sign with these keys.
        chmod(socketPath, 0o600)

        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            unlink(socketPath)
            throw SSHAgentSocketError.listenFailed(code: code)
        }

        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenFD >= 0 { close(self.listenFD); self.listenFD = -1 }
        }
        listenSource = source
        source.resume()

        logger.info("SSH agent listening at \(self.socketPath, privacy: .public)")
    }

    private func stopOnQueue() {
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        for (_, connection) in connections { connection.shutdown() }
        connections.removeAll()
        unlink(socketPath)
        logger.info("SSH agent stopped")
    }

    /// Accepts every connection currently pending, one `accept` per readable event.
    ///
    /// Looping matters: a read event can correspond to more than one queued connection, and
    /// accepting one per event leaves the rest waiting for an event that will not come.
    private func acceptPending() {
        while listenFD >= 0 {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else {
                // EAGAIN means "no more pending"; anything else is a real failure and the loop
                // must not spin on it.
                return
            }
            openConnection(fd)
        }
    }

    private func openConnection(_ fd: Int32) {
        // Blocking, deliberately: the connection's own queue does nothing else, and a non-blocking
        // descriptor would turn the write loop's `EAGAIN` retry into a spin.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) & ~O_NONBLOCK)

        let connection = Connection(fd: fd)
        connections[fd] = connection

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: connection.queue)
        connection.source = source
        source.setEventHandler { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.readAvailable(on: connection)
        }
        source.setCancelHandler { [weak self, weak connection] in
            guard let connection else { return }
            connection.shutdown()
            guard let self else { return }
            let fd = connection.fd
            self.queue.async { self.connections.removeValue(forKey: fd) }
        }
        source.resume()
    }

    private func readAvailable(on connection: Connection) {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let count = recv(connection.fd, &chunk, chunk.count, 0)

        if count == 0 { connection.source?.cancel(); return }
        if count < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            connection.source?.cancel()
            return
        }

        connection.buffer.append(contentsOf: chunk[0..<count])

        while let message = connection.nextMessage(maximum: Self.maximumMessageLength) {
            // Chained, so answers go back in the order the requests arrived. A client that piped
            // two sign requests would otherwise get the second signature first, and the failure
            // would be blamed on the key.
            let previous = connection.pending
            connection.pending = Task.detached(priority: .userInitiated) { [weak self] in
                if let previous { await previous.value }
                guard let self else { return }
                let answer = await self.respond(message)
                self.write(answer, on: connection)
            }
        }

        if connection.declaresOversizedMessage(maximum: Self.maximumMessageLength) {
            logger.error("SSH agent closed a connection that declared an oversized message")
            connection.source?.cancel()
        }
    }

    private func write(_ bytes: Data, on connection: Connection) {
        connection.queue.async { [weak self] in
            guard connection.isOpen else { return }
            var remaining = bytes
            while !remaining.isEmpty {
                let written = remaining.withUnsafeBytes { raw in
                    send(connection.fd, raw.baseAddress, raw.count, 0)
                }
                if written <= 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    self?.logger.error("SSH agent could not write a response; closing")
                    connection.source?.cancel()
                    return
                }
                remaining = remaining.dropFirst(written)
            }
        }
    }
}

// MARK: - Connection

/// One client, and the buffer it is being read into.
///
/// Every field is touched only on this connection's own queue, which is what makes the server's
/// dictionary of them safe without a lock.
private nonisolated final class Connection: @unchecked Sendable {

    let fd: Int32
    let queue = DispatchQueue(label: "com.prizm.ssh-agent.connection", qos: .userInitiated)

    var buffer  = Data()
    var source:  DispatchSourceRead?
    /// The last response still being produced, so the next one waits for it. See
    /// `readAvailable(on:)`.
    var pending: Task<Void, Never>?

    private(set) var isOpen = true

    init(fd: Int32) { self.fd = fd }

    /// Pulls one complete message — length prefix included — off the front of the buffer.
    func nextMessage(maximum: Int) -> Data? {
        guard let length = declaredLength(), length <= maximum else { return nil }
        guard buffer.count >= 4 + length else { return nil }
        let end     = 4 + length
        let message = buffer.prefix(end)
        buffer.removeFirst(end)
        return Data(message)
    }

    /// Whether the buffer declares a message larger than Prizm will accept — meaning no framing of
    /// this stream will ever succeed and the connection has to go.
    func declaresOversizedMessage(maximum: Int) -> Bool {
        guard let length = declaredLength() else { return false }
        return length > maximum
    }

    /// The length in the buffer's first four bytes, read byte by byte.
    ///
    /// Not `load(as: UInt32.self)`: a `Data` slice is not guaranteed to be four-byte aligned, and
    /// an unaligned load is a trap rather than a wrong answer.
    private func declaredLength() -> Int? {
        guard buffer.count >= 4 else { return nil }
        let start = buffer.startIndex
        return Int(UInt32(buffer[start])         << 24 |
                   UInt32(buffer[start + 1])     << 16 |
                   UInt32(buffer[start + 2])     << 8  |
                   UInt32(buffer[start + 3]))
    }

    func shutdown() {
        guard isOpen else { return }
        isOpen = false
        source?.cancel()
        source = nil
        pending?.cancel()
        pending = nil
        close(fd)
        buffer.removeAll()
    }
}
