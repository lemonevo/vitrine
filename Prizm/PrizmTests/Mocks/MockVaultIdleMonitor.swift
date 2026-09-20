import Foundation
@testable import Prizm

/// Test double for `VaultIdleMonitoring`.
///
/// Records start/stop so a suite can assert that monitoring follows the unlocked state, and lets a
/// test fire the timeout callback on demand. The real monitor's AppKit wiring — the `NSEvent`
/// local monitor and the repeating timer — is deliberately absent: it is the one part of the
/// feature that cannot be exercised in a unit test, which is exactly why the seam exists.
@MainActor
final class MockVaultIdleMonitor: VaultIdleMonitoring {

    var onTimeout: ((VaultTimeoutAction) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount  = 0
    private(set) var isRunning  = false

    func start() {
        startCount += 1
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    /// Simulates the configured interval elapsing.
    func fire(_ action: VaultTimeoutAction = .lock) {
        onTimeout?(action)
    }
}
