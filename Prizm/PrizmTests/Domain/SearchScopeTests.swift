import XCTest
@testable import Prizm

/// Tests for the widened search scope (Phase 1 §7).
///
/// Before this change the search only looked at the name plus a handful of per-type fields, so a
/// value the user could see in the item — a note, a custom field, the folder it lives in — was not
/// findable. The risk of widening it is over-matching, so half of this file is about what must
/// *still* be found.
///
/// `XCTAssertEqual` takes its arguments as autoclosures, which cannot contain `await`, so every
/// query is bound to a local first.
@MainActor
final class SearchScopeTests: XCTestCase {

    private var vault: VaultRepositoryImpl!
    private var sut: SearchVaultUseCaseImpl!

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Helpers

    /// The ids a query returns, in the order the repository produced them.
    private func ids(_ query: String, in selection: SidebarSelection = .allItems) async throws -> [String] {
        try await sut.execute(query: query, in: selection).map(\.id)
    }

    private func populate(_ items: [VaultItem], folders: [Folder] = []) async {
        await vault.populate(items: items, folders: folders, organizations: [],
                             collections: [], syncedAt: now)
    }

    private func login(id: String, name: String,
                       notes: String? = nil,
                       customFields: [CustomField] = [],
                       folderId: String? = nil) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .login(LoginContent(
                username: "user-\(id)", password: "p", uris: [],
                totp: nil, notes: notes, customFields: customFields
            )),
            folderId: folderId
        )
    }

    private func secureNote(id: String, name: String,
                            notes: String? = nil,
                            customFields: [CustomField] = []) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .secureNote(SecureNoteContent(notes: notes, customFields: customFields))
        )
    }

    private func sshKey(id: String, name: String, notes: String? = nil) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .sshKey(SSHKeyContent(privateKey: "priv", publicKey: "pub",
                                           keyFingerprint: "SHA256:abc",
                                           notes: notes, customFields: []))
        )
    }

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        vault = VaultRepositoryImpl(apiClient: MockPrizmAPIClient(), crypto: MockPrizmCryptoService())
        sut   = SearchVaultUseCaseImpl(vault: vault)
    }

    override func tearDown() async throws {
        vault = nil
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Notes (every item type)

    func test_search_matchesLoginNotes() async throws {
        await populate([login(id: "1", name: "Alpha", notes: "the recovery phrase is zephyr")])

        let result = try await ids("zephyr")
        XCTAssertEqual(result, ["1"])
    }

    func test_search_matchesSecureNoteBody() async throws {
        await populate([secureNote(id: "1", name: "Alpha", notes: "contains zephyr")])

        let result = try await ids("zephyr")
        XCTAssertEqual(result, ["1"])
    }

    func test_search_matchesSSHKeyNotes() async throws {
        await populate([sshKey(id: "1", name: "Alpha", notes: "zephyr")])

        let result = try await ids("zephyr")
        XCTAssertEqual(result, ["1"])
    }

    /// Notes on a card and on an identity reach the same `ItemContent.notes` accessor, but the
    /// accessor has to cover all five content types for this to hold.
    func test_search_matchesCardAndIdentityNotes() async throws {
        let card = VaultItem(
            id: "1", name: "Card", isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .card(CardContent(cardholderName: "Alice", brand: nil, number: nil,
                                       expMonth: nil, expYear: nil, code: nil,
                                       notes: "zephyr", customFields: []))
        )
        let identity = VaultItem(
            id: "2", name: "Identity", isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .identity(IdentityContent(title: nil, firstName: nil, middleName: nil, lastName: nil,
                                               address1: nil, address2: nil, address3: nil, city: nil,
                                               state: nil, postalCode: nil, country: nil, company: nil,
                                               email: nil, phone: nil, ssn: nil, username: nil,
                                               passportNumber: nil, licenseNumber: nil,
                                               notes: "zephyr", customFields: []))
        )
        await populate([card, identity])

        let result = try await ids("zephyr")
        XCTAssertEqual(Set(result), Set(["1", "2"]))
    }

    // MARK: - Custom fields (every item type)

    func test_search_matchesCustomFieldName() async throws {
        await populate([login(id: "1", name: "Alpha",
                              customFields: [CustomField(name: "recoveryEmail", value: "x",
                                                         type: .text, linkedId: nil)])])

        let result = try await ids("recoveryemail")
        XCTAssertEqual(result, ["1"])
    }

    func test_search_matchesCustomFieldValue() async throws {
        await populate([login(id: "1", name: "Alpha",
                              customFields: [CustomField(name: "env", value: "zephyr-prod",
                                                         type: .text, linkedId: nil)])])

        let result = try await ids("zephyr")
        XCTAssertEqual(result, ["1"])
    }

    func test_search_matchesCustomFieldOnANonLoginItem() async throws {
        await populate([secureNote(id: "1", name: "Alpha",
                                   customFields: [CustomField(name: "env", value: "zephyr",
                                                              type: .text, linkedId: nil)])])

        let result = try await ids("zephyr")
        XCTAssertEqual(result, ["1"])
    }

    /// A custom field with no value (a boolean, or a hidden field left empty) must not crash the
    /// matcher and must not match on its `nil` value.
    func test_search_customFieldWithoutAValueDoesNotMatch() async throws {
        await populate([login(id: "1", name: "Alpha",
                              customFields: [CustomField(name: "flag", value: nil,
                                                         type: .boolean, linkedId: nil)])])

        let unmatched = try await ids("zephyr")
        XCTAssertTrue(unmatched.isEmpty)

        let matched = try await ids("flag")
        XCTAssertEqual(matched, ["1"])
    }

    // MARK: - Folder names

    func test_search_matchesTheFolderName() async throws {
        await populate([login(id: "1", name: "Alpha", folderId: "f-1")],
                       folders: [Folder(id: "f-1", name: "Zephyr Project")])

        let result = try await ids("zephyr")
        XCTAssertEqual(result, ["1"])
    }

    func test_search_doesNotMatchAFolderTheItemIsNotIn() async throws {
        await populate([login(id: "1", name: "Alpha", folderId: "f-1")],
                       folders: [Folder(id: "f-1", name: "Work"),
                                 Folder(id: "f-2", name: "Zephyr Project")])

        let result = try await ids("zephyr")
        XCTAssertTrue(result.isEmpty)
    }

    /// An item with no folder must not match a folder-name query, and must not crash resolving one.
    func test_search_itemWithoutAFolderIsSafe() async throws {
        await populate([login(id: "1", name: "Alpha")],
                       folders: [Folder(id: "f-1", name: "Zephyr")])

        let result = try await ids("zephyr")
        XCTAssertTrue(result.isEmpty)
    }

    /// A dangling `folderId` (the folder was deleted while the item still references it) must be
    /// treated as "no folder name", not as a match or a crash.
    func test_search_danglingFolderIdIsIgnored() async throws {
        await populate([login(id: "1", name: "Alpha", folderId: "gone")])

        let result = try await ids("zephyr")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Previously matching queries still match

    func test_search_nameUsernameAndURIStillMatch() async throws {
        let item = VaultItem(
            id: "1", name: "GitHub", isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .login(LoginContent(
                username: "octocat", password: "p",
                uris: [LoginURI(uri: "https://github.com", matchType: nil)],
                totp: nil, notes: nil, customFields: []
            ))
        )
        await populate([item])

        for query in ["git", "octocat", "github.com"] {
            let result = try await ids(query)
            XCTAssertEqual(result, ["1"], "\(query) used to match and must keep matching")
        }
    }

    func test_search_cardholderAndIdentityEmailStillMatch() async throws {
        let card = VaultItem(
            id: "1", name: "My Visa", isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .card(CardContent(cardholderName: "Alice Smith", brand: nil, number: nil,
                                       expMonth: nil, expYear: nil, code: nil,
                                       notes: nil, customFields: []))
        )
        let identity = VaultItem(
            id: "2", name: "Work ID", isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .identity(IdentityContent(title: nil, firstName: nil, middleName: nil, lastName: nil,
                                               address1: nil, address2: nil, address3: nil, city: nil,
                                               state: nil, postalCode: nil, country: nil, company: "Acme",
                                               email: "alice@acme.com", phone: nil, ssn: nil, username: nil,
                                               passportNumber: nil, licenseNumber: nil,
                                               notes: nil, customFields: []))
        )
        await populate([card, identity])

        let byName  = try await ids("alice smith")
        let byEmail = try await ids("alice@acme")
        let byOrg   = try await ids("acme")

        XCTAssertEqual(byName, ["1"])
        XCTAssertEqual(byEmail, ["2"])
        XCTAssertEqual(byOrg, ["2"])
    }

    func test_search_isCaseInsensitiveForTheWidenedFields() async throws {
        await populate([login(id: "1", name: "Alpha", notes: "ZEPHYR")])

        let lower = try await ids("zephyr")
        let mixed = try await ids("ZePhYr")

        XCTAssertEqual(lower, ["1"])
        XCTAssertEqual(mixed, ["1"])
    }

    // MARK: - Scoping and emptiness are unchanged

    func test_search_emptyQueryReturnsEverythingInScope() async throws {
        await populate([login(id: "1", name: "Alpha"), login(id: "2", name: "Bravo")])

        let result = try await ids("")
        XCTAssertEqual(result, ["1", "2"])
    }

    /// Widening what a query matches must not widen *where* it looks: a search in Trash still only
    /// searches Trash.
    func test_search_staysScopedToTheSelection() async throws {
        var trashed = login(id: "1", name: "Alpha", notes: "zephyr")
        trashed = trashed.with(isDeleted: true)
        await populate([trashed, login(id: "2", name: "Bravo", notes: "zephyr")])

        let inTrash = try await ids("zephyr", in: .trash)
        let inAll   = try await ids("zephyr", in: .allItems)

        XCTAssertEqual(inTrash, ["1"])
        XCTAssertEqual(inAll, ["2"])
    }

    func test_search_noMatchReturnsEmpty() async throws {
        await populate([login(id: "1", name: "Alpha", notes: "hello")])

        let result = try await ids("zephyr")
        XCTAssertTrue(result.isEmpty)
    }
}
