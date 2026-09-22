import Foundation
import os
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
            return L("Vitrine is running sandboxed. A sandboxed app can only create sockets inside its own container, which ssh cannot reach, so the agent cannot be used in this build.")
        case .directoryUnusable(let path, let reason):
            return L("Vitrine could not prepare a private directory for the agent socket at %@: %@", path, reason)
        case .pathTooLong(let path, let limit):
            return L("The socket path is too long (%lld characters is the maximum): %@",
                     Int64(limit), path)
        case .socketCreationFailed(let code):
            return L("Vitrine could not create the agent socket (error %lld).", Int64(code))
        case .bindFailed(let path, let code):
            return L("Vitrine could not bind the agent socket at %@ (error %lld). Another agent may already be listening there.",
                     path, Int64(code))
        case .listenFailed(let code):
            return L("Vitrine could not listen on the agent socket (error %lld).", Int64(code))
        }
    }
}

// MARK: - SSHAgentSocketLocation

/// Where the socket goes, and why there.
nonisolated enum SSHAgentSocketLocation {

    /// `~/Library/Application Support/Vitrine/ssh-agent/agent.sock`.
    ///
    /// The directory is named for the product, so a machine that exported `SSH_AUTH_SOCK`
    /// against the old path has to re-copy the line from Settings ▸ SSH agent once.
    ///
    /// A stable path rather than a per-launch temporary one, because `SSH_AUTH_SOCK` has to be
    /// exported in the user's shell and a path that changes on every launch would have to be
    /// re-exported every time. The cost of stability is a stale socket file after a crash, handled
    /// in `SSHAgentServer.start` by removing only a file that is a socket.
    static func defaultPath() -> String {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Vitrine/ssh-agent", isDirectory: true)
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
/// **Only the listening socket uses a `DispatchSource`.** Connections are served by a blocking loop
/// on a dispatch thread instead, and that is a deliberate retreat rather than a preference. A
/// `DispatchSource` owns the descriptor it was made from, and the rule about who closes it is
/// enforced by libdispatch with a trap: cancelling a per-connection source and then closing its
/// descriptor — from the cancel handler, from the queue that made it, from anywhere — killed the
/// test process with `SIGTRAP` and no diagnostic. The listening source is kept because starting and
/// stopping it is exercised by tests that pass; a source per connection is not worth the same
/// argument.
///
/// A blocking loop also makes ordering free: one connection is one thread reading a request and
/// writing its answer before reading the next, so two pipelined requests cannot come back reversed.
///
/// `@unchecked Sendable` with the listener's state confined to `queue`: `listenFD`, `listenSource`
/// and `connections` are read and written only there, and `isRunning` goes through `queue.sync`
/// rather than reading a field directly.
nonisolated final class SSHAgentServer: @unchecked Sendable {

    /// The largest message accepted. `ssh` sends a signature request a few hundred bytes long; a
    /// peer claiming more than this is not speaking the protocol, and growing the buffer to
    /// accommodate a claimed length is how a small allocation becomes a large one.
    static let maximumMessageLength = 4 * 1024 * 1024

    let socketPath: String

    /// Answers one message. The second argument is the process on the other end of the connection,
    /// when the kernel would name it — the responder needs it to say *who* is asking, and this is
    /// the only layer that has a descriptor to ask about.
    private let respond: @Sendable (Data, SSHAgentPeer?) async -> Data
    private let queue   = DispatchQueue(label: "com.prizm.ssh-agent", qos: .userInitiated)
    private let logger  = Logger(subsystem: "dev.lemonevo.vitrine", category: "SSHAgent")

    private var listenFD:     Int32 = -1
    private var listenSource: DispatchSourceRead?
    /// Open client descriptors, so `stop()` can wake their threads. Written on `queue`.
    private var connections: Set<Int32> = []
    /// Read by connection threads between polls, written by `stop()`.
    private let isStopped = OSAllocatedUnfairLock(initialState: true)

    init(socketPath: String, respond: @escaping @Sendable (Data, SSHAgentPeer?) async -> Data) {
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

    /// Stops listening, wakes every connection, and removes the socket file.
    ///
    /// Connections are cut off rather than drained: a client waiting on a signature whose grant was
    /// revoked by a lock must not receive it, and the only way to guarantee that is to end the
    /// connection. Each connection thread closes its own descriptor once its read returns, so
    /// nothing here closes a descriptor another thread may still be using.
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
        isStopped.withLock { $0 = false }

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
        isStopped.withLock { $0 = true }
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        // `shutdown` rather than `close`: it wakes a thread blocked in `read` with end-of-file and
        // leaves the descriptor valid, so the thread that owns it is the one that closes it. A
        // `close` from here would be a descriptor pulled out from under a `recv` already in flight.
        for fd in connections { shutdown(fd, SHUT_RDWR) }
        connections.removeAll()
        unlink(socketPath)
        logger.info("SSH agent stopped")
    }

    /// Accepts every connection currently pending.
    ///
    /// Looping matters: a read event can correspond to more than one queued connection, and
    /// accepting one per event leaves the rest waiting for an event that will not come. The
    /// descriptor is non-blocking, so the loop is told when it is done rather than waiting.
    private func acceptPending() {
        while listenFD >= 0 {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            openConnection(fd)
        }
    }

    private func openConnection(_ fd: Int32) {
        // Blocking, deliberately: the serving loop below has a thread to itself, and a
        // non-blocking descriptor would turn every read into a spin.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) & ~O_NONBLOCK)

        // Asked once, here, rather than per message: the peer cannot change for a connection, and
        // the answer is what the signature prompt shows.
        let peer = SSHAgentPeerProcess.peer(forDescriptor: fd)

        connections.insert(fd)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { close(fd); return }
            self.serve(fd, peer: peer)
        }
    }

    /// Reads requests from one client and writes answers back, until the client leaves.
    private func serve(_ fd: Int32, peer: SSHAgentPeer?) {
        defer {
            close(fd)
            queue.async { [weak self] in self?.connections.remove(fd) }
        }

        while !isStopped.withLock({ $0 }) {
            switch Self.waitForReadable(fd) {
            case .readable: break
            case .timedOut: continue      // re-check the stop flag, then wait again
            case .closed:   return
            }
            guard let message = Self.readMessage(from: fd,
                                                 maximum: Self.maximumMessageLength) else { return }
            guard let answer = awaitResponse(to: message, peer: peer) else { return }
            guard Self.writeAll(answer, to: fd) else { return }
        }
    }

    /// Bridges the blocking loop to the async responder.
    ///
    /// A semaphore rather than `await` at the top of `serve`, because `serve` is already running on
    /// a dispatch thread and blocking it is the whole design. The responder runs on the
    /// cooperative pool, so nothing here holds a cooperative thread while it waits — including
    /// while it waits for a master password.
    private func awaitResponse(to message: Data, peer: SSHAgentPeer?) -> Data? {
        let box       = AnswerBox()
        let semaphore = DispatchSemaphore(value: 0)
        let respond   = self.respond

        Task.detached(priority: .userInitiated) {
            box.value = await respond(message, peer)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    // MARK: - Descriptor helpers

    /// What a wait on one descriptor produced.
    private enum Readiness { case readable, timedOut, closed }

    /// Whether a request can be read, waiting up to a second.
    ///
    /// The timeout is not for the client's benefit: it is what lets a connection thread notice that
    /// the agent was stopped without `stop()` having to reach into a descriptor the thread is
    /// using. `stop()` also calls `shutdown`, which wakes the wait immediately; this is the backstop
    /// for a server that was dropped without one. A timeout must **not** fall through to a read —
    /// the descriptor is blocking, so reading after a timeout would wait forever.
    private static func waitForReadable(_ fd: Int32) -> Readiness {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 1000)
        if ready > 0 { return .readable }
        if ready == 0 { return .timedOut }
        return errno == EINTR ? .timedOut : .closed
    }

    /// One complete message, length prefix included, or nil when the stream ended.
    ///
    /// A message longer than `maximum` ends the connection rather than being skipped: the length
    /// field is the only framing there is, so a peer that declares a length Prizm will not accept
    /// has put the stream somewhere no subsequent read can be trusted to find the next message.
    private static func readMessage(from fd: Int32, maximum: Int) -> Data? {
        guard let header = readExactly(4, from: fd) else { return nil }
        let start  = header.startIndex
        let length = Int(UInt32(header[start])     << 24 |
                         UInt32(header[start + 1]) << 16 |
                         UInt32(header[start + 2]) << 8  |
                         UInt32(header[start + 3]))
        guard length <= maximum, let body = readExactly(length, from: fd) else { return nil }
        return header + body
    }

    private static func readExactly(_ count: Int, from fd: Int32) -> Data? {
        var result = Data()
        while result.count < count {
            var chunk = [UInt8](repeating: 0, count: count - result.count)
            let read  = recv(fd, &chunk, chunk.count, 0)
            if read == 0 { return nil }
            if read < 0 {
                if errno == EINTR { continue }
                return nil
            }
            result.append(contentsOf: chunk[0..<read])
        }
        return result
    }

    private static func writeAll(_ bytes: Data, to fd: Int32) -> Bool {
        var remaining = bytes
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            if written > 0 {
                remaining = remaining.dropFirst(written)
                continue
            }
            if written < 0 && errno == EINTR { continue }
            return false
        }
        return true
    }
}

// MARK: - AnswerBox

/// Carries the responder's result from its task back to the connection thread.
///
/// A box rather than a captured `var`, which concurrent code cannot mutate, and rather than a
/// `Task` handle whose value would have to be awaited — the thread is deliberately not async. The
/// semaphore in `awaitResponse(to:)` is what orders the two: the write happens before the signal.
private nonisolated final class AnswerBox: @unchecked Sendable {
    var value = Data()
}
