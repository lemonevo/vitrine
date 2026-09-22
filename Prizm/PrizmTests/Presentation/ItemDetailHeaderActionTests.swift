import XCTest
@testable import Prizm

/// Which actions the detail header offers for a given item.
///
/// The rule under test is that the header never advertises something the item cannot do: a dead
/// "Copy password" on a secure note, or a "Copy code" beside a key that yields no code. Both would
/// look like a feature that failed, and the second is the one a user would blame their vault for.
@MainActor
final class ItemDetailHeaderActionTests: XCTestCase {

    // MARK: - Fixtures

    private func login(
        password: String? = "hunter2",
        totp: String? = nil,
        uris: [String] = []
    ) -> VaultItem {
        VaultItem(
            id: "i-1", name: "Example", isFavorite: false, isDeleted: false,
            creationDate: .distantPast, revisionDate: .distantPast,
            content: .login(LoginContent(
                username: "user@example.com", password: password,
                uris: uris.map { LoginURI(uri: $0, matchType: nil) },
                totp: totp, notes: nil, customFields: []))
        )
    }

    private func note() -> VaultItem {
        VaultItem(
            id: "i-2", name: "Note", isFavorite: false, isDeleted: false,
            creationDate: .distantPast, revisionDate: .distantPast,
            content: .secureNote(SecureNoteContent(notes: "text", customFields: []))
        )
    }

    private func card() -> VaultItem {
        VaultItem(
            id: "i-3", name: "Card", isFavorite: false, isDeleted: false,
            creationDate: .distantPast, revisionDate: .distantPast,
            content: .card(CardContent(cardholderName: "A", brand: "Visa", number: "4111111111111111",
                                       expMonth: "1", expYear: "2030", code: "123",
                                       notes: nil, customFields: []))
        )
    }

    /// A key the generator accepts. Base32 for "badsecret" — the same shape a real authenticator
    /// app hands out.
    private let validTOTPSecret = "JBSWY3DPEHPK3PXP"

    private var generator: any TOTPGenerator { TOTPGeneratorImpl() }

    // MARK: - Non-login items

    func test_secureNote_offersNothing() {
        XCTAssertEqual(
            ItemDetailView.headerActions(for: note(), totpGenerator: generator), [],
            "a secure note holds no password, no code and no site to open"
        )
    }

    func test_card_offersNothing() {
        XCTAssertEqual(ItemDetailView.headerActions(for: card(), totpGenerator: generator), [])
    }

    // MARK: - Login items

    func test_loginWithEverything_offersAllThreeInOrder() {
        let actions = ItemDetailView.headerActions(
            for: login(totp: validTOTPSecret, uris: ["https://example.com"]),
            totpGenerator: generator
        )
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.first, .copyPassword)
        XCTAssertEqual(actions[1], .copyCode)
        XCTAssertEqual(actions.last, .openWebsite(URL(string: "https://example.com")!))
    }

    func test_loginWithoutPassword_omitsCopyPassword() {
        let actions = ItemDetailView.headerActions(for: login(password: nil), totpGenerator: generator)
        XCTAssertFalse(actions.contains(.copyPassword))
    }

    func test_loginWithEmptyPassword_omitsCopyPassword() {
        let actions = ItemDetailView.headerActions(for: login(password: ""), totpGenerator: generator)
        XCTAssertFalse(actions.contains(.copyPassword),
                       "an empty password is not a value the button could usefully copy")
    }

    func test_loginWithoutTOTP_omitsCopyCode() {
        let actions = ItemDetailView.headerActions(for: login(totp: nil), totpGenerator: generator)
        XCTAssertFalse(actions.contains(.copyCode))
    }

    /// The case that matters most: a stored key that produces no code. The row in the Credentials
    /// card already says so; a header button beside it would be a second, louder and emptier claim.
    func test_loginWithUnusableTOTP_omitsCopyCode() {
        let actions = ItemDetailView.headerActions(
            for: login(totp: "not base32 at all !!!"), totpGenerator: generator
        )
        XCTAssertFalse(actions.contains(.copyCode))
    }

    func test_loginWithoutURIs_omitsOpenWebsite() {
        let actions = ItemDetailView.headerActions(for: login(uris: []), totpGenerator: generator)
        XCTAssertFalse(actions.contains(where: {
            if case .openWebsite = $0 { return true } else { return false }
        }))
    }

    /// No generator injected means no way to derive a code, so no button — rather than a button whose
    /// press would silently do nothing. Previews and the screenshot harness land here.
    func test_noGenerator_omitsCopyCodeEvenWithAValidKey() {
        let actions = ItemDetailView.headerActions(
            for: login(totp: validTOTPSecret), totpGenerator: nil
        )
        XCTAssertFalse(actions.contains(.copyCode))
    }

    // MARK: - Identity

    func test_actionIdentity_isStablePerAction() {
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(ItemDetailView.DetailAction.openWebsite(url).id,
                       ItemDetailView.DetailAction.openWebsite(url).id)
        XCTAssertNotEqual(ItemDetailView.DetailAction.openWebsite(url).id,
                          ItemDetailView.DetailAction.openWebsite(URL(string: "https://other.test")!).id)
    }
}
