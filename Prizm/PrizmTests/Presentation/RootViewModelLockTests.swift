import XCTest
@testable import Prizm

/// Unit tests for `RootViewModel.lockVault()`.
@MainActor
final class RootViewModelLockTests: XCTestCase {

    private var mockAuth: MockAuthRepository!
    private var mockVault: MockVaultRepository!
    /// Held so a suite can reach the container's session-scoped state. The generator history is
    /// cleared by `lockVault()` but is not observable through `sut`, so the test needs the same
    /// container the view model was built with.
    private var deps: MockRootDependencies!
    private var sut: RootViewModel!

    private let stubAccount = Account(
        userId: "user-001",
        email: "alice@example.com",
        name: nil,
        serverEnvironment: ServerEnvironment(
            base: URL(string: "https://vault.example.com")!,
            overrides: nil
        )
    )

    override func setUp() async throws {
        try await super.setUp()
        mockAuth = MockAuthRepository()
        mockVault = MockVaultRepository()
        deps = MockRootDependencies(auth: mockAuth, vault: mockVault)
        sut = RootViewModel(container: deps)
    }

    /// Yields to the main actor run loop until `condition` returns true or timeout.
    /// Replaces fixed `Task.sleep` which is flaky under parallel test execution
    /// when multiple actor hops are involved (e.g. lockVault → authRepo → vaultKeyCache → orgKeyCache).
    private func waitUntil(
        timeout: Duration = .milliseconds(500),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - 1.1 lockVault() transitions screen to .unlock

    func testLockVault_transitionsToUnlock() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault

        sut.lockVault()
        try await waitUntil { if case .unlock = self.sut.screen { return true }; return false }

        guard case .unlock = sut.screen else {
            return XCTFail("Expected .unlock, got \(sut.screen)")
        }
    }

    // MARK: - 1.2 lockVault() is a no-op when screen != .vault

    func testLockVault_noOpWhenLogin() async throws {
        sut.screen = .login
        sut.lockVault()
        // Fixed sleep (not polling) because this is a no-op test — there is no positive
        // state change to poll for. 50ms is enough for the guard-return fast path.
        try await Task.sleep(for: .milliseconds(50))

        guard case .login = sut.screen else {
            return XCTFail("Expected .login, got \(sut.screen)")
        }
    }

    func testLockVault_noOpWhenUnlock() async throws {
        sut.screen = .unlock
        sut.lockVault()
        // Fixed sleep (not polling) because this is a no-op test — there is no positive
        // state change to poll for. 50ms is enough for the guard-return fast path.
        try await Task.sleep(for: .milliseconds(50))

        guard case .unlock = sut.screen else {
            return XCTFail("Expected .unlock, got \(sut.screen)")
        }
    }

    // MARK: - 1.3 lockVault() calls authRepository.lockVault() and vaultStore.clearVault()

    func testLockVault_callsLockAndClear() async throws {
        sut.screen = .vault

        sut.lockVault()
        try await waitUntil { self.mockAuth.lockVaultCalledCount >= 1 }

        XCTAssertEqual(mockAuth.lockVaultCalledCount, 1)
        XCTAssertTrue(mockVault.clearVaultCalled)
    }

    // MARK: - 1.4 lockVault() creates a new unlockVM from the stored account

    func testLockVault_createsUnlockVM() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault
        sut.unlockVM = nil

        sut.lockVault()
        try await waitUntil { self.sut.unlockVM != nil }

        XCTAssertNotNil(sut.unlockVM)
    }

    // MARK: - 1.5 lockVault() falls back to .login when storedAccount() returns nil

    func testLockVault_fallsBackToLogin_whenNoStoredAccount() async throws {
        mockAuth.stubbedStoredAccount = nil
        sut.screen = .vault

        sut.lockVault()
        try await waitUntil { if case .login = self.sut.screen { return true }; return false }

        guard case .login = sut.screen else {
            return XCTFail("Expected .login, got \(sut.screen)")
        }
    }

    // MARK: - lockVault() works from .syncing state

    func testLockVault_worksFromSyncing() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .syncing(message: "Syncing…")

        sut.lockVault()
        try await waitUntil { if case .unlock = self.sut.screen { return true }; return false }

        guard case .unlock = sut.screen else {
            return XCTFail("Expected .unlock, got \(sut.screen)")
        }
    }

    // MARK: - lockVault() clears the generator history

    /// A value generated but never saved is still a credential, so it must not survive the lock that
    /// destroys every other piece of session state (design D9).
    func testLockVault_clearsTheGeneratorHistory() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault
        deps.generatorHistory.append("generated-but-unsaved")
        XCTAssertEqual(deps.generatorHistory.entries.count, 1)

        sut.lockVault()
        try await waitUntil { self.deps.generatorHistory.entries.isEmpty }

        XCTAssertTrue(deps.generatorHistory.entries.isEmpty)
    }

    /// The no-op guard has to cover the history too. Locking a vault that is already locked must not
    /// throw away a list the user may still be reading.
    func testLockVault_keepsTheHistoryWhenItIsANoOp() async throws {
        sut.screen = .login
        deps.generatorHistory.append("kept")

        sut.lockVault()
        // Fixed sleep, matching the other no-op tests: there is no positive state change to poll for.
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(deps.generatorHistory.entries.map(\.value), ["kept"])
    }

    // MARK: - SSH agent

    /// The agent's socket follows the vault's lock state, and the wiring is the thing under test
    /// here rather than the coordinator: `transitionToVault` is what tells the agent the vault
    /// became readable, and `lockVault()` is what tells it to stop.
    ///
    /// Both halves are asserted. A test that only checked the stop would pass against a coordinator
    /// that was never started — which is exactly the state a broken `vaultDidUnlock()` call leaves.
    func testLockVault_stopsTheSSHAgentThatTheVaultTransitionStarted() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        deps.sshAgentCoordinator.setEnabled(true)

        sut.handleLoginFlow(.vault)
        XCTAssertTrue(deps.sshAgentListener.isRunning,
                      "reaching the vault should have started the agent")

        sut.lockVault()
        try await waitUntil { !self.deps.sshAgentListener.isRunning }

        XCTAssertFalse(deps.sshAgentListener.isRunning)
    }
}
