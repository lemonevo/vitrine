import XCTest
@testable import Prizm

/// The app-level half of the teardown: that both session-ending paths clear the presentation layer,
/// and that the copy commands are closed on the unlock screen.
///
/// What is asserted *here* and not in `VaultBrowserViewModelSessionTeardownTests` is the wiring —
/// that a property cleared on one path is cleared on the other too. That is the property that makes
/// the two paths safe to have at all.
@MainActor
final class RootViewModelSessionTeardownTests: XCTestCase {

    private var mockAuth:  MockAuthRepository!
    private var mockVault: MockVaultRepository!
    private var deps:      MockRootDependencies!
    private var sut:       RootViewModel!

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
        mockAuth  = MockAuthRepository()
        mockVault = MockVaultRepository()
        deps      = MockRootDependencies(auth: mockAuth, vault: mockVault)
        // A real search, so the browser view model actually loads items from the store and the
        // assertions below are about clearing them rather than about a stub returning nothing.
        // Set before `RootViewModel` is built, because that is what builds the view model.
        deps.searchUseCase = SearchVaultUseCaseImpl(vault: mockVault)
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

    private func loginItem(id: String = "1", name: String = "GitHub") -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: "octocat", password: "s3cret", uris: [
                LoginURI(uri: "https://github.com", matchType: nil)
            ], totp: "JBSWY3DPEHPK3PXP", notes: nil, customFields: []))
        )
    }

    /// Puts the app into the state the bug needs: unlocked, with an item loaded and selected, so
    /// every holder of decrypted content is populated.
    private func unlockWithAnItemSelected() async {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault
        await mockVault.populate(
            items:         [loginItem()],
            folders:       [Folder(id: "f1", name: "Work")],
            organizations: [Organization(id: "o1", name: "Acme", role: .user)],
            collections:   [OrgCollection(id: "c1", organizationId: "o1", name: "Shared")],
            syncedAt:      Date()
        )
        sut.vaultBrowserVM.refreshItems()
        sut.vaultBrowserVM.refreshCounts()
        sut.vaultBrowserVM.refreshFolders()
        sut.vaultBrowserVM.refreshOrganizations()
        await waitUntil { !self.sut.vaultBrowserVM.displayedItems.isEmpty }
        await waitUntil { !self.sut.vaultBrowserVM.folders.isEmpty }
        sut.vaultBrowserVM.selectItem(id: "1")
        await waitUntil { self.sut.selectedLogin != nil }
        // Last, not first: the login flow's initial emission is delivered on the main queue and
        // calls `handleLoginFlow(.login)`, which sets `screen` back to `.login`. Setting it here
        // makes the unlocked state the last word rather than a value that gets overwritten.
        sut.screen = .vault
    }

    // MARK: - 3.1 / 3.2 the copy commands

    /// The concrete bug: after a lock the menu stayed enabled, because it was gated only on whether
    /// a login was selected — and nothing cleared the selection.
    func test_copyCommands_areUnavailableWhileLocked() async throws {
        await unlockWithAnItemSelected()
        XCTAssertTrue(sut.selectedFieldAvailable(RootViewModel.CopyableField.password), "precondition: available while unlocked")

        sut.screen = .unlock

        for field in [RootViewModel.CopyableField.username, .password, .totp, .website] {
            XCTAssertFalse(
                sut.selectedFieldAvailable(field),
                "\(field) must not be copyable from the unlock screen"
            )
        }
    }

    /// The regression guard: a gate that is always closed is not a gate.
    func test_copyCommands_areAvailableWhileUnlocked() async throws {
        await unlockWithAnItemSelected()

        XCTAssertTrue(sut.selectedFieldAvailable(RootViewModel.CopyableField.username))
        XCTAssertTrue(sut.selectedFieldAvailable(RootViewModel.CopyableField.password))
        XCTAssertTrue(sut.selectedFieldAvailable(RootViewModel.CopyableField.totp))
        XCTAssertTrue(sut.selectedFieldAvailable(RootViewModel.CopyableField.website))
    }

    // MARK: - 6.1 lock clears the presentation layer

    func test_lockVault_clearsEverythingTheSessionHeld() async throws {
        await unlockWithAnItemSelected()

        sut.lockVault()
        await waitUntil { self.sut.vaultBrowserVM.displayedItems.isEmpty }

        XCTAssertTrue(sut.vaultBrowserVM.displayedItems.isEmpty)
        XCTAssertNil(sut.vaultBrowserVM.itemSelection)
        XCTAssertNil(sut.selectedLogin, "the selection-derived login content must go too")
        XCTAssertTrue(sut.vaultBrowserVM.folders.isEmpty)
        XCTAssertTrue(sut.vaultBrowserVM.organizations.isEmpty)
        XCTAssertTrue(sut.vaultBrowserVM.searchQuery.isEmpty)
    }

    // MARK: - 6.2 sign-out clears the same set

    /// Asserted as the same list as 6.1. A property cleared on the lock path and missed on the
    /// sign-out path is exactly the drift this shape is here to catch.
    func test_signOut_clearsEverythingTheSessionHeld() async throws {
        await unlockWithAnItemSelected()
        sut.vaultBrowserVM.searchQuery = "hunter2"

        sut.signOut()
        await waitUntil { if case .login = self.sut.screen { return true }; return false }
        await waitUntil { self.sut.vaultBrowserVM.displayedItems.isEmpty }

        XCTAssertTrue(sut.vaultBrowserVM.displayedItems.isEmpty)
        XCTAssertNil(sut.vaultBrowserVM.itemSelection)
        XCTAssertNil(sut.selectedLogin)
        XCTAssertTrue(sut.vaultBrowserVM.folders.isEmpty)
        XCTAssertTrue(sut.vaultBrowserVM.organizations.isEmpty)
        XCTAssertTrue(sut.vaultBrowserVM.searchQuery.isEmpty)
    }

    // MARK: - 6.3 the epoch moves before the teardown, not after

    /// If the epoch were advanced at the end of the teardown, a sync completing in the middle of it
    /// would see the old session and repopulate a store that had just been cleared. The observable
    /// consequence is that the epoch has already moved while the teardown is still running.
    func test_lockVault_advancesTheEpochBeforeItsTeardownRuns() async throws {
        await unlockWithAnItemSelected()
        mockAuth.lockVaultDelay = .milliseconds(400)
        let before = deps.sessionEpoch.current()

        sut.lockVault()

        var moved = false
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if deps.sessionEpoch.isCurrent(before) == false { moved = true; break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertTrue(moved, "the epoch must move as the lock starts, not as it finishes")
        XCTAssertFalse(
            mockVault.clearVaultCalled,
            "precondition for this assertion: the teardown is still in flight"
        )
    }

    func test_signOut_advancesTheEpoch() async throws {
        await unlockWithAnItemSelected()
        let before = deps.sessionEpoch.current()

        sut.signOut()

        var moved = false
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if deps.sessionEpoch.isCurrent(before) == false { moved = true; break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(moved)
    }
}
