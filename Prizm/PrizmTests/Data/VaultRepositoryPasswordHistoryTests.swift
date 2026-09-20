import XCTest
@testable import Prizm

// MARK: - VaultRepositoryPasswordHistoryTests

/// Tests for the real decryption of `passwordHistory` in `VaultRepositoryImpl`.
///
/// **These belong here, not against a mock.** `MockVaultRepository` holds no key material, so it
/// returns whatever entries a test hands it and can prove nothing about which key was used. The two
/// properties worth proving — the per-item key resolution, and that a damaged entry does not hide
/// the healthy ones — only exist in the real implementation.
///
/// Distinguishable key material throughout: if the wrong key is selected the MAC check fails loudly
/// instead of succeeding with bytes that happen to look plausible.
@MainActor
final class VaultRepositoryPasswordHistoryTests: XCTestCase {

    private var sut: VaultRepositoryImpl!
    private var mockAPI: MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!

    private let vaultKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0xAA, count: 32),
        macKey:        Data(repeating: 0xBB, count: 32)
    )
    private let itemKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0x11, count: 32),
        macKey:        Data(repeating: 0x22, count: 32)
    )
    /// Deliberately unrelated to both: used to prove an entry encrypted for someone else is skipped
    /// rather than silently decrypted into garbage.
    private let foreignKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0x77, count: 32),
        macKey:        Data(repeating: 0x88, count: 32)
    )

    override func setUp() async throws {
        try await super.setUp()
        mockAPI    = MockPrizmAPIClient()
        mockCrypto = MockPrizmCryptoService()
        mockCrypto.stubbedVaultKeys = vaultKeys
        await mockCrypto.unlockWith(keys: vaultKeys)
        sut = VaultRepositoryImpl(apiClient: mockAPI, crypto: mockCrypto, orgKeyCache: OrgKeyCache())
    }

    // MARK: - Helpers

    private func encrypt(_ plaintext: String, keys: CryptoKeys) throws -> String {
        try EncString.encrypt(data: Data(plaintext.utf8), keys: keys).toString()
    }

    private func entry(_ password: String,
                       keys: CryptoKeys,
                       lastUsedDate: String? = nil) throws -> JSONValue {
        var fields: [String: JSONValue] = ["password": .string(try encrypt(password, keys: keys))]
        if let lastUsedDate { fields["lastUsedDate"] = .string(lastUsedDate) }
        return .object(fields)
    }

    private func makeItem(id: String = "item-1",
                          history: [JSONValue],
                          cipherKey: String? = nil) -> VaultItem {
        VaultItem(
            id: id, name: "GitHub", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .login(LoginContent(
                username: "octocat", password: "hunter2", uris: [],
                totp: nil, notes: nil, customFields: []
            )),
            organizationId: nil,
            collectionIds: [],
            preserved: PreservedCipherFields(passwordHistory: history, cipherKey: cipherKey)
        )
    }

    private func populate(_ item: VaultItem) async {
        await sut.populate(items: [item], folders: [], organizations: [],
                           collections: [], syncedAt: .now)
    }

    /// The 64-byte per-item key, wrapped for the vault key — the form `cipherKey` arrives in.
    private func wrappedItemKey() throws -> String {
        try EncString.encrypt(data: itemKeys.encryptionKey + itemKeys.macKey,
                              keys: vaultKeys).toString()
    }

    // MARK: - Decryption

    func test_passwordHistory_decryptsEveryEntryInOrder() async throws {
        let item = try makeItem(history: [
            entry("newer-old-password", keys: vaultKeys),
            entry("oldest-password",   keys: vaultKeys)
        ])
        await populate(item)

        let result = try await sut.passwordHistory(for: item.id)

        XCTAssertEqual(result.map(\.password), ["newer-old-password", "oldest-password"])
    }

    /// Both date forms the server actually emits, and an unparseable one that must not cost the
    /// password — the date is display metadata, the password is the payload.
    func test_passwordHistory_lastUsedDate_isParsedWhenPossible() async throws {
        let item = try makeItem(history: [
            entry("a", keys: vaultKeys, lastUsedDate: "2026-01-02T03:04:05.678Z"),
            entry("b", keys: vaultKeys, lastUsedDate: "2025-01-02T03:04:05Z"),
            entry("c", keys: vaultKeys, lastUsedDate: "not a date")
        ])
        await populate(item)

        let result = try await sut.passwordHistory(for: item.id)

        XCTAssertEqual(result.count, 3)
        XCTAssertNotNil(result[0].lastUsedDate)
        XCTAssertNotNil(result[1].lastUsedDate)
        XCTAssertNil(result[2].lastUsedDate)
        XCTAssertEqual(result[2].password, "c")
    }

    /// One damaged entry must not hide the rest. Refusing the whole list would hide data the user
    /// owns because of a single bad row.
    func test_passwordHistory_malformedEntriesAreSkipped() async throws {
        let item = try makeItem(history: [
            .string("not an object at all"),
            .object(["lastUsedDate": .string("2026-01-01T00:00:00Z")]),   // no password
            .object(["password": .string("")]),                            // empty password
            try entry("survivor", keys: vaultKeys)
        ])
        await populate(item)

        let result = try await sut.passwordHistory(for: item.id)

        XCTAssertEqual(result.map(\.password), ["survivor"])
    }

    /// Encrypted for a different key. The MAC check fails, and the entry is dropped rather than
    /// surfacing whatever the wrong key produced.
    func test_passwordHistory_undecryptableEntryIsSkipped() async throws {
        let item = try makeItem(history: [
            try entry("someone-elses", keys: foreignKeys),
            try entry("mine",          keys: vaultKeys)
        ])
        await populate(item)

        let result = try await sut.passwordHistory(for: item.id)

        XCTAssertEqual(result.map(\.password), ["mine"])
    }

    // MARK: - Key resolution

    /// No `cipherKey`: the vault key decrypts it.
    func test_passwordHistory_withoutCipherKey_usesTheVaultKey() async throws {
        let item = try makeItem(history: [entry("vault-key-secret", keys: vaultKeys)])
        await populate(item)

        let result = try await sut.passwordHistory(for: item.id)

        XCTAssertEqual(result.map(\.password), ["vault-key-secret"])
    }

    /// With a `cipherKey`, the entry is encrypted under the *item's* key. Decrypting it with the
    /// vault key fails, so a successful round trip is what proves the wrapped key was unwrapped and
    /// used — the same resolution `CipherMapper` performs for the current password.
    func test_passwordHistory_withCipherKey_usesTheItemKey() async throws {
        let item = try makeItem(
            history: [entry("item-key-secret", keys: itemKeys)],
            cipherKey: try wrappedItemKey()
        )
        await populate(item)

        let result = try await sut.passwordHistory(for: item.id)

        XCTAssertEqual(result.map(\.password), ["item-key-secret"])
    }

    // MARK: - Absence

    func test_passwordHistory_emptyHistory_returnsEmpty() async throws {
        let item = makeItem(history: [])
        await populate(item)

        let result = try await sut.passwordHistory(for: item.id)

        XCTAssertTrue(result.isEmpty)
    }

    func test_passwordHistory_unknownItem_throws() async throws {
        do {
            _ = try await sut.passwordHistory(for: "no-such-item")
            XCTFail("Expected itemNotFound")
        } catch VaultError.itemNotFound(let id) {
            XCTAssertEqual(id, "no-such-item")
        }
    }
}
