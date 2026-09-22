import XCTest
@testable import Prizm

/// Surfacing the items a sync could not read.
///
/// The count already existed and already reached `SyncResult`; its only consumer was a log line. So
/// the vault looked complete while quietly being short, and the user's reasonable conclusion was
/// that they had never saved the missing items.
@MainActor
final class UnreadableItemCountTests: XCTestCase {

    private var vault:    MockVaultRepository!
    private var syncRepo: MockSyncTimestampRepository!
    private var sync:     MockSyncUseCase!
    private var sut:      VaultBrowserViewModel!

    override func setUp() async throws {
        try await super.setUp()
        vault    = MockVaultRepository()
        syncRepo = MockSyncTimestampRepository(storedDate: nil)
        sync     = MockSyncUseCase()
        sut      = makeViewModel()
    }

    private func makeViewModel() -> VaultBrowserViewModel {
        VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          HoldableDeleteUseCase(),
            permanentDelete: StubUnreadablePermanentDeleteUseCase(),
            restore:         StubUnreadableRestoreUseCase(),
            duplicate:       NoopDuplicateUseCase(),
            emptyTrash:      StubEmptyTrashUseCase(),
            sync:            sync,
            createFolder:     StubUnreadableCreateFolder(),
            renameFolder:     StubUnreadableRenameFolder(),
            deleteFolder:     StubUnreadableDeleteFolder(),
            moveItem:         StubUnreadableMoveItem(),
            createCollection: StubUnreadableCreateCollection(),
            renameCollection: StubUnreadableRenameCollection(),
            deleteCollection: StubUnreadableDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo),
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        { _, _ in nil },
            filePicker:       { nil }
        )
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - 2.1 the count reaches the view model

    func testSync_withUnreadableItems_publishesTheCount() async throws {
        sync.stubbedResult = SyncResult(syncedAt: Date(), totalCiphers: 10, failedDecryptionCount: 3)

        sut.performManualSync()
        await waitUntil { self.sync.executeCallCount == 1 }
        await waitUntil { self.sut.unreadableItemCount == 3 }

        XCTAssertEqual(sut.unreadableItemCount, 3)
    }

    // MARK: - 2.2 a clean sync clears it

    func testSync_readingEverything_clearsTheCount() async throws {
        sync.stubbedResult = SyncResult(syncedAt: Date(), totalCiphers: 10, failedDecryptionCount: 3)
        sut.performManualSync()
        await waitUntil { self.sut.unreadableItemCount == 3 }

        sync.stubbedResult = SyncResult(syncedAt: Date(), totalCiphers: 10, failedDecryptionCount: 0)
        sut.performManualSync()
        await waitUntil { self.sut.unreadableItemCount == 0 }

        XCTAssertEqual(sut.unreadableItemCount, 0, "a complete vault must stop reporting a problem")
    }

    // MARK: - 2.3 it does not outlive its session

    func testClearSessionState_clearsTheCount() async throws {
        sut.handleSyncCompleted(SyncResult(syncedAt: Date(), totalCiphers: 10, failedDecryptionCount: 2))
        XCTAssertEqual(sut.unreadableItemCount, 2, "precondition")

        sut.clearSessionState()

        XCTAssertEqual(
            sut.unreadableItemCount, 0,
            "the count describes a session's vault, so it cannot survive that session"
        )
    }

    // MARK: - 2.5 a session that never synced reports nothing

    func testInit_neverSynced_reportsNothing() {
        XCTAssertEqual(sut.unreadableItemCount, 0)
    }

    func testHandleVaultEnteredWithoutSync_leavesTheCountAlone() async throws {
        sut.handleVaultEnteredWithoutSync()

        XCTAssertEqual(sut.unreadableItemCount, 0)
    }
}

// MARK: - Stubs

private final class StubUnreadablePermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
private final class StubUnreadableRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
private struct StubUnreadableCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubUnreadableRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubUnreadableDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubUnreadableMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubUnreadableCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubUnreadableRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubUnreadableDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
