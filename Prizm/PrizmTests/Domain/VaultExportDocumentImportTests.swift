import Foundation
import XCTest
@testable import Prizm

// MARK: - VaultExportDocumentImportTests

/// Tests for reading an export back: decoding, folder resolution and the projection into drafts.
///
/// Separate from `VaultExportDocumentTests` because the two directions fail differently. The
/// writing side cannot fail — it is a projection of already-valid entities. The reading side is
/// handed a file that may be anything at all, so most of what matters here is which refusal the
/// user gets and which problems are survivable rather than fatal.
@MainActor
final class VaultExportDocumentImportTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    /// A minimal but complete export, built as JSON text so the tests exercise the real decoder
    /// rather than a round trip through the encoder (which could hide a symmetric mistake).
    ///
    /// `items` is wrapped in brackets here so each call site can pass one object or several
    /// without having to remember the array itself.
    private func json(_ items: String, folders: String = "[]", encrypted: String = "false") -> Data {
        Data("""
        { "encrypted": \(encrypted), "folders": \(folders), "items": [\(items)] }
        """.utf8)
    }

    private let loginItem = """
    { "id": "file-1", "type": 1, "name": "GitHub", "favorite": false, "reprompt": 0,
      "login": { "username": "octocat", "password": "hunter2",
                 "uris": [ { "uri": "https://github.com", "match": 0 } ] } }
    """

    // MARK: - Decoding refusals

    /// Not JSON at all.
    func test_decode_refusesNonJSON() {
        XCTAssertThrowsError(try VaultExportDocument.decode(from: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? VaultExportDocumentError, .notAnUnencryptedExport)
        }
    }

    /// JSON, but not an export: there is no `items` array.
    func test_decode_refusesJSONWithoutItems() {
        let data = Data(#"{ "encrypted": false, "folders": [] }"#.utf8)
        XCTAssertThrowsError(try VaultExportDocument.decode(from: data)) { error in
            XCTAssertEqual(error as? VaultExportDocumentError, .notAnUnencryptedExport)
        }
    }

    /// An encrypted export *is* a real export, so it gets its own message. Reporting "not an
    /// export" for a file the user exported from Bitwarden would be false and unhelpful.
    func test_decode_refusesAnEncryptedExport_distinctlyFromNotAnExport() {
        let data = json(loginItem, encrypted: "true")
        XCTAssertThrowsError(try VaultExportDocument.decode(from: data)) { error in
            XCTAssertEqual(error as? VaultExportDocumentError, .encryptedExportUnsupported)
        }
    }

    /// The `encrypted` check runs before the `items` check, so an encrypted export is never
    /// misreported as a non-export even when it is otherwise shaped like one.
    func test_decode_encryptedExportWinsOverTheItemsCheck() {
        let data = Data(#"{ "encrypted": true }"#.utf8)
        XCTAssertThrowsError(try VaultExportDocument.decode(from: data)) { error in
            XCTAssertEqual(error as? VaultExportDocumentError, .encryptedExportUnsupported)
        }
    }

    /// A tool that omits an empty `folders` array still produced a valid export.
    func test_decode_acceptsADocumentWithoutAFoldersKey() throws {
        let data = Data("{ \"encrypted\": false, \"items\": [\(loginItem)] }".utf8)
        let doc  = try VaultExportDocument.decode(from: data)
        XCTAssertTrue(doc.folders.isEmpty)
        XCTAssertEqual(doc.items.count, 1)
    }

    /// Right shape, unreadable item.
    func test_decode_refusesAMalformedItem() {
        let data = json(#"{ "id": "x", "type": "not-a-number", "name": "n" }"#)
        XCTAssertThrowsError(try VaultExportDocument.decode(from: data)) { error in
            XCTAssertEqual(error as? VaultExportDocumentError, .malformedExport)
        }
    }

    func test_decode_readsTheItemFields() throws {
        let doc  = try VaultExportDocument.decode(from: json(loginItem))
        let item = try XCTUnwrap(doc.items.first)

        XCTAssertEqual(item.id, "file-1")
        XCTAssertEqual(item.type, 1)
        XCTAssertEqual(item.name, "GitHub")
        XCTAssertEqual(item.login?.username, "octocat")
        XCTAssertEqual(item.login?.uris?.first?.match, 0)
    }

    // MARK: - Folder resolution

    func test_folderNamesById_mapsIdsToNames() throws {
        let doc = try VaultExportDocument.decode(
            from: json(loginItem, folders: #"[ { "id": "f-1", "name": "Work" } ]"#)
        )
        XCTAssertEqual(doc.folderNamesById, ["f-1": "Work"])
    }

    /// An item's `folderId` is file-local, so the *name* is what has to survive the round trip.
    func test_makeDraft_resolvesTheFolderThroughItsName() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "file-1", "type": 1, "name": "GitHub", "folderId": "f-1", "favorite": false, "reprompt": 0 }"#,
            folders: #"[ { "id": "f-1", "name": "Work" } ]"#
        ))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: ["work": "server-folder"], now: now)

        XCTAssertEqual(draft.folderId, "server-folder")
    }

    /// An unresolvable folder imports the item unfoldered. Dropping the item would lose data to
    /// preserve a filing hint.
    func test_makeDraft_unknownFolder_importsUnfoldered() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "file-1", "type": 1, "name": "GitHub", "folderId": "f-missing", "favorite": false, "reprompt": 0 }"#
        ))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertNil(draft.folderId)
    }

    /// An item with no folder at all is not an error.
    func test_makeDraft_itemWithoutAFolder_hasNoFolderId() throws {
        let doc = try VaultExportDocument.decode(from: json(loginItem))
        let item  = try XCTUnwrap(doc.items.first)
        XCTAssertNil(try doc.makeDraft(from: item, folderIdsByName: [:], now: now).folderId)
    }

    // MARK: - Which folders get created

    /// Only folders an item actually points at. Inventing empty folders is a side effect the user
    /// did not ask for.
    func test_referencedFolderNames_listsOnlyFoldersAnItemUses() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "file-1", "type": 1, "name": "GitHub", "folderId": "f-1", "favorite": false, "reprompt": 0 }"#,
            folders: #"[ { "id": "f-1", "name": "Work" }, { "id": "f-2", "name": "Empty" } ]"#
        ))
        XCTAssertEqual(doc.referencedFolderNames, ["Work"])
    }

    /// Deduplicated case-insensitively, first-seen order preserved, so two items in "Work" create
    /// one folder and not two.
    func test_referencedFolderNames_deduplicatesCaseInsensitively() throws {
        let doc = try VaultExportDocument.decode(from: json(
            """
            { "id": "a", "type": 1, "name": "A", "folderId": "f-1", "favorite": false, "reprompt": 0 },
            { "id": "b", "type": 1, "name": "B", "folderId": "f-2", "favorite": false, "reprompt": 0 },
            { "id": "c", "type": 1, "name": "C", "folderId": "f-3", "favorite": false, "reprompt": 0 }
            """,
            folders: #"[ { "id": "f-1", "name": "Work" }, { "id": "f-2", "name": "work" }, { "id": "f-3", "name": "Personal" } ]"#
        ))
        XCTAssertEqual(doc.referencedFolderNames, ["Work", "Personal"])
    }

    /// A folder entry with a blank name cannot be matched to anything, so it is not referenced.
    func test_referencedFolderNames_ignoresBlankNames() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "a", "type": 1, "name": "A", "folderId": "f-1", "favorite": false, "reprompt": 0 }"#,
            folders: #"[ { "id": "f-1", "name": "" } ]"#
        ))
        XCTAssertTrue(doc.referencedFolderNames.isEmpty)
    }

    // MARK: - Draft projection

    func test_makeDraft_carriesTheLoginFields() throws {
        let doc   = try VaultExportDocument.decode(from: json(loginItem))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertEqual(draft.name, "GitHub")
        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft, got \(draft.content)")
        }
        XCTAssertEqual(content.username, "octocat")
        XCTAssertEqual(content.password, "hunter2")
        XCTAssertEqual(content.uris.first?.uri, "https://github.com")
        XCTAssertEqual(content.uris.first?.matchType, .defaultMatch)
    }

    /// An unknown match integer degrades to "use the default strategy" rather than dropping the
    /// URI. Losing the site to preserve a matching hint is the wrong trade.
    /// **Reversed on 2026-09-22.** This test used to assert that an unrecognised match integer was
    /// dropped and the URI kept — "losing the site to preserve a matching hint would be the wrong
    /// trade". The trade was mis-stated: dropping the hint is not free, because the next save writes
    /// the field back as absent, and the server replaces the whole object. An unknown number now stays
    /// an unknown number, which is what `URIMatchType.unknown` exists for.
    func test_makeDraft_unknownURIMatch_carriesTheNumberUnchanged() throws {
        let doc = try VaultExportDocument.decode(from: json("""
        { "id": "a", "type": 1, "name": "A", "favorite": false, "reprompt": 0,
          "login": { "uris": [ { "uri": "https://example.com", "match": 99 } ] } }
        """))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        XCTAssertEqual(content.uris.count, 1, "the URI must survive")
        XCTAssertEqual(content.uris.first?.matchType, .unknown(99))
        XCTAssertEqual(content.uris.first?.matchType?.rawValue, 99,
                       "a value this build cannot name must go back out exactly as it came in")
    }

    /// A missing per-type payload degrades to an empty one, matching the reference's `toView`,
    /// which only maps a payload when it is non-null.
    func test_makeDraft_loginWithoutAPayload_stillProducesALogin() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "a", "type": 1, "name": "A", "favorite": false, "reprompt": 0 }"#
        ))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        XCTAssertNil(content.username)
        XCTAssertTrue(content.uris.isEmpty)
    }

    /// The type integer decides the payload, not the presence of a payload object.
    func test_makeDraft_mapsEachTypeToItsDraftContent() throws {
        let doc = try VaultExportDocument.decode(from: json("""
        { "id": "1", "type": 1, "name": "L", "favorite": false, "reprompt": 0 },
        { "id": "2", "type": 2, "name": "N", "favorite": false, "reprompt": 0 },
        { "id": "3", "type": 3, "name": "C", "favorite": false, "reprompt": 0 },
        { "id": "4", "type": 4, "name": "I", "favorite": false, "reprompt": 0 },
        { "id": "5", "type": 5, "name": "K", "favorite": false, "reprompt": 0 }
        """))
        let drafts = try doc.items.map { try doc.makeDraft(from: $0, folderIdsByName: [:], now: now) }

        guard case .login      = drafts[0].content else { return XCTFail("1 should be a login") }
        guard case .secureNote = drafts[1].content else { return XCTFail("2 should be a secure note") }
        guard case .card       = drafts[2].content else { return XCTFail("3 should be a card") }
        guard case .identity   = drafts[3].content else { return XCTFail("4 should be an identity") }
        guard case .sshKey     = drafts[4].content else { return XCTFail("5 should be an SSH key") }
    }

    func test_makeDraft_unsupportedType_throwsWithTheNumber() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "a", "type": 9, "name": "A", "favorite": false, "reprompt": 0 }"#
        ))
        let item = try XCTUnwrap(doc.items.first)

        XCTAssertThrowsError(try doc.makeDraft(from: item, folderIdsByName: [:], now: now)) { error in
            XCTAssertEqual(error as? VaultExportDocumentError, .unsupportedItemType(9))
        }
    }

    func test_makeDraft_blankName_throws() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "a", "type": 1, "name": "   ", "favorite": false, "reprompt": 0 }"#
        ))
        let item = try XCTUnwrap(doc.items.first)

        XCTAssertThrowsError(try doc.makeDraft(from: item, folderIdsByName: [:], now: now)) { error in
            XCTAssertEqual(error as? VaultExportDocumentError, .missingItemName)
        }
    }

    /// Organisation and collection membership is dropped. Writing an item into a collection the
    /// account cannot see would create an item invisible in every client, including this one.
    func test_makeDraft_dropsOrganisationAndCollectionMembership() throws {
        let doc = try VaultExportDocument.decode(from: json("""
        { "id": "a", "type": 1, "name": "A", "favorite": false, "reprompt": 0,
          "organizationId": "org-1", "collectionIds": [ "col-1" ] }
        """))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertNil(draft.organizationId)
        XCTAssertTrue(draft.collectionIds.isEmpty)
    }

    /// A new cipher has no per-item key, no passkeys and no history of its own.
    func test_makeDraft_clearsPreservedFields() throws {
        let doc   = try VaultExportDocument.decode(from: json(loginItem))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertEqual(draft.preserved, .empty)
    }

    /// The server assigns ids, so a file-local one means nothing here.
    func test_makeDraft_regeneratesTheId() throws {
        let doc   = try VaultExportDocument.decode(from: json(loginItem))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertNotEqual(draft.id, "file-1")
        XCTAssertFalse(draft.id.isEmpty)
    }

    /// An imported item is live, never created straight into Trash.
    func test_makeDraft_createsALiveItem() throws {
        let doc   = try VaultExportDocument.decode(from: json(loginItem))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertFalse(draft.isDeleted)
    }

    func test_makeDraft_carriesFavoriteAndReprompt() throws {
        let doc = try VaultExportDocument.decode(from: json(
            #"{ "id": "a", "type": 1, "name": "A", "favorite": true, "reprompt": 1 }"#
        ))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertTrue(draft.isFavorite)
        XCTAssertEqual(draft.reprompt, 1)
    }

    /// Notes and custom fields live on the item, so they have to be put back into whichever
    /// per-type content the item has.
    func test_makeDraft_carriesNotesAndCustomFieldsIntoTheContent() throws {
        let doc = try VaultExportDocument.decode(from: json("""
        { "id": "a", "type": 2, "name": "A", "favorite": false, "reprompt": 0,
          "notes": "the note",
          "fields": [ { "name": "PIN", "value": "1234", "type": 1 } ] }
        """))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        guard case .secureNote(let content) = draft.content else {
            return XCTFail("expected a secure note draft")
        }
        XCTAssertEqual(content.notes, "the note")
        XCTAssertEqual(content.customFields.count, 1)
        XCTAssertEqual(content.customFields.first?.name, "PIN")
        XCTAssertEqual(content.customFields.first?.type, .hidden)
    }

    /// `CipherMapper` skips unnamed fields on the way out, so importing one would inflate the
    /// count the user is shown without putting anything in the vault.
    func test_makeDraft_dropsUnnamedCustomFields() throws {
        let doc = try VaultExportDocument.decode(from: json("""
        { "id": "a", "type": 1, "name": "A", "favorite": false, "reprompt": 0,
          "fields": [ { "name": "  ", "value": "x", "type": 0 },
                      { "name": "kept", "value": "y", "type": 0 } ] }
        """))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        XCTAssertEqual(content.customFields.map(\.name), ["kept"])
    }

    /// An unrecognised field type degrades to text rather than dropping the field.
    func test_makeDraft_unknownCustomFieldType_degradesToText() throws {
        let doc = try VaultExportDocument.decode(from: json("""
        { "id": "a", "type": 1, "name": "A", "favorite": false, "reprompt": 0,
          "fields": [ { "name": "f", "value": "v", "type": 77 } ] }
        """))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        XCTAssertEqual(content.customFields.first?.type, .text)
    }

    /// `linkedId` is only meaningful for a linked field, and an unknown one is dropped rather than
    /// pointing at a field that does not exist.
    func test_makeDraft_linkedField_keepsKnownIdsAndDropsUnknownOnes() throws {
        let doc = try VaultExportDocument.decode(from: json("""
        { "id": "a", "type": 1, "name": "A", "favorite": false, "reprompt": 0,
          "fields": [ { "name": "u", "type": 3, "linkedId": 100 },
                      { "name": "v", "type": 3, "linkedId": 9999 },
                      { "name": "w", "type": 0, "linkedId": 100 } ] }
        """))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        XCTAssertEqual(content.customFields[0].linkedId, .loginUsername)
        XCTAssertNil(content.customFields[1].linkedId)
        XCTAssertNil(content.customFields[2].linkedId, "a non-linked field must not carry one")
    }

    func test_makeDraft_usesTheInjectedDateForBothTimestamps() throws {
        let doc   = try VaultExportDocument.decode(from: json(loginItem))
        let item  = try XCTUnwrap(doc.items.first)
        let draft = try doc.makeDraft(from: item, folderIdsByName: [:], now: now)

        XCTAssertEqual(draft.creationDate, now)
        XCTAssertEqual(draft.revisionDate, now)
    }

    // MARK: - Errors are user-facing

    /// Every refusal has to say something. An error with no description surfaces as a blank alert.
    func test_everyRefusalHasADescription() {
        let errors: [VaultExportDocumentError] = [
            .unsupportedItemType(9), .missingItemName, .notAnUnencryptedExport,
            .encryptedExportUnsupported, .malformedExport
        ]
        for error in errors {
            let description = error.errorDescription
            XCTAssertNotNil(description)
            XCTAssertFalse(description?.isEmpty ?? true, "\(error) has an empty description")
        }
    }

    /// The unsupported-type message names the number, so the user can see what the file asked for.
    func test_unsupportedTypeMessage_namesTheNumber() {
        XCTAssertTrue(
            VaultExportDocumentError.unsupportedItemType(9)
                .errorDescription?.contains("9") ?? false
        )
    }
}
