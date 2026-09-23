import XCTest
@testable import Prizm

// MARK: - RootViewModelHealthReportTests

/// Tests for opening, closing and tearing down the health report sheet.
///
/// Kept out of `RootViewModelLockTests` and `RootViewModelSignOutTests` because those suites are
/// about how the screen changes; this one is about a piece of session state that has to survive
/// neither.
@MainActor
final class RootViewModelHealthReportTests: XCTestCase {

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

    override func setUp() async throws {
        try await super.setUp()
        mockAuth  = MockAuthRepository()
        mockVault = MockVaultRepository()
        deps      = MockRootDependencies(auth: mockAuth, vault: mockVault)
        sut       = RootViewModel(container: deps)
    }

    /// Yields to the main actor run loop until `condition` returns true or timeout.
    private func waitUntil(
        timeout: Duration = .milliseconds(500),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Presentation

    func test_presentHealthReport_whenUnlocked_createsAReport() {
        sut.screen = .vault

        sut.presentHealthReport()

        XCTAssertNotNil(sut.healthReportVM)
    }

    /// Locked means there is nothing decrypted to analyse. The command is disabled in the menu, but
    /// the guard is here so a keyboard shortcut cannot get past it either.
    func test_presentHealthReport_whenLocked_isANoOp() {
        sut.screen = .login

        sut.presentHealthReport()

        XCTAssertNil(sut.healthReportVM)
    }

    func test_dismissHealthReport_clearsTheReport() {
        sut.screen = .vault
        sut.presentHealthReport()

        sut.dismissHealthReport()

        XCTAssertNil(sut.healthReportVM)
    }

    /// Selecting a finding closes the report. Whether the item ends up selected is
    /// `VaultBrowserViewModel.selectItem`'s job, tested there — the mock vault is empty here, so
    /// there is no item for it to land on.
    func test_openItemFromHealthReport_closesTheReport() {
        sut.screen = .vault
        sut.presentHealthReport()

        sut.openItemFromHealthReport(id: "item-1")

        XCTAssertNil(sut.healthReportVM)
    }

    // MARK: - Enablement

    /// Derived from the screen rather than mirrored into a flag. The phase 1 ⌘R defect was a
    /// mirrored flag whose only update site never fired at launch, leaving the command permanently
    /// disabled.
    func test_menuBarCanRunHealthReport_followsTheUnlockedState() {
        sut.screen = .login
        XCTAssertFalse(sut.menuBarCanRunHealthReport)

        sut.screen = .vault
        XCTAssertTrue(sut.menuBarCanRunHealthReport)

        sut.screen = .unlock
        XCTAssertFalse(sut.menuBarCanRunHealthReport)
    }

    // MARK: - Teardown

    /// The report lists decrypted item names. Leaving it behind would keep decrypted content past
    /// the end of the session.
    func test_lockVault_dropsTheReport() async throws {
        mockAuth.stubbedStoredAccount = stubAccount
        sut.screen = .vault
        sut.presentHealthReport()
        XCTAssertNotNil(sut.healthReportVM, "precondition: the report should be open")

        sut.lockVault()
        try await waitUntil { self.sut.healthReportVM == nil }

        XCTAssertNil(sut.healthReportVM)
    }

    func test_signOut_dropsTheReport() async throws {
        sut.screen = .vault
        sut.presentHealthReport()
        XCTAssertNotNil(sut.healthReportVM, "precondition: the report should be open")

        sut.signOut()
        try await waitUntil { self.sut.healthReportVM == nil }

        XCTAssertNil(sut.healthReportVM)
    }
}
