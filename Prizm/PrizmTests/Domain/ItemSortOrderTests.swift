import XCTest
@testable import Prizm

/// Tests for `ItemSortOrder` and its persistence.
///
/// The interesting cases are the tie-breaks. Swift's `sorted(by:)` is not a stable sort, so two
/// items sharing a timestamp would be free to swap places between refreshes unless the comparator
/// falls back to something deterministic — that is what most of this file is about.
final class ItemSortOrderTests: XCTestCase {

    // MARK: - Fixtures

    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let t1 = t0.addingTimeInterval(60)
    private static let t2 = t0.addingTimeInterval(120)

    private func item(_ id: String, _ name: String,
                      created: Date = ItemSortOrderTests.t0,
                      modified: Date = ItemSortOrderTests.t0) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: created, revisionDate: modified,
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
    }

    private func ids(_ order: ItemSortOrder, _ items: [VaultItem]) -> [String] {
        order.sort(items).map(\.id)
    }

    // MARK: - Name orders

    func test_nameAscending_sortsCaseInsensitively() {
        let items = [item("b", "banana"), item("A", "Apple"), item("c", "cherry")]
        XCTAssertEqual(ids(.nameAscending, items), ["A", "b", "c"])
    }

    func test_nameDescending_isTheReverseOfAscending() {
        let items = [item("b", "banana"), item("A", "Apple"), item("c", "cherry")]
        XCTAssertEqual(ids(.nameDescending, items), ["c", "b", "A"])
    }

    /// Two items with the same name must not be reported as ordered relative to each other, or the
    /// comparator stops being a strict weak ordering and `sorted(by:)` is free to do anything.
    func test_nameOrder_doesNotReorderEqualNames() {
        let a = item("a", "Same")
        let b = item("b", "same")
        XCTAssertEqual(ids(.nameAscending, [a, b]).count, 2)
        XCTAssertEqual(ids(.nameDescending, [a, b]).count, 2)
    }

    // MARK: - Date orders

    func test_modifiedNewestFirst_ordersByRevisionDateDescending() {
        let items = [
            item("old",    "A", modified: Self.t0),
            item("newest", "B", modified: Self.t2),
            item("middle", "C", modified: Self.t1)
        ]
        XCTAssertEqual(ids(.modifiedNewestFirst, items), ["newest", "middle", "old"])
    }

    func test_modifiedOldestFirst_ordersByRevisionDateAscending() {
        let items = [
            item("old",    "A", modified: Self.t0),
            item("newest", "B", modified: Self.t2),
            item("middle", "C", modified: Self.t1)
        ]
        XCTAssertEqual(ids(.modifiedOldestFirst, items), ["old", "middle", "newest"])
    }

    func test_createdNewestFirst_ordersByCreationDateDescending() {
        let items = [
            item("old",    "A", created: Self.t0),
            item("newest", "B", created: Self.t2),
            item("middle", "C", created: Self.t1)
        ]
        XCTAssertEqual(ids(.createdNewestFirst, items), ["newest", "middle", "old"])
    }

    func test_createdOldestFirst_ordersByCreationDateAscending() {
        let items = [
            item("old",    "A", created: Self.t0),
            item("newest", "B", created: Self.t2),
            item("middle", "C", created: Self.t1)
        ]
        XCTAssertEqual(ids(.createdOldestFirst, items), ["old", "middle", "newest"])
    }

    /// Creation and modification are independent. An item created long ago but touched today must
    /// sort by *its* order's key, not by whichever date happens to differ.
    func test_dateOrders_useTheirOwnDate() {
        let ancient = item("ancient", "Ancient", created: Self.t0, modified: Self.t2)
        let recent  = item("recent",  "Recent",  created: Self.t2, modified: Self.t0)

        XCTAssertEqual(ids(.modifiedNewestFirst, [ancient, recent]), ["ancient", "recent"])
        XCTAssertEqual(ids(.createdNewestFirst,  [ancient, recent]), ["recent", "ancient"])
    }

    // MARK: - Tie-breaks

    /// The property that actually matters: the same input set produces the same output order no
    /// matter what order it arrives in. Without the name fallback this is not guaranteed.
    func test_dateOrder_tiesFallBackToNameAscending() {
        let a = item("a", "Alpha",   created: Self.t1, modified: Self.t1)
        let b = item("b", "Bravo",   created: Self.t1, modified: Self.t1)
        let c = item("c", "Charlie", created: Self.t1, modified: Self.t1)

        for order in [ItemSortOrder.modifiedNewestFirst, .modifiedOldestFirst,
                      .createdNewestFirst, .createdOldestFirst] {
            XCTAssertEqual(ids(order, [c, a, b]), ["a", "b", "c"], "\(order) should tie-break by name")
            XCTAssertEqual(ids(order, [b, c, a]), ["a", "b", "c"], "\(order) should tie-break by name")
        }
    }

    func test_dateOrder_tieBreakIsCaseInsensitive() {
        let a = item("a", "apple",  created: Self.t1, modified: Self.t1)
        let b = item("b", "Banana", created: Self.t1, modified: Self.t1)
        XCTAssertEqual(ids(.modifiedNewestFirst, [b, a]), ["a", "b"])
    }

    // MARK: - Metadata

    func test_allCases_haveDistinctRawValuesAndNonEmptyLabels() {
        let raws = ItemSortOrder.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "raw values must be unique")

        let labels = ItemSortOrder.allCases.map(\.displayName)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertEqual(Set(labels).count, labels.count, "labels must be distinguishable in the menu")
    }

    func test_sort_doesNotMutateInputOrLoseItems() {
        let items = [item("b", "B"), item("a", "A"), item("c", "C")]
        let sorted = ItemSortOrder.nameAscending.sort(items)
        XCTAssertEqual(sorted.count, items.count)
        XCTAssertEqual(Set(sorted.map(\.id)), Set(items.map(\.id)))
        XCTAssertEqual(items.map(\.id), ["b", "a", "c"], "the input array must be untouched")
    }

    func test_sort_emptyInput() {
        XCTAssertTrue(ItemSortOrder.nameAscending.sort([]).isEmpty)
    }
}

// MARK: - ItemSortPreference

final class ItemSortPreferenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ItemSortPreferenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_load_defaultsToNameAscendingWhenUnset() {
        XCTAssertEqual(ItemSortPreference.load(from: defaults), .nameAscending)
    }

    func test_saveThenLoad_roundTripsEveryCase() {
        for order in ItemSortOrder.allCases {
            ItemSortPreference.save(order, to: defaults)
            XCTAssertEqual(ItemSortPreference.load(from: defaults), order)
        }
    }

    /// A value written by a newer build must not be read as "the first case" — it must fall back to
    /// the documented default.
    func test_load_fallsBackForUnrecognisedValue() {
        defaults.set("someFutureOrder", forKey: ItemSortPreference.key)
        XCTAssertEqual(ItemSortPreference.load(from: defaults), .nameAscending)
    }

    func test_load_fallsBackWhenValueIsNotAString() {
        defaults.set(42, forKey: ItemSortPreference.key)
        XCTAssertEqual(ItemSortPreference.load(from: defaults), .nameAscending)
    }
}

// MARK: - The view model's use of the preference domain

/// The sort order the view model persists must land in the domain it was given, and nowhere else.
///
/// The second assertion is the one that matters. Two suites used to read and clear the sort key in
/// `UserDefaults.standard` — and because Xcode runs test classes in parallel *processes*, one of them
/// deleted the key the other had just written, so a sort test failed at random. Asserting on
/// `.standard` is what stops that write being moved back.
@MainActor
final class VaultBrowserViewModelSortPreferenceDomainTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var vault: MockVaultRepository!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "VaultBrowserViewModelSortPreferenceDomainTests-\(UUID().uuidString)"
        defaults  = UserDefaults(suiteName: suiteName)
        vault     = MockVaultRepository()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        vault = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeViewModel() -> VaultBrowserViewModel {
        VaultBrowserViewModel(
            vault:           vault,
            search:          SearchVaultUseCaseImpl(vault: vault),
            delete:          HoldableDeleteUseCase(),
            permanentDelete: StubSortPermanentDeleteUseCase(),
            restore:         StubSortRestoreUseCase(),
            duplicate:       NoopDuplicateUseCase(),
            emptyTrash:      StubEmptyTrashUseCase(),
            sync:            MockSyncUseCase(),
            createFolder:     StubSortCreateFolder(),
            renameFolder:     StubSortRenameFolder(),
            deleteFolder:     StubSortDeleteFolder(),
            moveItem:         StubSortMoveItem(),
            createCollection: StubSortCreateCollection(),
            renameCollection: StubSortRenameCollection(),
            deleteCollection: StubSortDeleteCollection(),
            syncTimestamp:    MockSyncTimestampRepository(storedDate: nil),
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: MockSyncTimestampRepository(storedDate: nil)),
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        { _, _ in nil },
            filePicker:       { nil },
            userDefaults:     defaults
        )
    }

    func testSortOrder_isPersistedInTheInjectedDomain() {
        let sut = makeViewModel()

        sut.sortOrder = .nameDescending

        XCTAssertEqual(ItemSortPreference.load(from: defaults), .nameDescending)
    }

    func testSortOrder_doesNotTouchTheSharedDomain() {
        let before = UserDefaults.standard.string(forKey: ItemSortPreference.key)
        let sut = makeViewModel()

        sut.sortOrder = .modifiedNewestFirst

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: ItemSortPreference.key), before,
            "a test must not write the application's preference domain"
        )
    }

    func testSortOrder_isReadFromTheInjectedDomainOnInit() {
        ItemSortPreference.save(.createdOldestFirst, to: defaults)

        let sut = makeViewModel()

        XCTAssertEqual(sut.sortOrder, .createdOldestFirst)
    }
}

private final class StubSortPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
private final class StubSortRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
private struct StubSortCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
private struct StubSortRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
private struct StubSortDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
private struct StubSortMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
private struct StubSortCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
private struct StubSortRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
private struct StubSortDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
