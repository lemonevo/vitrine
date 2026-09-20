import XCTest
@testable import Prizm

/// Tests for `EmptyTrashUseCaseImpl`.
///
/// The point of this use case is that it does **not** throw. Emptying Trash is a sequence of
/// independent per-item requests, so a partial outcome is a real outcome and the user needs the
/// counts rather than a single error that hides how much was actually removed.
@MainActor
final class EmptyTrashUseCaseTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut: EmptyTrashUseCaseImpl!

    private func trashed(_ id: String, name: String = "Trashed") -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: true,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
    }

    private func active(_ id: String) -> VaultItem {
        VaultItem(
            id: id, name: "Active", isFavorite: false, isDeleted: false,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
    }

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        sut = EmptyTrashUseCaseImpl(repository: vault)
    }

    override func tearDown() async throws {
        vault = nil
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Happy path

    func test_execute_deletesEveryTrashedItem() async {
        await vault.populate(items: [trashed("1"), trashed("2"), trashed("3"), active("4")],
                             folders: [], organizations: [], collections: [], syncedAt: .now)

        let result = await sut.execute()

        XCTAssertEqual(result.deletedCount, 3)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertNil(result.errorMessage)
        XCTAssertFalse(result.hadFailures)
        XCTAssertEqual(Set(vault.permanentDeletedIds), Set(["1", "2", "3"]))
    }

    /// Emptying Trash must never touch an item that is not in Trash. The use case lists `.trash`
    /// rather than `.allItems` precisely so this cannot happen.
    func test_execute_leavesActiveItemsAlone() async {
        await vault.populate(items: [trashed("1"), active("2")],
                             folders: [], organizations: [], collections: [], syncedAt: .now)

        _ = await sut.execute()

        XCTAssertEqual(vault.populatedItems.map(\.id), ["2"])
        XCTAssertFalse(vault.permanentDeletedIds.contains("2"))
    }

    func test_execute_emptyTrash_isANoOp() async {
        await vault.populate(items: [active("1")], folders: [], organizations: [], collections: [], syncedAt: .now)

        let result = await sut.execute()

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.deletedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(vault.permanentDeleteCallCount, 0, "nothing to delete means no requests")
    }

    // MARK: - Partial failure

    /// The case that justifies returning a result instead of throwing: one item fails, the rest must
    /// still be removed, and the counts must say so.
    func test_execute_partialFailure_reportsCountsAndKeepsGoing() async {
        await vault.populate(items: [trashed("1"), trashed("2"), trashed("3"), trashed("4")],
                             folders: [], organizations: [], collections: [], syncedAt: .now)
        vault.permanentDeleteErrorIds = ["2"]

        let result = await sut.execute()

        XCTAssertEqual(result.deletedCount, 3)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(result.hadFailures)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(vault.permanentDeleteCallCount, 4, "a failure must not stop the loop")
        XCTAssertEqual(Set(vault.permanentDeletedIds), Set(["1", "3", "4"]))
        XCTAssertTrue(vault.populatedItems.contains { $0.id == "2" }, "the failed item stays in Trash")
    }

    func test_execute_everyDeleteFails_reportsZeroDeleted() async {
        await vault.populate(items: [trashed("1"), trashed("2")],
                             folders: [], organizations: [], collections: [], syncedAt: .now)
        vault.permanentDeleteErrorIds = ["1", "2"]

        let result = await sut.execute()

        XCTAssertEqual(result.deletedCount, 0)
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertTrue(result.hadFailures)
        XCTAssertFalse(result.isEmpty, "a total failure is not the same as nothing to do")
    }

    // MARK: - Listing failure

    /// Failing to list Trash is not a partial delete — nothing was attempted. Reporting
    /// `failedCount: 0` keeps the two cases distinguishable.
    func test_execute_listingFails_reportsTheErrorWithoutDeleting() async {
        await vault.populate(items: [trashed("1")], folders: [], organizations: [], collections: [], syncedAt: .now)
        vault.stubbedItemsError = VaultError.itemNotFound("trash")

        let result = await sut.execute()

        XCTAssertEqual(result.deletedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertFalse(result.hadFailures)
        XCTAssertEqual(vault.permanentDeleteCallCount, 0)
    }

    // MARK: - EmptyTrashResult

    func test_result_noneIsEmpty() {
        XCTAssertTrue(EmptyTrashResult.none.isEmpty)
        XCTAssertFalse(EmptyTrashResult.none.hadFailures)
        XCTAssertNil(EmptyTrashResult.none.errorMessage)
    }

    func test_result_isEmptyOnlyWhenNothingHappenedAtAll() {
        XCTAssertFalse(EmptyTrashResult(deletedCount: 2, failedCount: 0, errorMessage: nil).isEmpty)
        XCTAssertFalse(EmptyTrashResult(deletedCount: 0, failedCount: 1, errorMessage: "x").isEmpty)
    }
}
