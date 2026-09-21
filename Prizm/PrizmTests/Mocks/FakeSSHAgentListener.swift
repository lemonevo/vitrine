import Foundation
@testable import Prizm

// MARK: - FakeSSHAgentListener

/// A listener that never binds anything.
///
/// Exists so `SSHAgentCoordinator`'s state machine can be tested without a socket. Everything with
/// a failure mode is in that state machine — enabled × unlocked → running, and the reason when it
/// cannot start — and driving it through a real `bind` would make each test depend on the
/// filesystem, on `sun_path`'s 104-byte limit, and on not being sandboxed, while covering nothing
/// the state machine's own tests do not.
///
/// It also keeps the `respond` closure it was handed, which is what lets a test send a real
/// `REQUEST_IDENTITIES` down the same path a socket would use — vault read, key classification and
/// responder included — with no descriptor in the way.
///
/// Deliberately **not** `@MainActor`: `SSHAgentListening` is nonisolated, and the coordinator drives
/// it from the main actor anyway, so isolation here would buy nothing and cost a conformance.
nonisolated final class FakeSSHAgentListener: SSHAgentListening {

    let socketPath: String

    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount  = 0

    /// When set, `start()` throws it instead of listening. Cleared by the test, not by this type.
    var startError: Error?

    /// The closure the coordinator built for this listener. `nil` until the first start.
    var respond: (@Sendable (Data, SSHAgentPeer?) async -> Data)?

    init(socketPath: String = "/tmp/prizm-ssh-agent-tests/agent.sock") {
        self.socketPath = socketPath
    }

    func start() throws {
        startCount += 1
        if let startError { throw startError }
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }
}
