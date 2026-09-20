import Foundation
import XCTest
@testable import Prizm

// MARK: - ExportVaultUseCaseTests

/// Tests for the export use case: what it counts, what it refuses, and what the bytes it returns
/// actually contain.
///
/// The use case returns bytes and never writes, so there is no file-system dependency to stub and
/// no disk to clean up. The one thing it does reach for is password history, which is decrypted
/// here and nowhere else in the export path — so that is what the double counts.
@MainActor
final class ExportVaultUseCaseTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut: ExportVaultUseCaseImpl!

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        sut   = ExportVaultUseCaseImpl(vault: vault)
    }

    // MARK: - Fixtures

    private func login(id: String = "item-1",
                       name: String = "GitHub",
                       organizationId: String? = nil,
                       collectionIds: [String] = [],
                       preserved: PreservedCipherFields = .empty) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .login(LoginContent(
                username: "octocat", password: "hunter2",
                uris: [LoginURI(uri: "https://github.com", matchType: .domain)],
                totp: nil, notes: nil, customFields: []
            )),
            organizationId: organizationId,
            collectionIds: collectionIds,
            preserved: preserved
        )
    }

    private func populate(_ items: [VaultItem], folders: [Folder] = []) async {
        await vault.populate(items: items, folders: folders, organizations: [],
                             collections: [], syncedAt: .now)
    }

    private func decode(_ export: VaultExport) throws -> VaultExportDocument {
        try VaultExportDocument.decode(from: export.data)
    }

    // MARK: - Refusals

    /// A zero-item backup that the user believes is a backup is worse than no backup.
    func test_execute_emptyVault_isRefused() async {
        await populate([])

        do {
            _ = try await sut.execute()
            XCTFail("an empty vault must not produce a file")
        } catch {
            XCTAssertEqual(error as? ExportVaultError, .emptyVault)
        }
    }

    /// The refusal has to be explainable — this is the text the user sees.
    func test_emptyVault_hasADescription() {
        XCTAssertNotNil(ExportVaultError.emptyVault.errorDescription)
    }

    /// Refusing happens before any history is decrypted, so an empty vault costs nothing.
    func test_execute_emptyVault_doesNotReadPasswordHistory() async {
        await populate([])
        _ = try? await sut.execute()
        XCTAssertEqual(vault.passwordHistoryCallCount, 0)
    }

    // MARK: - Counts

    func test_execute_countsTheItems() async throws {
        await populate([login(id: "1"), login(id: "2"), login(id: "3")])
        let export = try await sut.execute()

        XCTAssertEqual(export.itemCount, 3)
        XCTAssertEqual(try decode(export).items.count, 3)
    }

    /// Reported separately because the official individual export omits these, so a user who has
    /// used that client will not expect them in the file.
    func test_execute_countsOrganisationItemsSeparately() async throws {
        await populate([
            login(id: "1"),
            login(id: "2", organizationId: "org-1", collectionIds: ["col-1"]),
            login(id: "3", organizationId: "org-1")
        ])
        let export = try await sut.execute()

        XCTAssertEqual(export.itemCount, 3)
        XCTAssertEqual(export.organisationItemCount, 2)
    }

    func test_execute_withoutOrganisationItems_reportsZero() async throws {
        await populate([login(id: "1")])
        let export = try await sut.execute()

        XCTAssertEqual(export.organisationItemCount, 0)
    }

    // MARK: - What the bytes contain

    func test_execute_encodesAnUnencryptedDocument() async throws {
        await populate([login()])
        let document = try decode(try await sut.execute())

        XCTAssertFalse(document.encrypted)
    }

    func test_execute_includesFolders() async throws {
        await populate([login()], folders: [Folder(id: "f-1", name: "Work")])
        let document = try decode(try await sut.execute())

        XCTAssertEqual(document.folders, [ExportFolder(id: "f-1", name: "Work")])
    }

    /// The file has to carry the actual secret, or it is not a backup.
    func test_execute_writesThePasswordInPlaintext() async throws {
        await populate([login()])
        let text = String(decoding: try await sut.execute().data, as: UTF8.self)

        XCTAssertTrue(text.contains("hunter2"))
    }

    /// `.withoutEscapingSlashes`: without it every URL reads `https:\/\/…`, which is valid JSON
    /// but stops the file being readable to the person verifying their own backup.
    func test_execute_doesNotEscapeSlashes() async throws {
        await populate([login()])
        let text = String(decoding: try await sut.execute().data, as: UTF8.self)

        XCTAssertTrue(text.contains("https://github.com"))
        XCTAssertFalse(text.contains("https:\\/\\/github.com"))
    }

    /// `.sortedKeys` makes the output deterministic, so two exports of an unchanged vault are
    /// byte-identical.
    func test_execute_isDeterministic() async throws {
        await populate([login(id: "1"), login(id: "2")])

        let first  = try await sut.execute()
        let second = try await sut.execute()

        XCTAssertEqual(first.data, second.data)
    }

    // MARK: - Password history

    /// History is decrypted only for the items that have some — one cheap check per item rather
    /// than a decrypt pass over the whole vault.
    func test_execute_readsHistoryOnlyForItemsThatHaveSome() async throws {
        let withHistory = PreservedCipherFields(passwordHistory: [.string("enc")])
        await populate([login(id: "1", preserved: withHistory), login(id: "2")])
        vault.stubbedPasswordHistory = [
            "1": [PasswordHistoryEntry(password: "old-hunter1", lastUsedDate: epoch)]
        ]

        let document = try decode(try await sut.execute())

        XCTAssertEqual(vault.passwordHistoryCallCount, 1, "only the item with history is read")
        XCTAssertEqual(vault.lastPasswordHistoryId, "1")
        XCTAssertEqual(document.items[0].passwordHistory?.first?.password, "old-hunter1")
        XCTAssertNil(document.items[1].passwordHistory)
    }

    /// An unreadable history is not a reason to refuse the user a backup of everything else.
    func test_execute_historyFailure_degradesToNoHistory() async throws {
        let withHistory = PreservedCipherFields(passwordHistory: [.string("enc")])
        await populate([login(id: "1", preserved: withHistory)])
        vault.stubbedPasswordHistoryError = VaultError.itemNotFound("1")

        let export   = try await sut.execute()
        let document = try decode(export)

        XCTAssertEqual(export.itemCount, 1, "the export still happens")
        XCTAssertNil(document.items[0].passwordHistory)
    }

    // MARK: - Filename

    /// `prizm_export_YYYYMMDDHHmmss.json`, mirroring the reference's `bitwarden_export_<ts>.json`.
    func test_filename_hasTheExpectedShape() {
        let name = ExportVaultUseCaseImpl.filename(now: epoch)

        XCTAssertTrue(name.hasPrefix("prizm_export_"), name)
        XCTAssertTrue(name.hasSuffix(".json"), name)
        XCTAssertEqual(name.count, "prizm_export_".count + 14 + ".json".count)
        XCTAssertEqual(name, "prizm_export_20231114221320.json")
    }

    /// The time is included so two exports in one session do not offer the same name.
    func test_filename_changesWithTheTime() {
        XCTAssertNotEqual(
            ExportVaultUseCaseImpl.filename(now: epoch),
            ExportVaultUseCaseImpl.filename(now: epoch.addingTimeInterval(1))
        )
    }

    /// The second-resolution format is intentional: two exports a minute apart get different
    /// names, and the name is a valid filename on every platform the app runs on.
    func test_filename_isAPlainFilename() {
        let name = ExportVaultUseCaseImpl.filename(now: epoch)

        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains(" "))
        XCTAssertEqual(name, name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Round trip

    /// The point of using Bitwarden's format rather than a Prizm one: the file has to be readable
    /// again. This is the strongest single assertion in the suite — export a vault, import it back,
    /// and check the content survived.
    func test_roundTrip_exportThenImport_preservesContent() async throws {
        let original = VaultItem(
            id: "item-1", name: "GitHub", isFavorite: true, isDeleted: false,
            creationDate: epoch, revisionDate: epoch,
            content: .login(LoginContent(
                username: "octocat", password: "hunter2",
                uris: [LoginURI(uri: "https://github.com", matchType: .domain)],
                totp: "JBSWY3DPEHPK3PXP", notes: "a note",
                customFields: [CustomField(name: "PIN", value: "1234", type: .hidden, linkedId: nil)]
            )),
            reprompt: 1,
            folderId: "f-1"
        )
        await populate([original], folders: [Folder(id: "f-1", name: "Work")])

        let export   = try await sut.execute()
        let document = try decode(export)
        let item     = try XCTUnwrap(document.items.first)
        let draft    = try document.makeDraft(from: item,
                                             folderIdsByName: ["work": "server-folder"],
                                             now: epoch)

        XCTAssertEqual(draft.name, "GitHub")
        XCTAssertTrue(draft.isFavorite)
        XCTAssertEqual(draft.reprompt, 1)
        XCTAssertEqual(draft.folderId, "server-folder")

        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        XCTAssertEqual(content.username, "octocat")
        XCTAssertEqual(content.password, "hunter2")
        XCTAssertEqual(content.totp, "JBSWY3DPEHPK3PXP", "losing the seed would disable 2FA")
        XCTAssertEqual(content.notes, "a note")
        XCTAssertEqual(content.uris.first?.uri, "https://github.com")
        XCTAssertEqual(content.uris.first?.matchType, .domain)
        XCTAssertEqual(content.customFields.first?.name, "PIN")
        XCTAssertEqual(content.customFields.first?.value, "1234")
        XCTAssertEqual(content.customFields.first?.type, .hidden)
    }

    /// A round trip through the file must not change an item's type, for any of the five.
    func test_roundTrip_preservesTheItemType() async throws {
        let items = [
            VaultItem(id: "1", name: "L", isFavorite: false, isDeleted: false,
                      creationDate: epoch, revisionDate: epoch,
                      content: .login(LoginContent(username: nil, password: nil, uris: [],
                                                   totp: nil, notes: nil, customFields: []))),
            VaultItem(id: "2", name: "N", isFavorite: false, isDeleted: false,
                      creationDate: epoch, revisionDate: epoch,
                      content: .secureNote(SecureNoteContent(notes: nil, customFields: []))),
            VaultItem(id: "3", name: "C", isFavorite: false, isDeleted: false,
                      creationDate: epoch, revisionDate: epoch,
                      content: .card(CardContent(cardholderName: nil, brand: nil, number: nil,
                                                 expMonth: nil, expYear: nil, code: nil,
                                                 notes: nil, customFields: []))),
            VaultItem(id: "4", name: "I", isFavorite: false, isDeleted: false,
                      creationDate: epoch, revisionDate: epoch,
                      content: .identity(IdentityContent(
                        title: nil, firstName: nil, middleName: nil, lastName: nil,
                        address1: nil, address2: nil, address3: nil, city: nil, state: nil,
                        postalCode: nil, country: nil, company: nil, email: nil, phone: nil,
                        ssn: nil, username: nil, passportNumber: nil, licenseNumber: nil,
                        notes: nil, customFields: []))),
            VaultItem(id: "5", name: "K", isFavorite: false, isDeleted: false,
                      creationDate: epoch, revisionDate: epoch,
                      content: .sshKey(SSHKeyContent(privateKey: nil, publicKey: "ssh-ed25519 A",
                                                     keyFingerprint: nil, notes: nil,
                                                     customFields: [])))
        ]
        await populate(items)

        let document = try decode(try await sut.execute())
        let drafts   = try document.items.map {
            try document.makeDraft(from: $0, folderIdsByName: [:], now: epoch)
        }

        XCTAssertEqual(document.items.map(\.type), [1, 2, 3, 4, 5])
        guard case .login      = drafts[0].content else { return XCTFail("1") }
        guard case .secureNote = drafts[1].content else { return XCTFail("2") }
        guard case .card       = drafts[2].content else { return XCTFail("3") }
        guard case .identity   = drafts[3].content else { return XCTFail("4") }
        guard case .sshKey     = drafts[4].content else { return XCTFail("5") }
    }

    /// Trash is not part of a backup, and this use case is only ever handed the active vault. The
    /// assertion pins that the item count follows what the repository returns rather than
    /// second-guessing it.
    func test_execute_exportsExactlyWhatTheRepositoryReturns() async throws {
        await populate([login(id: "1"), login(id: "2")])
        let both = try await sut.execute()
        XCTAssertEqual(both.itemCount, 2)

        await populate([login(id: "1")])
        let one = try await sut.execute()
        XCTAssertEqual(one.itemCount, 1)
    }
}
