import XCTest
@testable import Prizm

/// Tests for the Phase 1 actions on `VaultBrowserViewModel`: manual sync, duplicate, empty Trash,
/// sort order and the configurable clipboard clear.
///
/// These are the actions the user triggers directly, so what matters is the state the UI reads
/// afterwards — `isSyncing`, `actionError`, `displayedItems`, `itemSelection` — rather than the
/// call itself.
@MainActor
final class VaultBrowserViewModelActionsTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var duplicate: NoopDuplicateUseCase!
    private var emptyTrash: StubEmptyTrashUseCase!
    private var sync: MockSyncUseCase!
    private var syncTimestamp: MockSyncTimestampRepository!
    private var sut: VaultBrowserViewModel!

    private let storedSyncDate = Date(timeIntervalSince1970: 1_600_000_000)

    // MARK: - Fixtures

    private func login(id: String, name: String,
                       isDeleted: Bool = false,
                       created: Date = Date(timeIntervalSince1970: 1_700_000_000),
                       modified: Date? = nil) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: isDeleted,
            creationDate: created, revisionDate: modified ?? created,
            content: .login(LoginContent(username: "u-\(id)", password: "p", uris: [],
                                         totp: nil, notes: nil, customFields: []))
        )
    }

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        // `VaultBrowserViewModel` reads its sort order and clipboard interval from `.standard`, so
        // these keys are cleared before and after each test to keep this suite from leaking a
        // preference into every other suite.
        UserDefaults.standard.removeObject(forKey: ItemSortPreference.key)
        UserDefaults.standard.removeObject(forKey: ClipboardClearInterval.key)

        vault        = MockVaultRepository()
        duplicate    = NoopDuplicateUseCase()
        emptyTrash   = StubEmptyTrashUseCase()
        sync         = MockSyncUseCase()
        syncTimestamp = MockSyncTimestampRepository(storedDate: storedSyncDate)
        sut          = makeSUT()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: ItemSortPreference.key)
        UserDefaults.standard.removeObject(forKey: ClipboardClearInterval.key)
        vault = nil
        duplicate = nil
        emptyTrash = nil
        sync = nil
        syncTimestamp = nil
        sut = nil
        try await super.tearDown()
    }

    private func makeSUT() -> VaultBrowserViewModel {
        VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          StubDelete(),
            permanentDelete: StubPermanentDelete(),
            restore:         StubRestore(),
            duplicate:       duplicate,
            emptyTrash:      emptyTrash,
            sync:            sync,
            createFolder:     StubCreateFolder(),
            renameFolder:     StubRenameFolder(),
            deleteFolder:     StubDeleteFolder(),
            moveItem:         StubMoveItem(),
            createCollection: StubCreateCollection(),
            renameCollection: StubRenameCollection(),
            deleteCollection: StubDeleteCollection(),
            syncTimestamp:    syncTimestamp,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncTimestamp),
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        { _, _ in nil },
            filePicker:       { nil }
        )
    }

    /// `refreshItems()` is fire-and-forget, so the list is only correct after a run-loop turn.
    private func populate(_ items: [VaultItem]) async {
        await vault.populate(items: items, folders: [], organizations: [], collections: [], syncedAt: .now)
        sut.refreshItems()
        sut.refreshCounts()
        let visible = items.filter { !$0.isDeleted }.count
        await waitUntil { self.sut.displayedItems.count == visible }
    }

    /// Waits for the (fire-and-forget) refresh to produce exactly these ids, in this order.
    private func waitForItems(_ ids: [String],
                              file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil { self.sut.displayedItems.map(\.id) == ids }
        XCTAssertEqual(sut.displayedItems.map(\.id), ids, file: file, line: line)
    }

    /// Yields to the main actor run loop until `condition` is true or the timeout elapses.
    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Manual sync: success

    func test_performManualSync_success_updatesTheTimestampAndClearsTheError() async throws {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        sync.stubbedResult = SyncResult(syncedAt: syncedAt, totalCiphers: 3, failedDecryptionCount: 0)
        sut.syncErrorMessage = "an older failure"

        sut.performManualSync()
        await waitUntil { !self.sut.isSyncing }

        XCTAssertTrue(sync.executeCalled)
        XCTAssertEqual(sut.lastSyncedAt, syncedAt)
        XCTAssertNil(sut.syncErrorMessage, "a success must clear the previous failure banner")
        XCTAssertTrue(syncTimestamp.recordCalled, "the timestamp must be persisted, not just displayed")
    }

    /// The spinner must be visible the instant the action is triggered. `performManualSync` sets the
    /// flag synchronously and only then spawns the work, which is what makes that true.
    func test_performManualSync_setsIsSyncingSynchronously() async {
        sut.performManualSync()
        XCTAssertTrue(sut.isSyncing, "the flag must be set before the first suspension point")
        await waitUntil { !self.sut.isSyncing }
        XCTAssertFalse(sut.isSyncing)
    }

    func test_performManualSync_success_refreshesTheItemList() async throws {
        await populate([login(id: "1", name: "Alpha")])
        await waitForItems(["1"])

        // The sync writes new items into the store, as the real one does.
        await vault.populate(items: [login(id: "1", name: "Alpha"), login(id: "2", name: "Bravo")],
                             folders: [], organizations: [], collections: [], syncedAt: .now)

        sut.performManualSync()
        await waitUntil { !self.sut.isSyncing }

        await waitForItems(["1", "2"])
    }

    // MARK: - Manual sync: failure

    func test_performManualSync_failure_surfacesTheBannerAndKeepsTheTimestamp() async throws {
        // The view model seeds `lastSyncedAt` from the timestamp repository, so this is the value
        // carried over from the last successful sync.
        XCTAssertEqual(sut.lastSyncedAt, storedSyncDate)
        struct Boom: LocalizedError { var errorDescription: String? { "network down" } }
        sync.executeError = Boom()

        sut.performManualSync()
        await waitUntil { !self.sut.isSyncing }

        XCTAssertEqual(sut.syncErrorMessage, "network down")
        XCTAssertEqual(sut.lastSyncedAt, storedSyncDate,
                       "the timestamp reflects the last *successful* sync and must not move")
        XCTAssertFalse(syncTimestamp.recordCalled)
    }

    // MARK: - Manual sync: re-entrancy

    /// Two ⌘R presses in quick succession must produce one sync. `SyncRepositoryImpl` would reject
    /// the second, but only after the user saw an error banner for something that is not an error.
    func test_performManualSync_secondCallWhileInFlightIsIgnored() async throws {
        sut.performManualSync()
        sut.performManualSync()
        sut.performManualSync()

        await waitUntil { !self.sut.isSyncing }
        // Give any erroneously-spawned extra tasks a chance to run before asserting.
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(sync.executeCallCount, 1)
    }

    func test_performManualSync_canRunAgainAfterTheFirstCompletes() async throws {
        sut.performManualSync()
        await waitUntil { !self.sut.isSyncing }

        sut.performManualSync()
        await waitUntil { !self.sut.isSyncing }

        XCTAssertEqual(sync.executeCallCount, 2)
    }

    // MARK: - Duplicate

    func test_duplicateItem_success_selectsTheCopyAndRefreshesTheList() async throws {
        let source = login(id: "1", name: "GitHub")
        await populate([source])
        let copy = VaultItem(
            id: "2", name: "GitHub (copy)", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now, content: source.content
        )
        duplicate.stubbedResult = copy

        sut.duplicateItem(id: "1")
        await waitUntil { self.sut.itemSelection?.id == "2" }

        XCTAssertEqual(duplicate.lastId, "1")
        XCTAssertEqual(sut.itemSelection?.id, "2", "the copy is selected so it can be edited at once")
        XCTAssertNil(sut.actionError)
    }

    func test_duplicateItem_failure_reportsAndLeavesTheSelectionAlone() async throws {
        await populate([login(id: "1", name: "GitHub")])
        sut.itemSelection = sut.displayedItems.first
        struct Boom: LocalizedError { var errorDescription: String? { "server said no" } }
        duplicate.stubbedError = Boom()

        sut.duplicateItem(id: "1")
        await waitUntil { self.sut.actionError != nil }

        XCTAssertEqual(sut.actionError, "server said no")
        XCTAssertEqual(sut.itemSelection?.id, "1", "a failed duplicate must not move the selection")
    }

    func test_duplicateItem_unknownId_reportsAnError() async throws {
        await populate([])

        sut.duplicateItem(id: "missing")
        await waitUntil { self.sut.actionError != nil }

        XCTAssertNotNil(sut.actionError)
    }

    // MARK: - Empty Trash

    func test_performEmptyTrash_success_refreshesWithoutAnError() async throws {
        await populate([login(id: "1", name: "Gone", isDeleted: true), login(id: "2", name: "Kept")])
        emptyTrash.stubbedResult = EmptyTrashResult(deletedCount: 1, failedCount: 0, errorMessage: nil)

        await sut.performEmptyTrash()

        XCTAssertEqual(emptyTrash.callCount, 1)
        XCTAssertNil(sut.actionError)
    }

    func test_performEmptyTrash_partialFailure_reportsTheCounts() async throws {
        await populate([login(id: "1", name: "A", isDeleted: true),
                        login(id: "2", name: "B", isDeleted: true)])
        emptyTrash.stubbedResult = EmptyTrashResult(deletedCount: 1, failedCount: 1,
                                                    errorMessage: "one failed")

        await sut.performEmptyTrash()

        let message = try XCTUnwrap(sut.actionError)
        XCTAssertTrue(message.contains("1"), "the message must name how many could not be deleted: \(message)")
        XCTAssertTrue(message.contains("2"), "…and out of how many: \(message)")
    }

    func test_performEmptyTrash_nothingToDelete_isSilent() async throws {
        await populate([login(id: "1", name: "Kept")])
        emptyTrash.stubbedResult = .none

        await sut.performEmptyTrash()

        XCTAssertNil(sut.actionError)
    }

    /// On a partial failure the selected item may well still be in Trash. Clearing the detail pane
    /// would claim it was deleted.
    func test_performEmptyTrash_keepsTheSelectionWhenTheItemSurvives() async throws {
        let trashed = login(id: "1", name: "Still here", isDeleted: true)
        await populate([trashed])
        sut.itemSelection = trashed
        emptyTrash.stubbedResult = EmptyTrashResult(deletedCount: 0, failedCount: 1,
                                                    errorMessage: "nope")

        await sut.performEmptyTrash()

        XCTAssertEqual(sut.itemSelection?.id, "1")
    }

    func test_performEmptyTrash_deselectsAnItemThatIsActuallyGone() async throws {
        let trashed = login(id: "1", name: "Gone", isDeleted: true)
        await populate([trashed])
        sut.itemSelection = trashed
        emptyTrash.stubbedResult = EmptyTrashResult(deletedCount: 1, failedCount: 0, errorMessage: nil)
        // The stub reports the outcome but does not touch the store, so emulate the deletion.
        await vault.populate(items: [], folders: [], organizations: [], collections: [], syncedAt: .now)

        await sut.performEmptyTrash()

        XCTAssertNil(sut.itemSelection)
    }

    /// An active item being selected must not be deselected by emptying Trash — it was never in it.
    func test_performEmptyTrash_leavesAnActiveSelectionAlone() async throws {
        let active = login(id: "1", name: "Active")
        await populate([active])
        sut.itemSelection = active
        emptyTrash.stubbedResult = EmptyTrashResult(deletedCount: 0, failedCount: 0, errorMessage: nil)

        await sut.performEmptyTrash()

        XCTAssertEqual(sut.itemSelection?.id, "1")
    }

    // MARK: - Sort order

    func test_sortOrder_defaultsToNameAscending() async throws {
        await populate([login(id: "2", name: "Bravo"), login(id: "1", name: "Alpha")])

        XCTAssertEqual(sut.sortOrder, .nameAscending)
        await waitForItems(["1", "2"])
    }

    func test_sortOrder_changeReSortsAndPersists() async throws {
        await populate([login(id: "1", name: "Alpha"), login(id: "2", name: "Bravo")])
        await waitForItems(["1", "2"])

        sut.sortOrder = .nameDescending

        await waitForItems(["2", "1"])
        XCTAssertEqual(ItemSortPreference.load(), .nameDescending, "the choice must survive relaunch")
    }

    func test_sortOrder_byModificationDate() async throws {
        let older = login(id: "1", name: "Alpha",
                          created: Date(timeIntervalSince1970: 1_700_000_000),
                          modified: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = login(id: "2", name: "Bravo",
                          created: Date(timeIntervalSince1970: 1_700_000_000),
                          modified: Date(timeIntervalSince1970: 1_700_001_000))
        await populate([older, newer])

        sut.sortOrder = .modifiedNewestFirst
        await waitForItems(["2", "1"])

        sut.sortOrder = .modifiedOldestFirst
        await waitForItems(["1", "2"])
    }

    func test_sortOrder_isRestoredOnANewViewModel() async throws {
        ItemSortPreference.save(.createdNewestFirst)

        let restored = makeSUT()

        XCTAssertEqual(restored.sortOrder, .createdNewestFirst)
    }

    // MARK: - Clipboard clear

    func test_copy_putsTheValueOnThePasteboardAndSchedulesAClear() async throws {
        ClipboardClearInterval.save(.tenSeconds)

        sut.copy("hunter2")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hunter2")
        XCTAssertTrue(sut.isClipboardClearPending)
    }

    /// "Never" must schedule nothing at all — not a very long timer, which would still depend on
    /// the process outliving it.
    func test_copy_withNever_schedulesNoClear() async throws {
        ClipboardClearInterval.save(.never)

        sut.copy("hunter2")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hunter2")
        XCTAssertFalse(sut.isClipboardClearPending)
    }

    func test_copy_secondCopyReplacesThePendingClear() async throws {
        ClipboardClearInterval.save(.tenSeconds)

        sut.copy("first")
        XCTAssertTrue(sut.isClipboardClearPending)

        sut.copy("second")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "second")
        XCTAssertTrue(sut.isClipboardClearPending, "the second copy owns the pending clear")
    }

    /// Changing the setting to "Never" and copying again must cancel a clear that was already
    /// scheduled — otherwise the setting would appear not to take effect.
    func test_copy_withNeverAfterAFiniteCopy_cancelsThePendingClear() async throws {
        ClipboardClearInterval.save(.tenSeconds)
        sut.copy("first")
        XCTAssertTrue(sut.isClipboardClearPending)

        ClipboardClearInterval.save(.never)
        sut.copy("second")

        XCTAssertFalse(sut.isClipboardClearPending)
    }
}

// MARK: - File-private action doubles
//
// Same-named stubs exist in other suites; top-level `private` is file-scoped in Swift, so these do
// not collide with them.

@MainActor private final class StubDelete: DeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class StubPermanentDelete: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class StubRestore: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct StubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
@MainActor private struct StubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
@MainActor private struct StubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct StubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
@MainActor private struct StubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
@MainActor private struct StubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
@MainActor private struct StubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
