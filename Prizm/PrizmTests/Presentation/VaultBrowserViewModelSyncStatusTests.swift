import XCTest
@testable import Prizm

@MainActor
final class VaultBrowserViewModelSyncStatusTests: XCTestCase {

    private var vault:    MockVaultRepository!
    private var syncRepo: MockSyncTimestampRepository!
    private var sut:      VaultBrowserViewModel!

    override func setUp() async throws {
        try await super.setUp()
        vault    = MockVaultRepository()
        syncRepo = MockSyncTimestampRepository(storedDate: nil)
        sut = makeViewModel()
    }

    private func makeViewModel(storedDate: Date? = nil) -> VaultBrowserViewModel {
        let repo    = MockSyncTimestampRepository(storedDate: storedDate)
        syncRepo    = repo
        let useCase = GetLastSyncDateUseCaseImpl(repository: repo)
        return VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          StubVaultDeleteUseCase(),
            permanentDelete: StubVaultPermanentDeleteUseCase(),
            restore:         StubVaultRestoreUseCase(),
            duplicate:       NoopDuplicateUseCase(),
            emptyTrash:      StubEmptyTrashUseCase(),
            sync:            MockSyncUseCase(),
            createFolder:     StubCreateFolder(),
            renameFolder:     StubRenameFolder(),
            deleteFolder:     StubDeleteFolder(),
            moveItem:         StubMoveItem(),
            createCollection: StubCreateCollection(),
            renameCollection: StubRenameCollection(),
            deleteCollection: StubDeleteCollection(),
            syncTimestamp:    repo,
            getLastSyncDate:  useCase,
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        { _, _ in nil },
            filePicker:       { nil }
        )
    }

    // MARK: - 1. lastSyncedAt is nil when repository has no stored date

    func testInit_lastSyncedAt_isNil_whenNoStoredDate() async {
        XCTAssertNil(sut.lastSyncedAt)
    }

    // MARK: - 2. lastSyncedAt is loaded from use case on init

    func testInit_lastSyncedAt_loadedFromUseCase() async {
        let stored = Date(timeIntervalSince1970: 1_000_000)
        let vm = makeViewModel(storedDate: stored)
        XCTAssertEqual(vm.lastSyncedAt, stored)
    }

    // MARK: - 3. syncStatusLabel is "Never synced" when no date

    func testInit_syncStatusLabel_isNeverSynced_whenNoDate() async {
        XCTAssertEqual(sut.syncStatusLabel, "Never synced")
    }

    // MARK: - 4. handleSyncCompleted updates lastSyncedAt and calls recordSuccessfulSync

    func testHandleSyncCompleted_updatesLastSyncedAt_andRecordsTimestamp() async {
        let date = Date()
        sut.handleSyncCompleted(SyncResult(syncedAt: date, totalCiphers: 3, failedDecryptionCount: 0))

        XCTAssertEqual(sut.lastSyncedAt, date)
        XCTAssertTrue(syncRepo.recordCalled, "recordSuccessfulSync() should be called on sync success")
    }

    // MARK: - 5. syncStatusLabel updates after handleSyncCompleted

    func testHandleSyncCompleted_updatesSyncStatusLabel() async {
        let date = Date()
        sut.handleSyncCompleted(SyncResult(syncedAt: date, totalCiphers: 0, failedDecryptionCount: 0))

        XCTAssertNotEqual(sut.syncStatusLabel, "Never synced")
        XCTAssertTrue(sut.syncStatusLabel.hasPrefix("Synced"))
    }

    // MARK: - 5b. A cache-sourced sync reports the payload's age and records nothing

    /// The label must describe the data, not the attempt: this is the only thing standing between a
    /// user and a vault that looks current while the network is gone.
    func testHandleSyncCompleted_cacheSourced_doesNotRecordTimestamp() async {
        let payloadWrittenAt = Date(timeIntervalSinceNow: -3 * 3600)
        sut.handleSyncCompleted(SyncResult(
            syncedAt:              Date(),
            totalCiphers:          4,
            failedDecryptionCount: 0,
            source:                .cache,
            payloadTimestamp:      payloadWrittenAt
        ))

        XCTAssertEqual(sut.syncSource, .cache)
        XCTAssertFalse(
            syncRepo.recordCalled,
            "A cache read is not a successful server sync and must not be recorded as one"
        )
        XCTAssertNil(sut.lastSyncedAt, "The persisted last-sync timestamp must not move")
        XCTAssertTrue(
            sut.syncStatusLabel.hasPrefix("Offline"),
            "Expected an offline label; got: \(sut.syncStatusLabel)"
        )
    }

    /// The payload's own time is what the label reports, not the moment the cache was read.
    func testHandleSyncCompleted_cacheSourced_labelCarriesPayloadTime() async {
        let payloadWrittenAt = Date(timeIntervalSince1970: 1_600_000_000)
        sut.handleSyncCompleted(SyncResult(
            syncedAt:              Date(),
            totalCiphers:          1,
            failedDecryptionCount: 0,
            source:                .cache,
            payloadTimestamp:      payloadWrittenAt
        ))

        XCTAssertTrue(
            sut.syncStatusLabel.contains(OfflineSyncLabel.make(payloadTimestamp: payloadWrittenAt)),
            "Expected the payload's own time in the label; got: \(sut.syncStatusLabel)"
        )
    }

    // MARK: - 5c. Entering the vault without a sync records nothing

    func testHandleVaultEnteredWithoutSync_leavesTimestampAlone() async {
        sut.handleVaultEnteredWithoutSync()

        XCTAssertNil(sut.lastSyncedAt)
        XCTAssertFalse(syncRepo.recordCalled)
        XCTAssertEqual(sut.syncStatusLabel, "Never synced")
    }

    // MARK: - 6. handleSyncError does NOT call recordSuccessfulSync

    func testHandleSyncError_doesNotRecordTimestamp() async {
        sut.handleSyncError("Network unavailable")

        XCTAssertFalse(syncRepo.recordCalled, "recordSuccessfulSync() must not be called on sync failure")
    }
}

// MARK: - Stubs

private final class StubVaultDeleteUseCase: DeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
private final class StubVaultPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
private final class StubVaultRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
private struct StubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
