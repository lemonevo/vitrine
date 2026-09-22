import XCTest
@testable import Prizm

/// `VaultBrowserViewModel`'s background-sync entry point.
///
/// The decision — whether a tick *should* become a sync — belongs to `BackgroundSyncMonitorTests`.
/// What this suite pins is what happens once it does: the shared in-flight guard, the refreshed
/// state on success, and the two ways the background origin deliberately differs from the manual one.
@MainActor
final class VaultBrowserViewModelBackgroundSyncTests: XCTestCase {

    private var vault:    MockVaultRepository!
    private var syncRepo: MockSyncTimestampRepository!
    private var sync:     MockSyncUseCase!
    private var delete:   HoldingDeleteUseCase!
    private var sut:      VaultBrowserViewModel!

    override func setUp() async throws {
        try await super.setUp()
        vault    = MockVaultRepository()
        syncRepo = MockSyncTimestampRepository(storedDate: nil)
        sync     = MockSyncUseCase()
        delete   = HoldingDeleteUseCase()
        sut      = makeViewModel()
    }

    private func makeViewModel(
        duplicate: (any DuplicateVaultItemUseCase)? = nil
    ) -> VaultBrowserViewModel {
        VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          delete,
            permanentDelete: StubBackgroundPermanentDeleteUseCase(),
            restore:         StubBackgroundRestoreUseCase(),
            duplicate:       duplicate ?? NoopDuplicateUseCase(),
            emptyTrash:      StubEmptyTrashUseCase(),
            sync:            sync,
            createFolder:     StubBackgroundCreateFolder(),
            renameFolder:     StubBackgroundRenameFolder(),
            deleteFolder:     StubBackgroundDeleteFolder(),
            moveItem:         StubBackgroundMoveItem(),
            createCollection: StubBackgroundCreateCollection(),
            renameCollection: StubBackgroundRenameCollection(),
            deleteCollection: StubBackgroundDeleteCollection(),
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

    /// Lets a launched `Task` reach its first suspension point without asserting on timing.
    private func settle() async { try? await Task.sleep(for: .milliseconds(60)) }

    private func item(id: String = "1", name: String = "GitHub") -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: "octocat", password: "p", uris: [],
                                         totp: nil, notes: nil, customFields: []))
        )
    }

    /// Seeds the store the way a sync would, so "the view model read it" is an observation rather
    /// than a guess.
    private func seedStore(items: [VaultItem] = [], folders: [Folder] = [],
                           organizations: [Organization] = []) async {
        await vault.populate(items: items, folders: folders, organizations: organizations,
                             collections: [], syncedAt: Date())
    }

    // MARK: - 3.1 the in-flight flag behaves as the manual path's does

    func testBackgroundSync_setsAndClearsIsSyncing() async throws {
        XCTAssertFalse(sut.isSyncing)
        sync.stubbedDelay = .milliseconds(200)

        sut.backgroundSync()

        await waitUntil { self.sut.isSyncing }
        XCTAssertTrue(sut.isSyncing, "the toolbar indicator is shared with the manual path")

        await waitUntil { !self.sut.isSyncing }
        XCTAssertFalse(sut.isSyncing)
        XCTAssertEqual(sync.executeCallCount, 1)
    }

    // MARK: - 3.2 the guard is shared, not duplicated

    /// A tick that lands during a manual sync performs no second sync. This is what the single
    /// `guard` in `performSync(origin:)` buys: two origins, one in-flight flag.
    func testBackgroundSync_whileASyncIsInFlight_doesNotStartASecond() async throws {
        sync.stubbedDelay = .milliseconds(300)

        sut.performManualSync()
        await waitUntil { self.sut.isSyncing }

        sut.backgroundSync()
        await settle()

        XCTAssertEqual(sync.executeCallCount, 1, "the background tick must be refused, not queued")
    }

    /// …and the reverse, so the guard is not merely "manual wins".
    func testManualSync_whileABackgroundSyncIsInFlight_doesNotStartASecond() async throws {
        sync.stubbedDelay = .milliseconds(300)

        sut.backgroundSync()
        await waitUntil { self.sut.isSyncing }

        sut.performManualSync()
        await settle()

        XCTAssertEqual(sync.executeCallCount, 1)
    }

    // MARK: - 3.3 a background failure is quiet

    func testBackgroundSync_failure_doesNotRaiseTheErrorBanner() async throws {
        sync.executeError = SyncError.networkUnavailable

        sut.backgroundSync()
        await waitUntil { self.sync.executeCallCount == 1 }
        await settle()

        XCTAssertNil(
            sut.syncErrorMessage,
            "the user did not ask for this sync, so they are not made to dismiss its failure"
        )
    }

    // MARK: - 3.4 …and a manual failure still is not quiet

    /// The regression guard for 3.3: the two origins must not be collapsed into one.
    func testManualSync_failure_stillRaisesTheErrorBanner() async throws {
        sync.executeError = SyncError.networkUnavailable

        sut.performManualSync()
        await waitUntil { self.sync.executeCallCount == 1 }
        await settle()

        XCTAssertNotNil(
            sut.syncErrorMessage,
            "the user pressed the button, so the failure has to be reported"
        )
    }

    // MARK: - 3.5 a background failure leaves the clock alone

    func testBackgroundSync_failure_doesNotRecordSuccessOrMoveTheTimestamp() async throws {
        sync.executeError = SyncError.networkUnavailable

        sut.backgroundSync()
        await waitUntil { self.sync.executeCallCount == 1 }
        await settle()

        XCTAssertFalse(
            syncRepo.recordCalled,
            "a failure is not a sync; recording it would tell the next launch the vault was fetched"
        )
        XCTAssertNil(sut.lastSyncedAt, "the label must keep ageing from the last *successful* sync")
    }

    // MARK: - 3.6 a background success refreshes the vault state

    func testBackgroundSync_success_refreshesTheVaultState() async throws {
        // The store holds data the view model has not read yet; after the refresh it must be
        // visible. That is the observation, rather than an inference from a timestamp.
        await seedStore(
            items:         [item()],
            folders:       [Folder(id: "f1", name: "Work")],
            organizations: [Organization(id: "o1", name: "Acme", role: .user)]
        )
        XCTAssertTrue(sut.displayedItems.isEmpty, "precondition: nothing has been read yet")

        let syncedAt = sync.stubbedResult.syncedAt

        sut.backgroundSync()
        await waitUntil { self.sync.executeCallCount == 1 }
        await settle()

        XCTAssertEqual(sut.displayedItems.count, 1)
        XCTAssertEqual(sut.folders.count, 1)
        XCTAssertEqual(sut.organizations.count, 1)
        XCTAssertEqual(sut.lastSyncedAt, syncedAt, "a successful refresh advances the timestamp")
        XCTAssertTrue(syncRepo.recordCalled, "and persists it, so it survives a restart")
        XCTAssertNil(sut.syncErrorMessage)
    }

    // MARK: - The offline-cache cross-check

    /// The two changes meet here. A background refresh against an unreachable server now succeeds
    /// from the cache — and that must not be recorded as a server sync, or the label would claim the
    /// vault is current at the very moment the network is gone.
    func testBackgroundSync_cacheSourced_doesNotMoveTheTimestamp() async throws {
        let payloadWrittenAt = Date(timeIntervalSinceNow: -4 * 3600)
        sync.stubbedResult = SyncResult(
            syncedAt:              Date(),
            totalCiphers:          2,
            failedDecryptionCount: 0,
            source:                .cache,
            payloadTimestamp:      payloadWrittenAt
        )

        sut.backgroundSync()
        await waitUntil { self.sync.executeCallCount == 1 }
        await settle()

        XCTAssertEqual(sut.syncSource, .cache)
        XCTAssertFalse(syncRepo.recordCalled)
        XCTAssertNil(sut.lastSyncedAt, "a cache read is not a server sync")
        XCTAssertTrue(sut.syncStatusLabel.hasPrefix("Offline"))
    }

    // MARK: - 3.8 isMutating

    func testIsMutating_isFalseWhenIdle() {
        XCTAssertFalse(sut.isMutating)
    }

    func testIsMutating_isTrueWhileADeleteIsInFlight_andClearedAfterwards() async throws {
        await seedStore(items: [item()])
        delete.delay = .milliseconds(200)

        let inFlight = Task { await self.sut.performSoftDelete(id: "1") }
        await waitUntil { self.sut.isMutating }
        XCTAssertTrue(sut.isMutating, "a refresh now would replace the list under the write")

        await inFlight.value
        XCTAssertFalse(sut.isMutating, "a flag left set disables background sync for the session")
    }

    /// The failure path must clear it too, or one failed delete disables the feature for the rest of
    /// the session.
    func testIsMutating_isClearedWhenTheMutationFails() async throws {
        await seedStore(items: [item()])
        delete.error = VaultError.itemNotFound("1")

        await sut.performSoftDelete(id: "1")

        XCTAssertFalse(sut.isMutating)
    }

    /// A duplicate is a write whose completion selects the new item — exactly the state a refresh
    /// would clobber.
    func testIsMutating_isSetByDuplicate() async throws {
        let duplicate = HoldingDuplicateUseCase()
        duplicate.delay = .milliseconds(200)
        let vm = makeViewModel(duplicate: duplicate)
        await seedStore(items: [item()])

        vm.duplicateItem(id: "1")
        await waitUntil { vm.isMutating }
        XCTAssertTrue(vm.isMutating)

        await waitUntil { !vm.isMutating }
        XCTAssertFalse(vm.isMutating)
    }
}

// MARK: - Stubs

private final class HoldingDeleteUseCase: DeleteVaultItemUseCase {
    var error: Error?
    /// Holds the call open so the in-flight state is observable rather than a race.
    var delay: Duration?

    func execute(id: String) async throws {
        if let delay { try? await Task.sleep(for: delay) }
        if let error { throw error }
    }
}

private final class HoldingDuplicateUseCase: DuplicateVaultItemUseCase {
    var delay: Duration?

    func execute(id: String) async throws -> VaultItem {
        if let delay { try? await Task.sleep(for: delay) }
        return VaultItem(
            id: "copy", name: "GitHub", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
    }
}

private final class StubBackgroundPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
private final class StubBackgroundRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}

// Folder and collection CRUD is irrelevant to a background refresh; the view model needs a
// conforming value and nothing more. Named apart from the identically-shaped stubs in the sibling
// suites because top-level `private` is file-scoped in Swift.
private struct StubBackgroundCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubBackgroundRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubBackgroundDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubBackgroundMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubBackgroundCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubBackgroundRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubBackgroundDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
