import Combine
import XCTest
@testable import Prizm

/// How many times a burst of typing rewrites the item list.
///
/// Each keystroke in the search field starts a pass over the vault. The pass ends in
/// `displayedItems = sortOrder.sort(...)`, and the sort is the part that costs: it is O(n log n)
/// locale-aware comparisons, and it runs on the main actor, not on the vault repository. So five
/// keystrokes used to mean five sorts and five publishes of the list on the thread drawing it, even
/// though only the fifth could describe what the field now contains.
@MainActor
final class VaultBrowserViewModelSearchCoalescingTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var search: CoalesceStubSearch!
    private var sut:   VaultBrowserViewModel!
    private var cancellables: Set<AnyCancellable> = []

    /// Counts writes to the list, which is what the interface has to react to.
    private final class PublishCounter { var count = 0 }
    private var publishes = PublishCounter()

    override func setUp() async throws {
        try await super.setUp()
        vault  = MockVaultRepository()
        search = CoalesceStubSearch()
        let syncRepo = MockSyncTimestampRepository(storedDate: nil)
        sut = VaultBrowserViewModel(
            vault:           vault,
            search:          search,
            delete:          HoldableDeleteUseCase(),
            permanentDelete: CoalesceStubPermanentDelete(),
            restore:         CoalesceStubRestore(),
            duplicate:       NoopDuplicateUseCase(),
            emptyTrash:      StubEmptyTrashUseCase(),
            sync:            MockSyncUseCase(),
            createFolder:     CoalesceStubCreateFolder(),
            renameFolder:     CoalesceStubRenameFolder(),
            deleteFolder:     CoalesceStubDeleteFolder(),
            moveItem:         CoalesceStubMoveItem(),
            createCollection: CoalesceStubCreateCollection(),
            renameCollection: CoalesceStubRenameCollection(),
            deleteCollection: CoalesceStubDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo),
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        { _, _ in nil },
            filePicker:       { nil }
        )
        // Let whatever `init` kicks off land before counting, so the numbers below belong to the
        // keystrokes and not to construction.
        try? await Task.sleep(for: .milliseconds(120))
        search.callCount = 0
        publishes = PublishCounter()
        sut.$displayedItems.dropFirst()
            .sink { [publishes] _ in publishes.count += 1 }
            .store(in: &cancellables)
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - The burst

    /// Five queries assigned inside one main-actor turn, so all five passes are in flight at once.
    private func typeFiveQueries() async {
        for index in 1...5 { sut.searchQuery = "q\(index)" }
        // Longer than the stub's delay, so every pass has finished by the time this returns.
        try? await Task.sleep(for: .milliseconds(400))
    }

    func test_fiveQueriesRewriteTheListOnce() async {
        await typeFiveQueries()

        XCTAssertEqual(search.callCount, 5,
                       "the passes still run — this change is about what they are allowed to write")
        XCTAssertEqual(publishes.count, 1,
                       "five overlapping passes each published the list, so the pane re-rendered five "
                     + "times and four of those sorts ran on the main actor for nothing")
    }

    /// The list has to end up holding the newest query's answer, not merely one answer.
    func test_theNewestQueryOwnsTheList() async {
        await typeFiveQueries()

        XCTAssertEqual(sut.displayedItems.map(\.name), ["q5"])
    }

    /// A query typed on its own still reaches the list — the guard may drop overlapping passes, but
    /// it must not become a reason to never draw anything.
    func test_singleQueryStillLands() async {
        sut.searchQuery = "solo"
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(sut.displayedItems.map(\.name), ["solo"])
        XCTAssertEqual(publishes.count, 1)
    }
}

// MARK: - Doubles
//
// `private` because several suites declare same-named stubs for the same protocols, and top-level
// `private` is file-scoped in Swift.

/// Returns one item named after the query, so a pass's result identifies the query that produced it,
/// and holds long enough that a burst of assignments overlaps. The count is settable because building
/// the view model asks once before any keystroke happens, and that pass is not this file's subject.
@MainActor private final class CoalesceStubSearch: SearchVaultUseCase {
    var callCount = 0
    func execute(query: String, in selection: SidebarSelection) async throws -> [VaultItem] {
        callCount += 1
        try? await Task.sleep(for: .milliseconds(80))
        return [VaultItem(id: query, name: query, isFavorite: false, isDeleted: false,
                          creationDate: .now, revisionDate: .now,
                          content: .secureNote(SecureNoteContent(notes: nil, customFields: [])))]
    }
}

@MainActor private final class CoalesceStubPermanentDelete: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class CoalesceStubRestore: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct CoalesceStubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
@MainActor private struct CoalesceStubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
@MainActor private struct CoalesceStubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct CoalesceStubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
@MainActor private struct CoalesceStubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
@MainActor private struct CoalesceStubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
@MainActor private struct CoalesceStubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
