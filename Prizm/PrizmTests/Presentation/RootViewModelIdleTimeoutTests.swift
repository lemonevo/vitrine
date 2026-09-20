import XCTest
@testable import Prizm

/// Tests for `RootViewModel`'s idle timeout, duplicate command and menu-bar state.
///
/// The idle monitor is a mock here: what matters at this level is that observation follows the
/// unlocked state and that each timeout action routes to an existing teardown path. The decision
/// itself is covered by `VaultIdleMonitorTests`.
@MainActor
final class RootViewModelIdleTimeoutTests: XCTestCase {

    private var mockAuth: MockAuthRepository!
    private var mockVault: MockVaultRepository!
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

    private func loginItem(id: String = "1", name: String = "GitHub", isDeleted: Bool = false) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: isDeleted,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: "octocat", password: "p", uris: [],
                                         totp: nil, notes: nil, customFields: []))
        )
    }

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

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Observation follows the unlocked state

    func test_unlockingStartsIdleObservation() async throws {
        sut.screen = .vault

        await waitUntil { self.deps.mockIdleMonitor.isRunning }

        XCTAssertTrue(deps.mockIdleMonitor.isRunning)
        XCTAssertGreaterThanOrEqual(deps.mockIdleMonitor.startCount, 1)
    }

    func test_syncingScreenCountsAsUnlocked() async throws {
        sut.screen = .syncing(message: "Syncing…")

        await waitUntil { self.deps.mockIdleMonitor.isRunning }

        XCTAssertTrue(deps.mockIdleMonitor.isRunning)
    }

    func test_lockingStopsIdleObservation() async throws {
        sut.screen = .vault
        await waitUntil { self.deps.mockIdleMonitor.isRunning }

        sut.screen = .unlock

        await waitUntil { !self.deps.mockIdleMonitor.isRunning }
        XCTAssertFalse(deps.mockIdleMonitor.isRunning)
    }

    /// A locked vault has nothing to lock; a timer running against the login screen would be pure
    /// overhead.
    func test_lockedScreensDoNotObserveInput() async throws {
        for screen in [RootViewModel.Screen.login, .loading, .unlock, .totpPrompt] {
            sut.screen = screen
            try? await Task.sleep(for: .milliseconds(30))
            XCTAssertFalse(deps.mockIdleMonitor.isRunning, "\(screen) must not observe idle time")
        }
    }

    // MARK: - Timeout actions

    func test_idleTimeout_lock_transitionsToUnlock() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault

        sut.handleIdleTimeout(.lock)

        await waitUntil { if case .unlock = self.sut.screen { return true }; return false }
        guard case .unlock = sut.screen else {
            return XCTFail("Expected .unlock, got \(sut.screen)")
        }
        XCTAssertEqual(mockAuth.lockVaultCalledCount, 1)
        XCTAssertTrue(mockVault.clearVaultCalled, "the vault cache must be cleared on lock")
    }

    func test_idleTimeout_signOut_transitionsToLogin() async throws {
        sut.screen = .vault

        sut.handleIdleTimeout(.signOut)

        await waitUntil { if case .login = self.sut.screen { return true }; return false }
        guard case .login = sut.screen else {
            return XCTFail("Expected .login, got \(sut.screen)")
        }
        XCTAssertTrue(mockAuth.signOutCalled)
        XCTAssertTrue(mockVault.clearVaultCalled)
    }

    /// The monitor is stopped when the vault is not unlocked, so a late callback must not tear down
    /// a session the user has already left.
    func test_idleTimeout_isIgnoredWhenTheVaultIsNotUnlocked() async throws {
        sut.screen = .login

        sut.handleIdleTimeout(.lock)
        sut.handleIdleTimeout(.signOut)
        try? await Task.sleep(for: .milliseconds(50))

        guard case .login = sut.screen else {
            return XCTFail("Expected .login, got \(sut.screen)")
        }
        XCTAssertFalse(mockAuth.signOutCalled)
        XCTAssertEqual(mockAuth.lockVaultCalledCount, 0)
    }

    // MARK: - Duplicate command

    func test_duplicateSelectedItem_forwardsTheSelectedId() async throws {
        sut.screen = .vault
        sut.vaultBrowserVM.itemSelection = loginItem(id: "42")

        sut.duplicateSelectedItem()

        await waitUntil { self.deps.duplicateUseCase.lastId != nil }
        XCTAssertEqual(deps.duplicateUseCase.lastId, "42")
        XCTAssertEqual(deps.duplicateUseCase.callCount, 1)
    }

    func test_duplicateSelectedItem_withNoSelection_doesNothing() async throws {
        sut.screen = .vault
        sut.vaultBrowserVM.itemSelection = nil

        sut.duplicateSelectedItem()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(deps.duplicateUseCase.callCount, 0)
    }

    // MARK: - Menu-bar state

    func test_menuBarCanDuplicate_tracksASelection() async throws {
        sut.screen = .vault

        sut.vaultBrowserVM.itemSelection = loginItem()
        await waitUntil { self.sut.menuBarCanDuplicate }

        XCTAssertTrue(sut.menuBarCanDuplicate)
    }

    /// A trashed item is restorable or deletable, not duplicable.
    func test_menuBarCanDuplicate_isFalseForATrashedItem() async throws {
        sut.vaultBrowserVM.itemSelection = loginItem(isDeleted: true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(sut.menuBarCanDuplicate)
    }

    /// Duplicating mid-edit would race the in-flight draft.
    func test_menuBarCanDuplicate_isFalseWhileTheEditSheetIsOpen() async throws {
        sut.vaultBrowserVM.itemSelection = loginItem()
        await waitUntil { self.sut.menuBarCanDuplicate }

        sut.vaultBrowserVM.handleEditSheetState(true)

        await waitUntil { !self.sut.menuBarCanDuplicate }
        XCTAssertFalse(sut.menuBarCanDuplicate)
    }

    /// ⌘R is one of the ways to start a sync, so the command must be enabled by unlocking alone.
    /// Deriving it only from `isSyncing` left it disabled until the first sync — which the shortcut
    /// itself was needed to start.
    func test_menuBarCanSync_enablesOnUnlockWithoutWaitingForASync() async throws {
        XCTAssertFalse(sut.menuBarCanSync, "a locked vault cannot sync")

        sut.screen = .vault

        await waitUntil { self.sut.menuBarCanSync }
        XCTAssertTrue(sut.menuBarCanSync)
    }

    func test_menuBarCanSync_disablesWhileSyncing() async throws {
        sut.screen = .vault
        await waitUntil { self.sut.menuBarCanSync }

        // Hold the sync in flight so the disabled state is observable rather than a race.
        deps.mockSyncUseCase.stubbedDelay = .milliseconds(400)
        sut.vaultBrowserVM.performManualSync()

        await waitUntil { !self.sut.menuBarCanSync }
        XCTAssertFalse(sut.menuBarCanSync, "a second sync must not be startable from the menu")

        await waitUntil { self.sut.menuBarCanSync }
        XCTAssertTrue(sut.menuBarCanSync, "…and the command must come back when the sync finishes")
    }

    func test_menuBarCanSync_disablesOnLock() async throws {
        sut.screen = .vault
        await waitUntil { self.sut.menuBarCanSync }

        sut.screen = .unlock

        await waitUntil { !self.sut.menuBarCanSync }
        XCTAssertFalse(sut.menuBarCanSync)
    }
}
