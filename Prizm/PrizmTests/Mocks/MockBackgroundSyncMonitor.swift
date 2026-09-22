import Foundation
@testable import Prizm

/// Test double for `BackgroundSyncMonitoring`.
///
/// Records start/stop so a suite can assert that the refresh follows the unlocked state, and lets a
/// test fire a tick on demand. The real monitor's AppKit wiring — the repeating `Timer`, the
/// activation and wake observers — is deliberately absent: it is the part that cannot be exercised
/// in a unit test, and it is exactly why the seam exists.
///
/// `shouldSync(...)` is stubbed rather than answered, because the real answer is the thing
/// `BackgroundSyncMonitorTests` exists to pin. What this double is for is the other question: what
/// the wiring does *with* the answer, and what it asks for.
@MainActor
final class MockBackgroundSyncMonitor: BackgroundSyncMonitoring {

    var onTick: ((BackgroundSyncTrigger) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount  = 0
    private(set) var isRunning  = false

    /// What the decision returns. Set to `false` to exercise the refusal path.
    var stubbedShouldSync = true

    /// The arguments the last decision was asked with. Lets a suite prove the wiring supplies the
    /// session's real state rather than a convenient constant.
    private(set) var lastShouldSyncArguments: (trigger: BackgroundSyncTrigger,
                                               isUnlocked: Bool,
                                               isBusy: Bool,
                                               lastSuccessfulSyncAt: Date?)?

    func start() {
        startCount += 1
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func shouldSync(trigger: BackgroundSyncTrigger,
                    isUnlocked: Bool,
                    isBusy: Bool,
                    lastSuccessfulSyncAt: Date?) -> Bool {
        lastShouldSyncArguments = (trigger, isUnlocked, isBusy, lastSuccessfulSyncAt)
        return stubbedShouldSync
    }

    /// Simulates the interval elapsing, or the app coming back to the foreground.
    func fire(_ trigger: BackgroundSyncTrigger = .timer) {
        onTick?(trigger)
    }
}
