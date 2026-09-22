import Foundation
import XCTest
@testable import Prizm

// MARK: - VaultExportDocumentTests

/// Tests for the Bitwarden interchange format and the projection into and out of the entities.
///
/// The format was read out of `bitwarden/clients` rather than reconstructed (design D1), so the
/// assertions here are mostly about the details that source settled: that `match` is an integer,
/// that `collectionIds` is absent rather than empty for a personal item, that `passwordHistory`
/// is part of the format, and that deleted items never appear.
///
/// A separate suite covers the use cases; this one covers the value type, which has no I/O.
@MainActor
final class VaultExportDocumentTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func login(
        id: String = "item-1",
        name: String = "GitHub",
        username: String? = "octocat",
        password: String? = "hunter2",
        totp: String? = "JBSWY3DPEHPK3PXP",
        uris: [LoginURI] = [LoginURI(uri: "https://github.com", matchType: .defaultMatch)],
        notes: String? = "a note",
        customFields: [CustomField] = []
    ) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .login(LoginContent(
                username: username, password: password, uris: uris,
                totp: totp, notes: notes, customFields: customFields
            ))
        )
    }

    private func document(_ items: [VaultItem],
                          folders: [Folder] = [],
                          history: [String: [PasswordHistoryEntry]] = [:]) -> VaultExportDocument {
        VaultExportDocument(items: items, folders: folders, passwordHistory: history)
    }

    // MARK: - The document as a whole

    /// Every export this type produces is plaintext. If this ever reads `true` the importer will
    /// refuse the file it just wrote.
    func test_document_isNeverEncrypted() {
        XCTAssertFalse(document([login()]).encrypted)
    }

    /// Folders carry their id, which is the only reason an item's `folderId` resolves inside the
    /// file. `FolderExport` alone has just a name; the reference uses `FolderWithIdExport`.
    func test_folders_carryBothIdAndName() {
        let doc = document([], folders: [Folder(id: "f-1", name: "Work")])
        XCTAssertEqual(doc.folders, [ExportFolder(id: "f-1", name: "Work")])
    }

    /// The five integers are the server's `CipherType` enum. They must agree with
    /// `CipherMapper.mapContent` or a round trip through the file changes an item's type.
    func test_typeIntegers_matchTheWireFormat() {
        XCTAssertEqual(ExportItemType(.login).rawValue, 1)
        XCTAssertEqual(ExportItemType(.secureNote).rawValue, 2)
        XCTAssertEqual(ExportItemType(.card).rawValue, 3)
        XCTAssertEqual(ExportItemType(.identity).rawValue, 4)
        XCTAssertEqual(ExportItemType(.sshKey).rawValue, 5)
    }

    /// The mapping is total in both directions, so no item type can be silently mislabelled.
    func test_typeMapping_roundTripsForEveryCase() {
        for type in ItemType.allCases {
            XCTAssertEqual(ExportItemType(type).itemType, type)
        }
    }

    // MARK: - Per-type payloads

    func test_loginItem_carriesUsernamePasswordTOTPAndURIs() {
        let item = document([login()]).items[0]

        XCTAssertEqual(item.type, 1)
        XCTAssertEqual(item.login?.username, "octocat")
        XCTAssertEqual(item.login?.password, "hunter2")
        XCTAssertEqual(item.login?.totp, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(item.login?.uris?.count, 1)
        XCTAssertEqual(item.login?.uris?.first?.uri, "https://github.com")
    }

    /// The format stores Bitwarden's `UriMatchStrategySetting` integer, not a name — which is why
    /// `URIMatchType` maps its cases to those numbers by hand rather than numbering itself from zero.
    func test_loginURIMatch_isAnInteger() throws {
        let item = document([login()]).items[0]
        let uri  = try XCTUnwrap(item.login?.uris?.first)
        XCTAssertEqual(uri.match, 0, "`.defaultMatch` is raw value 0")

        let encoded = try JSONEncoder().encode(uri)
        let json    = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertTrue(json["match"] is Int, "the reference writes a number here, not a string")
    }

    /// A URI with no explicit strategy exports without the key rather than with a fabricated 0.
    func test_loginURI_withoutMatchType_omitsTheKey() {
        let item = document([login(uris: [LoginURI(uri: "https://example.com", matchType: nil)])]).items[0]
        XCTAssertNil(item.login?.uris?.first?.match)
    }

    func test_secureNoteItem_carriesGenericTypeZero() {
        let note = VaultItem(
            id: "n-1", name: "Recovery codes", isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .secureNote(SecureNoteContent(notes: "backup", customFields: []))
        )
        let item = document([note]).items[0]

        XCTAssertEqual(item.type, 2)
        XCTAssertEqual(item.secureNote?.type, 0)
        XCTAssertEqual(item.notes, "backup")
    }

    func test_cardItem_carriesTheCardPayload() {
        let card = VaultItem(
            id: "c-1", name: "Visa", isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .card(CardContent(
                cardholderName: "Ada Lovelace", brand: "Visa", number: "4111111111111111",
                expMonth: "04", expYear: "2030", code: "123",
                notes: nil, customFields: []
            ))
        )
        let item = document([card]).items[0]

        XCTAssertEqual(item.type, 3)
        XCTAssertEqual(item.card?.cardholderName, "Ada Lovelace")
        XCTAssertEqual(item.card?.number, "4111111111111111")
        XCTAssertEqual(item.card?.expMonth, "04")
    }

    func test_identityItem_carriesTheIdentityPayload() {
        let identity = VaultItem(
            id: "i-1", name: "Me", isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .identity(IdentityContent(
                title: "Dr", firstName: "Ada", middleName: nil, lastName: "Lovelace",
                address1: "1 Analytical Way", address2: nil, address3: nil,
                city: "London", state: nil, postalCode: "N1", country: "UK",
                company: nil, email: "ada@example.com", phone: nil, ssn: nil,
                username: "ada", passportNumber: nil, licenseNumber: nil,
                notes: nil, customFields: []
            ))
        )
        let item = document([identity]).items[0]

        XCTAssertEqual(item.type, 4)
        XCTAssertEqual(item.identity?.firstName, "Ada")
        XCTAssertEqual(item.identity?.city, "London")
        XCTAssertEqual(item.identity?.email, "ada@example.com")
    }

    func test_sshKeyItem_carriesTheSSHPayload() {
        let key = VaultItem(
            id: "k-1", name: "deploy key", isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .sshKey(SSHKeyContent(
                privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----",
                publicKey: "ssh-ed25519 AAAA",
                keyFingerprint: "SHA256:abc",
                notes: nil, customFields: []
            ))
        )
        let item = document([key]).items[0]

        XCTAssertEqual(item.type, 5)
        XCTAssertEqual(item.sshKey?.publicKey, "ssh-ed25519 AAAA")
        XCTAssertEqual(item.sshKey?.keyFingerprint, "SHA256:abc")
    }

    /// A card has no `login` key. Emitting an empty payload would make the file claim the item
    /// carries login data it does not have.
    func test_item_carriesOnlyItsOwnTypePayload() {
        let card = VaultItem(
            id: "c-1", name: "Visa", isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .card(CardContent(
                cardholderName: nil, brand: nil, number: nil,
                expMonth: nil, expYear: nil, code: nil, notes: nil, customFields: []
            ))
        )
        let item = document([card]).items[0]

        XCTAssertNil(item.login)
        XCTAssertNil(item.secureNote)
        XCTAssertNil(item.identity)
        XCTAssertNil(item.sshKey)
        XCTAssertNotNil(item.card)
    }

    // MARK: - Notes and custom fields are top-level

    /// The reference's `LoginExport` has no `notes` field: notes and custom fields sit on the item.
    func test_notesAndFields_areTopLevel_notInsideThePayload() throws {
        let field = CustomField(name: "PIN", value: "1234", type: .hidden, linkedId: nil)
        let item  = document([login(notes: "top level", customFields: [field])]).items[0]

        XCTAssertEqual(item.notes, "top level")
        XCTAssertEqual(item.fields?.count, 1)
        XCTAssertEqual(item.fields?.first?.name, "PIN")
        XCTAssertEqual(item.fields?.first?.type, 1)

        let encoded = try JSONEncoder().encode(item)
        let json    = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNotNil(json["notes"], "notes belongs on the item")
        let loginJSON = try XCTUnwrap(json["login"] as? [String: Any])
        XCTAssertNil(loginJSON["notes"], "the per-type payload must not carry notes")
    }

    /// An item with no fields exports without the key rather than with an empty array.
    func test_itemWithoutFields_omitsTheKey() {
        XCTAssertNil(document([login(customFields: [])]).items[0].fields)
    }

    /// `linkedId` is only meaningful for `.linked`; writing it for a text field would make the
    /// file claim a relationship that does not exist.
    func test_linkedId_isWrittenOnlyForLinkedFields() {
        let linked = CustomField(name: "u", value: nil, type: .linked, linkedId: .loginUsername)
        let text   = CustomField(name: "t", value: "v", type: .text, linkedId: .loginUsername)

        let item = document([login(customFields: [linked, text])]).items[0]

        XCTAssertEqual(item.fields?[0].linkedId, 100)
        XCTAssertNil(item.fields?[1].linkedId)
    }

    // MARK: - Organisation membership

    /// The deliberate difference from the reference: the official *individual* export drops these
    /// items entirely, so "export my vault" silently omits everything held through an org.
    func test_organisationItem_keepsItsMembership() {
        var item = login()
        item = VaultItem(
            id: item.id, name: item.name, isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch, content: item.content,
            organizationId: "org-1", collectionIds: ["col-1", "col-2"]
        )

        let exported = document([item]).items[0]

        XCTAssertEqual(exported.organizationId, "org-1")
        XCTAssertEqual(exported.collectionIds, ["col-1", "col-2"])
    }

    /// The reference writes `collectionIds = null` for a personal item, not `[]`.
    func test_personalItem_hasNoCollectionIds() throws {
        let item    = document([login()]).items[0]
        XCTAssertNil(item.collectionIds)

        let encoded = try JSONEncoder().encode(item)
        let json    = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertFalse(json.keys.contains("collectionIds"), "the key is omitted, not set to []")
    }

    // MARK: - Dates

    /// `JSON.stringify` of a JS `Date` is `toISOString()`: UTC with millisecond precision.
    func test_dates_areISO8601UTCWithFractionalSeconds() throws {
        let item = document([login()]).items[0]
        let raw  = try XCTUnwrap(item.creationDate)

        XCTAssertTrue(raw.hasSuffix("Z"), "the reference writes UTC: \(raw)")
        XCTAssertTrue(raw.contains("."), "millisecond precision: \(raw)")

        let parsed = try XCTUnwrap(VaultExportDocument.parseISO8601(raw))
        XCTAssertEqual(parsed.timeIntervalSince1970, epoch.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Vaultwarden writes both forms, so the parser has to accept both.
    func test_parseISO8601_acceptsAStringWithoutFractionalSeconds() {
        XCTAssertNotNil(VaultExportDocument.parseISO8601("2023-11-14T22:13:20Z"))
        XCTAssertNil(VaultExportDocument.parseISO8601("not a date"))
    }

    /// Trash is deliberately not part of a backup, and this type is only ever built from the
    /// active vault, so `deletedDate` is never written even though the model carries it.
    func test_deletedDate_isNeverWritten() {
        XCTAssertNil(document([login()]).items[0].deletedDate)
    }

    // MARK: - Password history

    /// The format *does* carry previous passwords, as `{ password, lastUsedDate }`. The first
    /// draft of the design claimed otherwise; this test pins the corrected behaviour.
    func test_passwordHistory_isExportedWhenPresent() throws {
        let entry = PasswordHistoryEntry(password: "old-hunter1", lastUsedDate: epoch)
        let item  = document([login()], history: ["item-1": [entry]]).items[0]

        let history = try XCTUnwrap(item.passwordHistory)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].password, "old-hunter1")
        XCTAssertNotNil(history[0].lastUsedDate)
    }

    /// An entry with no date exports without one rather than with an invented timestamp.
    func test_passwordHistory_withoutDate_omitsTheDate() {
        let entry = PasswordHistoryEntry(password: "old", lastUsedDate: nil)
        let item  = document([login()], history: ["item-1": [entry]]).items[0]
        XCTAssertNil(item.passwordHistory?.first?.lastUsedDate)
    }

    /// Most items have none. The key is omitted rather than written as an empty array.
    func test_passwordHistory_isOmittedWhenAbsent() {
        XCTAssertNil(document([login()]).items[0].passwordHistory)
        XCTAssertNil(document([login()], history: ["item-1": []]).items[0].passwordHistory)
    }

    // MARK: - Re-prompt

    func test_reprompt_isExported() {
        let item = VaultItem(
            id: "item-1", name: "Bank", isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .login(LoginContent(username: nil, password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: [])),
            reprompt: 1
        )
        XCTAssertEqual(document([item]).items[0].reprompt, 1)
    }

    func test_favorite_isExported() {
        let item = VaultItem(
            id: "item-1", name: "GitHub", isFavorite: true, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .login(LoginContent(username: nil, password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: []))
        )
        XCTAssertTrue(document([item]).items[0].favorite)
    }

    // MARK: - Encoding

    /// Without `.withoutEscapingSlashes` every URL is written `https:\/\/…`. Valid JSON, but the
    /// file stops being readable to the person trying to verify their own backup.
    func test_encoding_doesNotEscapeSlashes() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document([login()]))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("https://github.com"))
        XCTAssertFalse(text.contains("https:\\/\\/github.com"))
    }
}
