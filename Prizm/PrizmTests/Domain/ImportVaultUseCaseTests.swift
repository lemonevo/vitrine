import Foundation
import XCTest
@testable import Prizm

// MARK: - ImportVaultUseCaseTests

/// Tests for reading an export and creating the items it contains.
///
/// An import is N independent `POST /api/ciphers` requests, so the interesting assertions are about
/// the *partial* outcomes: which items were attempted, what happened to each, and whether the run
/// kept going. The summary is the deliverable, so most of what is checked here is the summary.
@MainActor
final class ImportVaultUseCaseTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut: ImportVaultUseCaseImpl!

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        sut   = ImportVaultUseCaseImpl(vault: vault)
    }

    // MARK: - Helpers

    /// Collects the progress callbacks. The closure is `@Sendable` and the implementation is
    /// nonisolated, so a plain captured `var` would not compile — and would be a data race even if
    /// it did.
    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(Int, Int)] = []

        func append(_ done: Int, _ total: Int) {
            lock.lock(); defer { lock.unlock() }
            values.append((done, total))
        }

        var recorded: [(Int, Int)] {
            lock.lock(); defer { lock.unlock() }
            return values
        }
    }

    /// `items` is wrapped in brackets here so each call site can pass one object or several
    /// without having to remember the array itself.
    private func data(_ items: String, folders: String = "[]", encrypted: String = "false") -> Data {
        Data("""
        { "encrypted": \(encrypted), "folders": \(folders), "items": [\(items)] }
        """.utf8)
    }

    private func run(_ payload: Data) async throws -> (summary: ImportSummary, progress: [(Int, Int)]) {
        let log = ProgressLog()
        let summary = try await sut.execute(data: payload) { done, total in
            log.append(done, total)
        }
        return (summary, log.recorded)
    }

    /// A minimal login item, so a test only has to vary the field it is about.
    private func loginJSON(id: String, name: String, extra: String = "") -> String {
        """
        { "id": "\(id)", "type": 1, "name": "\(name)", "favorite": false, "reprompt": 0\(extra) }
        """
    }

    // MARK: - Refusals

    /// The whole run is refused for a file that is not an unencrypted export — there is nothing to
    /// partially succeed at.
    func test_execute_encryptedExport_isRefused() async {
        do {
            _ = try await sut.execute(data: data(loginJSON(id: "1", name: "A"), encrypted: "true")) { _, _ in }
            XCTFail("an encrypted export must be refused")
        } catch {
            XCTAssertEqual(error as? VaultExportDocumentError, .encryptedExportUnsupported)
        }
    }

    func test_execute_notAnExport_isRefused() async {
        do {
            _ = try await sut.execute(data: Data("nonsense".utf8)) { _, _ in }
            XCTFail("a non-export must be refused")
        } catch {
            XCTAssertEqual(error as? VaultExportDocumentError, .notAnUnencryptedExport)
        }
    }

    /// A refused file creates nothing at all.
    func test_execute_refusedFile_createsNothing() async {
        _ = try? await sut.execute(data: Data("nonsense".utf8)) { _, _ in }
        XCTAssertEqual(vault.createCallCount, 0)
    }

    // MARK: - The happy path

    func test_execute_importsEveryItem() async throws {
        let payload = data("""
        \(loginJSON(id: "1", name: "GitHub")),
        \(loginJSON(id: "2", name: "GitLab")),
        \(loginJSON(id: "3", name: "Bitbucket"))
        """)
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.imported, 3)
        XCTAssertEqual(summary.total, 3)
        XCTAssertTrue(summary.skipped.isEmpty)
        XCTAssertTrue(summary.failed.isEmpty)
        XCTAssertTrue(summary.createdAnything)
    }

    /// The file's own ids mean nothing on this server, so every item goes through the ordinary
    /// create path and gets a fresh id.
    func test_execute_regeneratesIds() async throws {
        _ = try await run(data(loginJSON(id: "file-1", name: "GitHub")))

        XCTAssertEqual(vault.createCallCount, 1)
        XCTAssertNotEqual(vault.lastCreatedDraft?.id, "file-1")
    }

    /// The item's own fields survive.
    func test_execute_carriesTheContent() async throws {
        let payload = data("""
        { "id": "1", "type": 1, "name": "GitHub", "favorite": true, "reprompt": 1,
          "login": { "username": "octocat", "password": "hunter2",
                     "uris": [ { "uri": "https://github.com", "match": 0 } ] } }
        """)
        _ = try await run(payload)

        let draft = try XCTUnwrap(vault.lastCreatedDraft)
        XCTAssertEqual(draft.name, "GitHub")
        XCTAssertTrue(draft.isFavorite)
        XCTAssertEqual(draft.reprompt, 1)
        guard case .login(let content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        XCTAssertEqual(content.username, "octocat")
        XCTAssertEqual(content.password, "hunter2")
    }

    // MARK: - Partial outcomes

    /// An item with a type integer Prizm does not know cannot be represented, so it is skipped —
    /// and the run continues, because the other items are still importable.
    func test_execute_unsupportedType_isSkipped_andTheRunContinues() async throws {
        let payload = data("""
        \(loginJSON(id: "1", name: "Good")),
        { "id": "2", "type": 9, "name": "Weird", "favorite": false, "reprompt": 0 },
        \(loginJSON(id: "3", name: "Also good"))
        """)
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(summary.skipped.count, 1)
        XCTAssertEqual(summary.skipped.first?.itemName, "Weird")
        XCTAssertTrue(summary.failed.isEmpty)
        XCTAssertEqual(summary.total, 3, "a skipped item is still accounted for")
        XCTAssertEqual(vault.createCallCount, 2, "the skipped item never reached the server")
    }

    /// A skip carries a reason the user can read.
    func test_execute_skippedItem_hasAReadableReason() async throws {
        let payload = data(#"{ "id": "1", "type": 9, "name": "Weird", "favorite": false, "reprompt": 0 }"#)
        let (summary, _) = try await run(payload)

        let reason = try XCTUnwrap(summary.skipped.first?.reason)
        XCTAssertFalse(reason.isEmpty)
        XCTAssertTrue(reason.contains("9"), "the reason names the type the file asked for: \(reason)")
    }

    /// An item with no name cannot be created — the server requires one — so it is skipped rather
    /// than imported under a name Prizm invented.
    func test_execute_itemWithoutAName_isSkipped() async throws {
        let payload = data("""
        \(loginJSON(id: "1", name: "Good")),
        { "id": "2", "type": 1, "name": "   ", "favorite": false, "reprompt": 0 }
        """)
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.skipped.count, 1)
        XCTAssertEqual(summary.skipped.first?.itemName, "(unnamed)",
                       "an unnamed item is identified rather than shown as a blank row")
    }

    /// A server rejection is recorded as a failure — distinct from a skip, because "we chose not
    /// to" and "the server said no" are different things to tell the user.
    func test_execute_serverFailure_isRecorded_andTheRunContinues() async throws {
        vault.createErrorNames = ["Rejected"]
        let payload = data("""
        \(loginJSON(id: "1", name: "First")),
        \(loginJSON(id: "2", name: "Rejected")),
        \(loginJSON(id: "3", name: "Last"))
        """)
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(summary.failed.count, 1)
        XCTAssertEqual(summary.failed.first?.itemName, "Rejected")
        XCTAssertTrue(summary.skipped.isEmpty)
        XCTAssertEqual(vault.createCallCount, 3, "every item was attempted, including the one after")
        XCTAssertEqual(summary.total, 3)
    }

    /// The run does not throw for a per-item failure — that is the whole point of the summary.
    func test_execute_allItemsFailing_stillReturnsASummary() async throws {
        vault.stubbedCreateError = VaultError.vaultLocked
        let payload = data("""
        \(loginJSON(id: "1", name: "A")),
        \(loginJSON(id: "2", name: "B"))
        """)
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.failed.count, 2)
        XCTAssertFalse(summary.createdAnything)
        XCTAssertEqual(summary.total, 2)
    }

    /// A failure reason is the error's own description, so the report says what went wrong.
    func test_execute_failureReason_comesFromTheError() async throws {
        vault.stubbedCreateError = VaultError.vaultLocked
        let (summary, _) = try await run(data(loginJSON(id: "1", name: "A")))

        XCTAssertFalse(summary.failed.first?.reason.isEmpty ?? true)
    }

    // MARK: - Organisation membership

    /// Membership is dropped, and the user is told — an item that silently changed owner is worse
    /// than one that was reported as changed.
    func test_execute_organisationMembership_isDroppedAndCounted() async throws {
        let payload = data("""
        \(loginJSON(id: "1", name: "Personal")),
        \(loginJSON(id: "2", name: "Org", extra: #", "organizationId": "org-1""#)),
        \(loginJSON(id: "3", name: "Col", extra: #", "collectionIds": [ "col-1" ]"#))
        """)
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.imported, 3)
        XCTAssertEqual(summary.organisationMembershipDropped, 2)
        XCTAssertEqual(vault.lastCreatedDraft?.organizationId, nil)
        XCTAssertTrue(vault.lastCreatedDraft?.collectionIds.isEmpty ?? false)
    }

    func test_execute_personalItems_doNotCountAsDroppedMembership() async throws {
        let (summary, _) = try await run(data(loginJSON(id: "1", name: "Personal")))
        XCTAssertEqual(summary.organisationMembershipDropped, 0)
    }

    // MARK: - Folders

    /// A folder the vault already has is reused, matched case-insensitively.
    func test_execute_matchesAnExistingFolderByName() async throws {
        await vault.populate(items: [], folders: [Folder(id: "existing", name: "Work")],
                             organizations: [], collections: [], syncedAt: .now)

        let payload = data(
            #"{ "id": "1", "type": 1, "name": "A", "folderId": "f-1", "favorite": false, "reprompt": 0 }"#,
            folders: #"[ { "id": "f-1", "name": "work" } ]"#
        )
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.foldersCreated, 0)
        XCTAssertEqual(vault.lastCreatedDraft?.folderId, "existing")
    }

    /// A folder the vault does not have is created, and the item lands in it.
    func test_execute_createsAMissingFolder() async throws {
        let payload = data(
            #"{ "id": "1", "type": 1, "name": "A", "folderId": "f-1", "favorite": false, "reprompt": 0 }"#,
            folders: #"[ { "id": "f-1", "name": "Work" } ]"#
        )
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.foldersCreated, 1)
        XCTAssertEqual(vault.populatedFolders.map(\.name), ["Work"])
        XCTAssertEqual(vault.lastCreatedDraft?.folderId, vault.populatedFolders.first?.id)
    }

    /// Two items in the same folder create it once.
    func test_execute_createsAFolderOnceForSeveralItems() async throws {
        let payload = data("""
        { "id": "1", "type": 1, "name": "A", "folderId": "f-1", "favorite": false, "reprompt": 0 },
        { "id": "2", "type": 1, "name": "B", "folderId": "f-1", "favorite": false, "reprompt": 0 }
        """, folders: #"[ { "id": "f-1", "name": "Work" } ]"#)
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.foldersCreated, 1)
        XCTAssertEqual(summary.imported, 2)
    }

    /// An empty folder in the file is not created: the user asked to import their items, and
    /// inventing folders is a side effect they did not ask for.
    func test_execute_doesNotCreateFoldersNoItemUses() async throws {
        let payload = data(
            loginJSON(id: "1", name: "A"),
            folders: #"[ { "id": "f-1", "name": "Empty" } ]"#
        )
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.foldersCreated, 0)
        XCTAssertTrue(vault.populatedFolders.isEmpty)
    }

    /// A folder that cannot be created is counted, not thrown: the items that referenced it are
    /// imported unfoldered, which is recoverable, where refusing the whole import is not.
    func test_execute_folderCreationFailure_countsAndImportsUnfoldered() async throws {
        vault.stubbedCreateFolderError = VaultError.vaultLocked
        let payload = data(
            #"{ "id": "1", "type": 1, "name": "A", "folderId": "f-1", "favorite": false, "reprompt": 0 }"#,
            folders: #"[ { "id": "f-1", "name": "Work" } ]"#
        )
        let (summary, _) = try await run(payload)

        XCTAssertEqual(summary.foldersFailed, 1)
        XCTAssertEqual(summary.imported, 1, "the item is not lost because its folder failed")
        XCTAssertNil(vault.lastCreatedDraft?.folderId)
    }

    // MARK: - Progress

    /// Progress is reported for every item, including the ones that were skipped — otherwise the
    /// sheet stalls on an item that produced no create.
    func test_execute_reportsProgressForEveryItem() async throws {
        let payload = data("""
        \(loginJSON(id: "1", name: "A")),
        { "id": "2", "type": 9, "name": "Weird", "favorite": false, "reprompt": 0 },
        \(loginJSON(id: "3", name: "C"))
        """)
        let (_, progress) = try await run(payload)

        XCTAssertEqual(progress.count, 4, "one for the start plus one per item")
        XCTAssertEqual(progress.first?.0, 0)
        XCTAssertEqual(progress.first?.1, 3)
        XCTAssertEqual(progress.last?.0, 3)
        XCTAssertEqual(progress.last?.1, 3)
        XCTAssertEqual(progress.map(\.0), [0, 1, 2, 3], "the count never stalls or goes backwards")
    }

    func test_execute_emptyDocument_reportsZeroProgressAndImportsNothing() async throws {
        let (summary, progress) = try await run(data(""))

        XCTAssertEqual(summary.total, 0)
        XCTAssertFalse(summary.createdAnything)
        XCTAssertEqual(progress.count, 1, "the file is still counted once")
        XCTAssertEqual(progress.first?.0, 0)
        XCTAssertEqual(progress.first?.1, 0)
        XCTAssertEqual(vault.createCallCount, 0)
    }

    // MARK: - Additive

    /// Importing is additive: nothing is deleted, modified or merged, so the same file twice
    /// produces two copies. That is what the official clients do and it cannot lose data.
    func test_execute_isAdditive_importingTwiceCreatesTwoCopies() async throws {
        let payload = data(loginJSON(id: "1", name: "GitHub"))

        let first  = try await run(payload)
        let second = try await run(payload)

        XCTAssertEqual(first.summary.imported, 1)
        XCTAssertEqual(second.summary.imported, 1)
        XCTAssertEqual(vault.createCallCount, 2, "nothing was deduplicated")
        XCTAssertEqual(vault.createdDrafts.count, 2)
        XCTAssertNotEqual(vault.createdDrafts[0].id, vault.createdDrafts[1].id,
                          "the second import creates its own item rather than reusing the first")
    }

    /// Nothing is deleted by an import, whatever the file contains.
    func test_execute_neverDeletes() async throws {
        await vault.populate(items: [VaultItem(
            id: "existing", name: "Existing", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: nil, password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: []))
        )], folders: [], organizations: [], collections: [], syncedAt: .now)

        _ = try await run(data(loginJSON(id: "1", name: "New")))

        XCTAssertEqual(vault.deleteCallCount, 0)
        XCTAssertEqual(vault.permanentDeleteCallCount, 0)
    }

    /// An imported item is live, even if the file said otherwise about its own copy.
    func test_execute_importedItemsAreLive() async throws {
        _ = try await run(data(loginJSON(id: "1", name: "A")))
        XCTAssertFalse(vault.lastCreatedDraft?.isDeleted ?? true)
    }

    // MARK: - Summary

    func test_summary_total_countsEveryOutcome() {
        var summary = ImportSummary()
        summary.imported = 2
        summary.skipped  = [.init(itemName: "a", reason: "r")]
        summary.failed   = [.init(itemName: "b", reason: "r")]

        XCTAssertEqual(summary.total, 4)
        XCTAssertTrue(summary.createdAnything)
    }

    func test_summary_createdAnythingIsFalseWhenNothingLanded() {
        var summary = ImportSummary()
        summary.skipped = [.init(itemName: "a", reason: "r")]
        summary.failed  = [.init(itemName: "b", reason: "r")]

        XCTAssertFalse(summary.createdAnything)
    }

    /// A brand-new summary describes an import that has not happened.
    func test_summary_startsEmpty() {
        let summary = ImportSummary()
        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(summary.foldersCreated, 0)
        XCTAssertEqual(summary.foldersFailed, 0)
        XCTAssertEqual(summary.organisationMembershipDropped, 0)
        XCTAssertFalse(summary.createdAnything)
    }
}
