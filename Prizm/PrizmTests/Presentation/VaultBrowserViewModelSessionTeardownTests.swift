import XCTest
@testable import Prizm

/// `VaultBrowserViewModel.clearSessionState()` — the half of the teardown that the store clearing
/// does not reach.
///
/// Locking zeroes the keys and empties the vault store. Everything asserted here is a *second* copy
/// of the same plaintext, held in the presentation layer, that used to survive the lock: the item
/// list, the selection, decrypted folder and organisation names, the search query, reveals and
/// pending re-prompt state.
@MainActor
final class VaultBrowserViewModelSessionTeardownTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut:   VaultBrowserViewModel!

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        sut   = makeViewModel()
    }

    private func makeViewModel() -> VaultBrowserViewModel {
        VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          HoldableDeleteUseCase(),
            permanentDelete: StubTeardownPermanentDeleteUseCase(),
            restore:         StubTeardownRestoreUseCase(),
            duplicate:       NoopDuplicateUseCase(),
            emptyTrash:      StubEmptyTrashUseCase(),
            sync:            MockSyncUseCase(),
            createFolder:     StubTeardownCreateFolder(),
            renameFolder:     StubTeardownRenameFolder(),
            deleteFolder:     StubTeardownDeleteFolder(),
            moveItem:         StubTeardownMoveItem(),
            createCollection: StubTeardownCreateCollection(),
            renameCollection: StubTeardownRenameCollection(),
            deleteCollection: StubTeardownDeleteCollection(),
            syncTimestamp:    MockSyncTimestampRepository(storedDate: nil),
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: MockSyncTimestampRepository(storedDate: nil)),
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        { _, _ in nil },
            filePicker:       { nil }
        )
    }

    private func item(id: String = "1", name: String = "GitHub") -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: "octocat", password: "s3cret", uris: [],
                                         totp: "JBSWY3DPEHPK3PXP", notes: "notes", customFields: []))
        )
    }

    /// Puts the view model into the state a user leaves it in: something loaded, selected and typed.
    private func loadAndSelect() async {
        await vault.populate(
            items:         [item()],
            folders:       [Folder(id: "f1", name: "Work")],
            organizations: [Organization(id: "o1", name: "Acme", role: .user)],
            collections:   [OrgCollection(id: "c1", organizationId: "o1", name: "Shared")],
            syncedAt:      Date()
        )
        sut.refreshItems()
        sut.refreshCounts()
        sut.refreshFolders()
        sut.refreshOrganizations()
        await waitUntil { !self.sut.displayedItems.isEmpty }
        await waitUntil { !self.sut.folders.isEmpty }
        await waitUntil { !self.sut.organizations.isEmpty }
        sut.selectItem(id: "1")
        await waitUntil { self.sut.itemSelection != nil }
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - 2.1.1 / 2.1.2 the item list and the selection

    func testClearSessionState_emptiesTheItemListAndTheSelection() async throws {
        await loadAndSelect()
        XCTAssertFalse(sut.displayedItems.isEmpty, "precondition: items are loaded")
        XCTAssertNotNil(sut.itemSelection, "precondition: an item is selected")

        sut.clearSessionState()

        XCTAssertTrue(sut.displayedItems.isEmpty, "the decrypted items are still in memory otherwise")
        XCTAssertNil(sut.itemSelection)
    }

    // MARK: - 2.1.3 / 2.1.4 decrypted names

    func testClearSessionState_clearsDecryptedNames() async throws {
        await loadAndSelect()
        XCTAssertFalse(sut.folders.isEmpty, "precondition: folders are loaded")
        XCTAssertFalse(sut.organizations.isEmpty, "precondition: organisations are loaded")
        XCTAssertFalse(sut.collections.isEmpty, "precondition: collections are loaded")

        sut.clearSessionState()

        XCTAssertTrue(sut.folders.isEmpty, "a folder name is decrypted plaintext")
        XCTAssertTrue(sut.organizations.isEmpty)
        XCTAssertTrue(sut.collections.isEmpty)
    }

    // MARK: - 2.1.5 the search query

    func testClearSessionState_clearsTheSearchQueryAndExitsGlobalSearch() async throws {
        sut.searchQuery = "hunter2"
        sut.activateGlobalSearch()
        XCTAssertTrue(sut.isGlobalSearch, "precondition: global search is active")

        sut.clearSessionState()

        XCTAssertTrue(sut.searchQuery.isEmpty, "what the user searched a password manager for is a secret")
        XCTAssertFalse(sut.isGlobalSearch)
    }

    // MARK: - 2.1.6 reveals

    func testClearSessionState_discardsReveals() async throws {
        await loadAndSelect()
        sut.toggleReveal(itemId: "1")
        XCTAssertTrue(sut.isRevealed("1"), "precondition: the field is revealed")

        sut.clearSessionState()

        XCTAssertFalse(sut.isRevealed("1"))
    }

    // MARK: - 2.1.7 pending re-prompt state

    func testClearSessionState_clearsPendingRepromptState() async throws {
        await loadAndSelect()
        // Set directly rather than by driving `requestReveal`, which needs a re-prompt gate and an
        // item carrying the flag — neither of which is what this test is about.
        sut.pendingReprompt = PendingReprompt(itemId: "1", itemName: "GitHub")

        sut.clearSessionState()

        XCTAssertNil(sut.pendingReprompt, "the pending prompt names an item")
        XCTAssertNil(sut.repromptError)
        XCTAssertFalse(sut.isVerifyingReprompt)
    }

    // MARK: - 2.1.8 error strings and sheets

    func testClearSessionState_clearsErrorStringsAndSheets() async throws {
        sut.syncErrorMessage  = "Cannot reach vault.example.com"
        sut.actionError       = "Item could not be deleted"
        sut.createItemType    = .login

        sut.clearSessionState()

        XCTAssertNil(sut.syncErrorMessage)
        XCTAssertNil(sut.actionError)
        XCTAssertNil(sut.createItemType)
    }

    // MARK: - 2.1.9 counts

    func testClearSessionState_clearsItemCounts() async throws {
        await loadAndSelect()
        await waitUntil { !self.sut.itemCounts.isEmpty }
        XCTAssertFalse(sut.itemCounts.isEmpty, "precondition: counts are loaded")

        sut.clearSessionState()

        XCTAssertTrue(sut.itemCounts.isEmpty)
    }

    // MARK: - Idempotence

    /// Locking twice, or locking a session that never loaded anything, must not fault.
    func testClearSessionState_isIdempotent() async throws {
        await loadAndSelect()

        sut.clearSessionState()
        sut.clearSessionState()

        XCTAssertTrue(sut.displayedItems.isEmpty)
        XCTAssertNil(sut.itemSelection)
    }
}

// MARK: - Stubs

private final class StubTeardownPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
private final class StubTeardownRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
private struct StubTeardownCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubTeardownRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubTeardownDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubTeardownMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubTeardownCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubTeardownRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubTeardownDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
