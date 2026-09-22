import XCTest
@testable import Prizm

/// The presentation-layer half of the lock race: a sync that comes back after the session ended must
/// not write decrypted content into the view model — the unlock screen would otherwise be repopulated
/// by a sync the user cancelled by locking.
@MainActor
final class VaultBrowserViewModelSessionEpochTests: XCTestCase {

    private var vault:    MockVaultRepository!
    private var syncRepo: MockSyncTimestampRepository!
    private var sync:     MockSyncUseCase!
    private var epoch:    SessionEpoch!
    private var sut:      VaultBrowserViewModel!

    override func setUp() async throws {
        try await super.setUp()
        vault    = MockVaultRepository()
        syncRepo = MockSyncTimestampRepository(storedDate: nil)
        sync     = MockSyncUseCase()
        epoch    = SessionEpoch()
        sut      = makeViewModel()
    }

    private func makeViewModel() -> VaultBrowserViewModel {
        VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          HoldableDeleteUseCase(),
            permanentDelete: StubEpochPermanentDeleteUseCase(),
            restore:         StubEpochRestoreUseCase(),
            duplicate:       NoopDuplicateUseCase(),
            emptyTrash:      StubEmptyTrashUseCase(),
            sync:            sync,
            createFolder:     StubEpochCreateFolder(),
            renameFolder:     StubEpochRenameFolder(),
            deleteFolder:     StubEpochDeleteFolder(),
            moveItem:         StubEpochMoveItem(),
            createCollection: StubEpochCreateCollection(),
            renameCollection: StubEpochRenameCollection(),
            deleteCollection: StubEpochDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo),
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        { _, _ in nil },
            filePicker:       { nil },
            sessionEpoch:     epoch
        )
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(60)) }

    private func seedStore(items: Int = 1, folders: Int = 1) async {
        await vault.populate(
            items:         (0..<items).map { i in
                VaultItem(
                    id: "\(i)", name: "Item \(i)", isFavorite: false, isDeleted: false,
                    creationDate: .now, revisionDate: .now,
                    content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
                )
            },
            folders:       (0..<folders).map { Folder(id: "f\($0)", name: "Folder \($0)") },
            organizations: [],
            collections:   [],
            syncedAt:      Date()
        )
        // The store has data, and the view model is deterministically empty — rather than relying on
        // the ordering of the `refreshItems()` that `init` kicks off. The settle lets those land
        // first, so the clear below is the last word.
        try? await Task.sleep(for: .milliseconds(50))
        sut.clearSessionState()
    }

    /// Holds the sync open, advances the epoch (as a lock would), then lets it return.
    private func runSyncAndEndTheSession(_ start: () -> Void) async {
        sync.stubbedDelay = .milliseconds(300)
        start()
        await waitUntil { self.sut.isSyncing }
        epoch.advance()
        await waitUntil { !self.sut.isSyncing }
        await settle()
    }

    // MARK: - 5.1 a background result from a dead session is discarded

    func testBackgroundSync_returningAfterTheSessionEnded_leavesTheViewModelUntouched() async throws {
        await seedStore()
        sync.stubbedResult = SyncResult(syncedAt: Date(), totalCiphers: 5, failedDecryptionCount: 0)

        await runSyncAndEndTheSession { self.sut.backgroundSync() }

        XCTAssertTrue(
            sut.displayedItems.isEmpty,
            "the unlock screen must not be repopulated by a sync that outlived its session"
        )
        XCTAssertTrue(sut.folders.isEmpty)
        XCTAssertNil(sut.lastSyncedAt)
        XCTAssertFalse(syncRepo.recordCalled, "a discarded result is not a successful sync")
        XCTAssertNil(sut.syncErrorMessage, "and it is not a failure to report either")
    }

    // MARK: - 5.2 the same for a manual sync

    func testManualSync_returningAfterTheSessionEnded_leavesTheViewModelUntouched() async throws {
        await seedStore()
        sync.stubbedResult = SyncResult(syncedAt: Date(), totalCiphers: 5, failedDecryptionCount: 0)

        await runSyncAndEndTheSession { self.sut.performManualSync() }

        XCTAssertTrue(sut.displayedItems.isEmpty)
        XCTAssertTrue(sut.folders.isEmpty)
        XCTAssertNil(sut.lastSyncedAt)
        XCTAssertNil(sut.syncErrorMessage, "locking is not a sync failure the user must dismiss")
    }

    /// A failure that arrives after the session ended is equally not worth reporting — the user
    /// pressed ⌘L, they are not owed an error about the work they cancelled.
    func testBackgroundSync_failingAfterTheSessionEnded_doesNotRaiseABanner() async throws {
        sync.executeError = SyncError.networkUnavailable

        await runSyncAndEndTheSession { self.sut.backgroundSync() }

        XCTAssertNil(sut.syncErrorMessage)
    }

    // MARK: - 5.3 the in-flight flag is released even when the result is discarded

    /// A flag left set disables every later sync for the rest of the session — which, after a
    /// re-unlock, is the rest of the app's life.
    func testDiscardedSync_stillClearsIsSyncing() async throws {
        await runSyncAndEndTheSession { self.sut.backgroundSync() }

        XCTAssertFalse(sut.isSyncing, "the next sync must be able to start")
    }

    // MARK: - The live-session case is unaffected

    func testSync_withinItsSession_stillRefreshesTheViewModel() async throws {
        await seedStore()
        sync.stubbedResult = SyncResult(syncedAt: Date(), totalCiphers: 1, failedDecryptionCount: 0)

        sut.backgroundSync()
        await waitUntil { self.sync.executeCallCount == 1 }
        await waitUntil { !self.sut.displayedItems.isEmpty }

        XCTAssertFalse(sut.displayedItems.isEmpty)
        XCTAssertNotNil(sut.lastSyncedAt)
    }
}

// MARK: - Stubs

private final class StubEpochPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
private final class StubEpochRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
private struct StubEpochCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubEpochRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubEpochDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubEpochMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubEpochCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubEpochRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubEpochDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
