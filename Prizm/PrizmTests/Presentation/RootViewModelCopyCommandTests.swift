import XCTest
import AppKit
@testable import Prizm

// MARK: - RootViewModelCopyCommandTests

/// Regression tests for the ⌃⌘C "Copy Code" command (FEATURE-GAP-ANALYSIS.md §2.1).
///
/// The defect: `Copy Code` put `login.totp` on the clipboard. That value is the **long-lived
/// shared secret**, not the six-digit code the menu item's name promises — so a user pasting it
/// into a site's "verification code" field handed over their second factor permanently, and every
/// clipboard manager on the machine captured it too.
///
/// These tests drive the real command and read the real `NSPasteboard`, because the guarantee is
/// about what the command *writes*, not about what a helper function returns.
@MainActor
final class RootViewModelCopyCommandTests: XCTestCase {

    private var mockAuth: MockAuthRepository!
    private var mockVault: MockVaultRepository!
    private var sut: RootViewModel!

    /// A recognisable stored TOTP seed. It must never reach the clipboard.
    private let seed = "JBSWY3DPEHPK3PXP"

    override func setUp() async throws {
        try await super.setUp()
        NSPasteboard.general.clearContents()
    }

    override func tearDown() async throws {
        NSPasteboard.general.clearContents()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a `RootViewModel` whose TOTP generator is stubbed, so the test can tell the
    /// generated value apart from the seed instead of depending on the current wall clock.
    private func makeSUT(code: String? = "654321") -> RootViewModel {
        mockAuth  = MockAuthRepository()
        mockVault = MockVaultRepository()
        let deps = MockRootDependencies(auth: mockAuth, vault: mockVault,
                                        totpGenerator: StubTOTPGenerator(code: code))
        return RootViewModel(container: deps)
    }

    private func loginItem(totp: String?) -> VaultItem {
        VaultItem(
            id: "item-1", name: "Example",
            isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .login(LoginContent(
                username: "alice@example.com", password: "hunter2",
                uris: [LoginURI(uri: "https://example.com", matchType: .domain)],
                totp: totp, notes: nil, customFields: []
            ))
        )
    }

    /// Selects an item and waits for `RootViewModel` to derive `selectedLogin` from it.
    private func select(_ item: VaultItem) async throws {
        sut.vaultBrowserVM.itemSelection = item
        let deadline = ContinuousClock.now + .milliseconds(500)
        while sut.selectedLogin == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(sut.selectedLogin, "The selected item should reach the view model")
    }

    private var pasteboardValue: String? {
        NSPasteboard.general.string(forType: .string)
    }

    // MARK: - Copy Code copies the code

    func testCopyCode_copiesTheGeneratedCodeNotTheSeed() async throws {
        sut = makeSUT(code: "654321")
        try await select(loginItem(totp: seed))

        sut.copySelectedField(.totp)

        XCTAssertEqual(pasteboardValue, "654321", "Copy Code should copy the generated one-time code")
        XCTAssertNotEqual(pasteboardValue, seed,
                          "Copy Code must never put the long-lived TOTP seed on the clipboard")
    }

    func testCopyCode_isAvailableOnlyWhenACodeCanBeDerived() async throws {
        sut = makeSUT(code: nil)
        try await select(loginItem(totp: seed))
        XCTAssertFalse(sut.selectedFieldAvailable(.totp),
                       "The command should be disabled when no code can be derived")

        sut = makeSUT(code: "123456")
        try await select(loginItem(totp: seed))
        XCTAssertTrue(sut.selectedFieldAvailable(.totp))
    }

    func testCopyCode_unusableSeed_copiesNothing() async throws {
        sut = makeSUT(code: nil)
        try await select(loginItem(totp: seed))

        sut.copySelectedField(.totp)

        XCTAssertNil(pasteboardValue, "With no derivable code the command should be a no-op")
    }

    func testCopyCode_noStoredSeed_copiesNothing() async throws {
        sut = makeSUT()
        try await select(loginItem(totp: nil))

        sut.copySelectedField(.totp)

        XCTAssertNil(pasteboardValue)
    }

    // MARK: - No command hands out the seed

    func testNoCopyCommandEverWritesTheSeed() async throws {
        sut = makeSUT()
        try await select(loginItem(totp: seed))

        let fields: [RootViewModel.CopyableField] = [.username, .password, .totp, .website]
        for field in fields {
            NSPasteboard.general.clearContents()
            sut.copySelectedField(field)
            XCTAssertNotEqual(pasteboardValue, seed,
                              "No copy command may write the TOTP seed (field: \(field))")
        }
    }

    // MARK: - The other commands are unaffected

    func testCopyUsername_stillCopiesThePlainValue() async throws {
        sut = makeSUT()
        try await select(loginItem(totp: seed))

        sut.copySelectedField(.username)

        XCTAssertEqual(pasteboardValue, "alice@example.com")
    }

    func testCopyWebsite_stillCopiesTheFirstURI() async throws {
        sut = makeSUT()
        try await select(loginItem(totp: seed))

        sut.copySelectedField(.website)

        XCTAssertEqual(pasteboardValue, "https://example.com")
    }
}
