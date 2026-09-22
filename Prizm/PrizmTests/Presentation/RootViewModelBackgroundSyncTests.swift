import XCTest
@testable import Prizm

/// `RootViewModel`'s half of the background refresh: that the monitor follows the unlocked state
/// from the same transition the idle monitor does, and that a tick the decision allows reaches the
/// browser view model.
///
/// The monitor is a mock, so what is under test here is the wiring. The decision itself is
/// `BackgroundSyncMonitorTests`.
@MainActor
final class RootViewModelBackgroundSyncTests: XCTestCase {

    private var mockAuth: MockAuthRepository!
    private var mockVault: MockVaultRepository!
    private var deps: MockRootDependencies!
    private var sut: RootViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockAuth  = MockAuthRepository()
        mockVault = MockVaultRepository()
        deps      = MockRootDependencies(auth: mockAuth, vault: mockVault)
        sut       = RootViewModel(container: deps)
    }

    override func tearDown() async throws {
        mockAuth = nil
        mockVault = nil
        deps = nil
        sut = nil
        try await super.tearDown()
    }

    private var monitor: MockBackgroundSyncMonitor { deps.mockBackgroundSyncMonitor }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - 4.2 the monitor follows the unlocked state

    func test_unlockingStartsBackgroundRefresh() async throws {
        sut.screen = .vault

        await waitUntil { self.monitor.isRunning }

        XCTAssertTrue(monitor.isRunning)
        XCTAssertGreaterThanOrEqual(monitor.startCount, 1)
    }

    func test_syncingScreenCountsAsUnlocked() async throws {
        sut.screen = .syncing(message: "Syncing…")

        await waitUntil { self.monitor.isRunning }

        XCTAssertTrue(monitor.isRunning)
    }

    /// Every locked screen stops it. A timer running against the login screen would be pure
    /// overhead — and a refresh with the vault locked is the one thing this feature must never do.
    func test_lockedScreensDoNotRefresh() async throws {
        for screen in [RootViewModel.Screen.login, .loading, .unlock, .twoFactorPrompt(.authenticatorApp)] {
            sut.screen = screen
            try? await Task.sleep(for: .milliseconds(30))
            XCTAssertFalse(monitor.isRunning, "\(screen) must not run a background refresh")
        }
    }

    // MARK: - 4.3 lock and sign-out leave it stopped

    func test_lockVault_stopsBackgroundRefresh() async throws {
        sut.screen = .vault
        await waitUntil { self.monitor.isRunning }

        sut.lockVault()

        await waitUntil { !self.monitor.isRunning }
        XCTAssertFalse(monitor.isRunning)
    }

    func test_signOut_stopsBackgroundRefresh() async throws {
        sut.screen = .vault
        await waitUntil { self.monitor.isRunning }

        sut.signOut()

        await waitUntil { !self.monitor.isRunning }
        XCTAssertFalse(monitor.isRunning)
    }

    // MARK: - 4.5 a tick the decision allows reaches the browser

    func test_tick_performsASyncWhenTheDecisionAllowsIt() async throws {
        sut.screen = .vault
        await waitUntil { self.monitor.isRunning }
        deps.mockSyncUseCase.stubbedResult = SyncResult(
            syncedAt: Date(), totalCiphers: 1, failedDecryptionCount: 0
        )

        monitor.fire(.timer)

        await waitUntil { self.deps.mockSyncUseCase.executeCallCount == 1 }
        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 1)
    }

    /// The decision is the monitor's, and a refusal must be a no-op: no sync, nothing to dismiss.
    func test_tick_isANoOpWhenTheDecisionRefuses() async throws {
        sut.screen = .vault
        await waitUntil { self.monitor.isRunning }
        monitor.stubbedShouldSync = false

        monitor.fire(.timer)
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 0)
        XCTAssertNil(sut.vaultBrowserVM.syncErrorMessage)
    }

    /// A tick that arrives when the vault is not unlocked must not sync even if the monitor somehow
    /// managed to fire — the monitor is stopped in that state, and this is the belt to that braces.
    func test_tick_whileLocked_isIgnored() async throws {
        sut.screen = .login

        monitor.fire(.timer)
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 0)
    }

    /// The decision is asked with the session's own state, so a busy session is refused without the
    /// monitor needing to know what "busy" means. What is under test is the argument, not the
    /// verdict — the verdict is the stub's, and the real one is `BackgroundSyncMonitorTests`.
    func test_tick_passesTheSessionsBusyStateToTheDecision() async throws {
        sut.screen = .vault
        await waitUntil { self.monitor.isRunning }
        monitor.stubbedShouldSync = false
        sut.vaultBrowserVM.handleEditSheetState(true)
        try? await Task.sleep(for: .milliseconds(30))

        monitor.fire(.timer)
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(
            monitor.lastShouldSyncArguments?.isBusy, true,
            "an open edit sheet must be reported as busy, or a refresh would discard the draft"
        )
        XCTAssertEqual(monitor.lastShouldSyncArguments?.isUnlocked, true)
        XCTAssertEqual(deps.mockSyncUseCase.executeCallCount, 0)
    }

    /// …and the same for the other half of "busy": a write in flight, which is the case the edit
    /// sheet cannot cover because the sheet may already be closed.
    func test_tick_reportsAMutationInFlightAsBusy() async throws {
        sut.screen = .vault
        await waitUntil { self.monitor.isRunning }
        monitor.stubbedShouldSync = false
        deps.deleteUseCase.delay = .milliseconds(300)

        let inFlight = Task { await self.sut.vaultBrowserVM.performSoftDelete(id: "1") }
        await waitUntil { self.sut.vaultBrowserVM.isMutating }

        monitor.fire(.timer)
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(
            monitor.lastShouldSyncArguments?.isBusy, true,
            "a refresh landing between a write and the store's update leaves the list wrong"
        )
        await inFlight.value
    }
}
