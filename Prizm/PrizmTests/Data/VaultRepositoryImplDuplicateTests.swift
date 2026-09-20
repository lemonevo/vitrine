import XCTest
@testable import Prizm

/// Tests for `VaultRepositoryImpl.duplicate(id:)`.
///
/// The draft-level exclusions are covered by `DuplicateVaultItemTests`; what is verified here is
/// that the repository routes the duplicate through the ordinary `create` path — so a copy is
/// encrypted, org-key resolved and indexed exactly like any other new item, rather than being a
/// second, less-tested write path.
@MainActor
final class VaultRepositoryImplDuplicateTests: XCTestCase {

    private var sut: VaultRepositoryImpl!
    private var mockAPI: MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI    = MockPrizmAPIClient()
        mockCrypto = MockPrizmCryptoService()
        sut        = VaultRepositoryImpl(apiClient: mockAPI, crypto: mockCrypto)
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(repeating: 0xDE, count: 32),
            macKey:        Data(repeating: 0xAD, count: 32)
        ))
    }

    private func makeLogin(id: String = "item-1",
                           name: String = "GitHub",
                           isFavorite: Bool = false) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: isFavorite, isDeleted: false,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
            content: .login(LoginContent(
                username: "octocat", password: "hunter2",
                uris: [LoginURI(uri: "https://github.com", matchType: nil)],
                totp: nil, notes: nil,
                customFields: [CustomField(name: "env", value: "prod", type: .text, linkedId: nil)]
            ))
        )
    }

    private func populate(_ items: [VaultItem]) async {
        await sut.populate(items: items, folders: [], organizations: [], collections: [], syncedAt: .now)
    }

    // MARK: - Happy path

    func test_duplicate_returnsANewItemAndIndexesIt() async throws {
        await populate([makeLogin()])

        let copy = try await sut.duplicate(id: "item-1")

        XCTAssertNotEqual(copy.id, "item-1")
        XCTAssertFalse(copy.isFavorite)
        XCTAssertNotEqual(copy.name, "GitHub")

        let counts = try await sut.itemCounts()
        XCTAssertEqual(counts[.allItems], 2, "the copy must be indexed alongside the original")
    }

    func test_duplicate_leavesTheOriginalInPlace() async throws {
        await populate([makeLogin(id: "item-1", name: "GitHub", isFavorite: true)])

        _ = try await sut.duplicate(id: "item-1")

        let original = try await sut.itemDetail(id: "item-1")
        XCTAssertEqual(original.name, "GitHub")
        XCTAssertTrue(original.isFavorite)
    }

    func test_duplicate_copyIsSearchableByItsOwnName() async throws {
        await populate([makeLogin()])

        let copy = try await sut.duplicate(id: "item-1")

        let results = try await sut.searchItems(query: copy.name, in: .allItems)
        XCTAssertTrue(results.contains { $0.id == copy.id })
    }

    // MARK: - Missing source

    func test_duplicate_unknownId_throwsItemNotFound() async {
        await populate([])

        await XCTAssertThrowsErrorAsync(try await sut.duplicate(id: "missing")) { error in
            guard case VaultError.itemNotFound(let id) = error else {
                return XCTFail("Expected .itemNotFound, got \(error)")
            }
            XCTAssertEqual(id, "missing")
        }
    }

    /// A duplicate of a trashed item is still a live item: the source's `isDeleted` must not be
    /// carried over, or the copy would be created straight into Trash.
    func test_duplicate_ofATrashedItem_createsALiveCopy() async throws {
        var trashed = makeLogin(id: "item-1")
        trashed = trashed.with(isDeleted: true)
        await populate([trashed])

        let copy = try await sut.duplicate(id: "item-1")

        XCTAssertFalse(copy.isDeleted)
        let all = try await sut.items(for: .allItems)
        XCTAssertTrue(all.contains { $0.id == copy.id })
    }
}
