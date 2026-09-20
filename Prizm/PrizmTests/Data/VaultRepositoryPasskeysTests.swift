import XCTest
@testable import Prizm

// MARK: - VaultRepositoryPasskeysTests

/// Tests for the real decryption of `fido2Credentials` in `VaultRepositoryImpl`.
///
/// Against the real implementation rather than a mock, for the same reason as the password-history
/// suite: `MockVaultRepository` has no key material, so it hands back whatever it was given and can
/// prove nothing about which key was used.
///
/// **The case that carries the most weight is `test_keyValueIsNeverDecrypted`.** `keyValue` is the
/// credential's *private* key. Nothing in a read-only listing needs it, and the spec forbids
/// decrypting it — but "we did not decrypt it" is not something a passing test normally shows, since
/// a value that was never asked for leaves no trace. That test makes it observable by putting a
/// `keyValue` that **cannot** be decrypted in the fixture: if the implementation ever touched it,
/// the credential would be dropped or the call would fail, and it is neither.
@MainActor
final class VaultRepositoryPasskeysTests: XCTestCase {

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
    /// Unrelated to both, so an entry encrypted for someone else fails the MAC check loudly.
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

    /// Builds one credential as the server sends it: every field an EncString except the date.
    private func credential(rpId: String,
                            keys: CryptoKeys,
                            rpName: String? = nil,
                            userName: String? = nil,
                            userDisplayName: String? = nil,
                            creationDate: String? = nil,
                            dateKey: String = "creationDate",
                            keyValue: String? = nil) throws -> JSONValue {
        var fields: [String: JSONValue] = ["rpId": .string(try encrypt(rpId, keys: keys))]
        if let rpName          { fields["rpName"]          = .string(try encrypt(rpName, keys: keys)) }
        if let userName        { fields["userName"]        = .string(try encrypt(userName, keys: keys)) }
        if let userDisplayName { fields["userDisplayName"] = .string(try encrypt(userDisplayName, keys: keys)) }
        if let creationDate    { fields[dateKey]           = .string(creationDate) }
        if let keyValue        { fields["keyValue"]        = .string(keyValue) }
        return .object(fields)
    }

    private func makeItem(id: String = "item-1",
                          credentials: [JSONValue],
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
            preserved: PreservedCipherFields(cipherKey: cipherKey,
                                             fido2Credentials: credentials)
        )
    }

    private func populate(_ item: VaultItem) async {
        await sut.populate(items: [item], folders: [], organizations: [],
                           collections: [], syncedAt: .now)
    }

    private func wrappedItemKey() throws -> String {
        try EncString.encrypt(data: itemKeys.encryptionKey + itemKeys.macKey,
                              keys: vaultKeys).toString()
    }

    // MARK: - Decryption

    func test_passkeys_decryptsTheDisplayFields() async throws {
        let item = try makeItem(credentials: [
            credential(rpId: "example.com", keys: vaultKeys,
                       rpName: "Example", userName: "alice@example.com",
                       userDisplayName: "Alice",
                       creationDate: "2026-01-15T10:30:00Z")
        ])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].rpId, "example.com")
        XCTAssertEqual(result[0].rpName, "Example")
        XCTAssertEqual(result[0].userName, "alice@example.com")
        XCTAssertEqual(result[0].userDisplayName, "Alice")
        XCTAssertNotNil(result[0].creationDate)
    }

    /// Both spellings of the date. Bitwarden's own models disagree — the API type reads
    /// `CreationDate`, the wire carries `creationDate` — and their lookup is case-insensitive so
    /// they never noticed. A direct dictionary lookup does.
    func test_passkeys_creationDate_acceptsBothSpellings() async throws {
        let item = try makeItem(credentials: [
            credential(rpId: "a.example", keys: vaultKeys,
                       creationDate: "2026-01-15T10:30:00Z", dateKey: "creationDate"),
            credential(rpId: "b.example", keys: vaultKeys,
                       creationDate: "2026-02-15T10:30:00Z", dateKey: "CreationDate")
        ])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.map(\.rpId), ["a.example", "b.example"])
        XCTAssertNotNil(result[0].creationDate)
        XCTAssertNotNil(result[1].creationDate)
    }

    /// An absent optional field is omitted rather than rendered as empty — the spec's scenario, and
    /// the reason these are optionals on the type rather than empty strings.
    func test_passkeys_withoutAUserName_isStillListed() async throws {
        let item = try makeItem(credentials: [
            credential(rpId: "example.com", keys: vaultKeys, userName: nil)
        ])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].userName)
    }

    // MARK: - The private key

    /// `keyValue` is undecryptable here **on purpose**. If the implementation ever passed it to the
    /// decryption routine, this credential would be dropped or the call would throw; it is listed
    /// with its other fields intact, which is the observable form of "never read".
    func test_keyValueIsNeverDecrypted() async throws {
        let item = try makeItem(credentials: [
            credential(rpId: "example.com", keys: vaultKeys, userName: "alice",
                       keyValue: "not an EncString at all")
        ])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].rpId, "example.com")
        XCTAssertEqual(result[0].userName, "alice")
    }

    // MARK: - Skipping

    func test_passkeys_malformedEntriesAreSkipped() async throws {
        let item = try makeItem(credentials: [
            .string("not an object"),
            .object(["userName": .string("no rpId here")]),
            .object(["rpId": .string("")]),
            try credential(rpId: "survivor.example", keys: vaultKeys)
        ])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.map(\.rpId), ["survivor.example"])
    }

    func test_passkeys_undecryptableCredentialIsSkipped() async throws {
        let item = try makeItem(credentials: [
            try credential(rpId: "someone-elses.example", keys: foreignKeys),
            try credential(rpId: "mine.example",          keys: vaultKeys)
        ])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.map(\.rpId), ["mine.example"])
    }

    // MARK: - Key resolution

    func test_passkeys_withoutCipherKey_usesTheVaultKey() async throws {
        let item = try makeItem(credentials: [
            credential(rpId: "vault-key.example", keys: vaultKeys)
        ])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.map(\.rpId), ["vault-key.example"])
    }

    /// With a `cipherKey` the fields are encrypted under the item's own key, so a successful round
    /// trip is what proves the wrapped key was unwrapped and used.
    func test_passkeys_withCipherKey_usesTheItemKey() async throws {
        let item = try makeItem(
            credentials: [credential(rpId: "item-key.example", keys: itemKeys)],
            cipherKey: try wrappedItemKey()
        )
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertEqual(result.map(\.rpId), ["item-key.example"])
    }

    // MARK: - Absence

    func test_passkeys_empty_returnsEmpty() async throws {
        let item = makeItem(credentials: [])
        await populate(item)

        let result = try await sut.passkeys(for: item.id)

        XCTAssertTrue(result.isEmpty)
    }

    func test_passkeys_unknownItem_throws() async throws {
        do {
            _ = try await sut.passkeys(for: "no-such-item")
            XCTFail("Expected itemNotFound")
        } catch VaultError.itemNotFound(let id) {
            XCTAssertEqual(id, "no-such-item")
        }
    }
}
