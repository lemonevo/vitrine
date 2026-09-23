import XCTest
@testable import Prizm

// MARK: - VaultRepositoryPasskeysSelectionTests

/// The `.passkeys` sidebar selection: which items it lists, what it counts, and what it does *not*
/// have to do to know either.
///
/// Against the real `VaultRepositoryImpl` rather than the mock, because the thing under test is
/// `buildIndexes()` — the pre-computed per-selection lists — and a double that filters `populatedItems`
/// inline would pass against a broken index.
///
/// **The property the whole destination rests on:** whether an item carries a passkey is answered from
/// the credential list the item already holds *still encrypted*. If any of these tests needed a key,
/// they would be testing the wrong thing — the listing would have stopped being cheap, and
/// `passkey-viewer`'s "nothing is decrypted until it is displayed" would have quietly become "until
/// the sidebar is drawn".
@MainActor
final class VaultRepositoryPasskeysSelectionTests: XCTestCase {

    private var sut: VaultRepositoryImpl!

    private let vaultKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0xAA, count: 32),
        macKey:        Data(repeating: 0xBB, count: 32)
    )
    /// A key this repository was never given. Fields encrypted with it cannot be read here, which is
    /// the point: an unreadable credential is still a credential the item has.
    private let unreadableKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0x77, count: 32),
        macKey:        Data(repeating: 0x88, count: 32)
    )

    override func setUp() async throws {
        try await super.setUp()
        let crypto = MockPrizmCryptoService()
        crypto.stubbedVaultKeys = vaultKeys
        await crypto.unlockWith(keys: vaultKeys)
        sut = VaultRepositoryImpl(apiClient: MockPrizmAPIClient(),
                                  crypto:    crypto,
                                  orgKeyCache: OrgKeyCache())
    }

    // MARK: - Fixtures

    private func login(id: String,
                       name: String,
                       credentials: Int = 0,
                       deleted: Bool = false) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: deleted,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: "\(id)@example.com", password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: [])),
            organizationId: nil,
            collectionIds: [],
            // Opaque strings rather than well-formed EncStrings: the index must not look inside them.
            preserved: PreservedCipherFields(
                fido2Credentials: (0..<credentials).map { .object(["rpId": .string("opaque-\($0)")]) }
            )
        )
    }

    private func populate(_ items: VaultItem...) async {
        await sut.populate(items: items, folders: [], organizations: [],
                           collections: [], syncedAt: .now)
    }

    private func passkeyItems() async throws -> [VaultItem] {
        try await sut.items(for: .passkeys)
    }

    /// Hoisted because `XCTAssertEqual(try await …)` puts an `async` call inside an autoclosure that
    /// does not support concurrency — the assertion macro, not the code under test, is what forbids it.
    private func passkeyCount() async throws -> Int {
        try await sut.itemCounts()[.passkeys] ?? 0
    }

    // MARK: - Which items are listed

    func test_onlyItemsCarryingCredentialsAreListed() async throws {
        await populate(login(id: "with-one",   name: "GitHub",  credentials: 1),
                       login(id: "with-three", name: "Acme",    credentials: 3),
                       login(id: "none",       name: "Netflix"))

        let listed = try await passkeyItems().map(\.id)

        XCTAssertEqual(Set(listed), ["with-one", "with-three"])
    }

    func test_aTrashedItemIsNeitherListedNorCounted() async throws {
        await populate(login(id: "kept",    name: "GitHub", credentials: 1),
                       login(id: "trashed", name: "Old",    credentials: 2, deleted: true))

        let listed = try await passkeyItems().map(\.id)

        XCTAssertEqual(listed, ["kept"],
                       "Trash is excluded from every other category; a destination that showed its "
                     + "contents would be a way to reach deleted credentials")
        let counts = try await sut.itemCounts()
        XCTAssertEqual(counts[.passkeys], 1)
    }

    func test_anEmptyVaultYieldsAnEmptyListRatherThanAnError() async throws {
        await populate(login(id: "none", name: "Netflix"))

        let listed = try await passkeyItems()
        let count  = try await passkeyCount()

        XCTAssertTrue(listed.isEmpty)
        XCTAssertEqual(count, 0)
    }

    // MARK: - Existence without decryption

    /// The index must not open a credential to decide whether an item has one.
    ///
    /// Made observable by encrypting the fields with a key this repository does not hold: if the
    /// listing depended on reading them, these items would disappear from it.
    func test_itemsWithUnreadableCredentialsAreStillListed() async throws {
        let unreadable = VaultItem(
            id: "unreadable", name: "Vault of Unreadable", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: nil, password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: [])),
            preserved: PreservedCipherFields(fido2Credentials: [
                .object(["rpId": .string(try EncString.encrypt(data: Data("github.com".utf8),
                                                               keys: unreadableKeys).toString())])
            ])
        )
        await populate(unreadable)

        let listed = try await passkeyItems()

        XCTAssertEqual(listed.map(\.id), ["unreadable"])
        XCTAssertEqual(listed.first?.passkeyCount, 1)
        // And reading it really does fail, so the assertion above is not passing because the field
        // happened to be readable after all.
        let credentials = try await sut.passkeys(for: "unreadable")
        XCTAssertTrue(credentials.isEmpty,
                      "the fixture stopped being unreadable and no longer proves anything")
    }

    /// A credential entry the server did not send as an object is still evidence that the item has a
    /// passkey. Dropping it from the listing would hide the item, which is the opposite of what a
    /// screen whose purpose is "what do I have" is for.
    func test_aMalformedEntryStillCountsAsAPasskey() async throws {
        let malformed = VaultItem(
            id: "malformed", name: "Odd Shape", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: nil, password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: [])),
            preserved: PreservedCipherFields(fido2Credentials: [.string("not an object")])
        )
        await populate(malformed)

        let listed = try await passkeyItems().map(\.id)
        let count  = try await passkeyCount()

        XCTAssertEqual(listed, ["malformed"])
        XCTAssertEqual(count, 1)
    }

    // MARK: - The selection behaves like the others

    func test_searchStaysInsideThePasskeysScope() async throws {
        await populate(login(id: "gh",  name: "GitHub",  credentials: 1),
                       login(id: "gh2", name: "GitHub Enterprise", credentials: 1),
                       login(id: "gl",  name: "GitLab"))

        let found = try await sut.searchItems(query: "GitHub", in: .passkeys)

        XCTAssertEqual(Set(found.map(\.id)), ["gh", "gh2"],
                       "a query on this destination filters its own rows, not the whole vault")
    }

    /// The listing follows a write without waiting for a sync, which is what
    /// `vault-actor-isolation`'s "indexes rebuild after every write mutation" exists to guarantee — and
    /// what makes a destination like this one say something untrue about the vault if it were broken.
    func test_trashingAnItemRemovesItFromTheListingWithoutAnotherSync() async throws {
        await populate(login(id: "gh", name: "GitHub", credentials: 1),
                       login(id: "nf", name: "Netflix"))
        let before = try await passkeyItems().map(\.id)
        XCTAssertEqual(before, ["gh"])

        try await sut.deleteItem(id: "gh")

        let listed = try await passkeyItems()
        let count  = try await passkeyCount()

        XCTAssertTrue(listed.isEmpty,
                      "the index was not rebuilt, so the listing still shows an item the user just moved")
        XCTAssertEqual(count, 0)
    }
}
