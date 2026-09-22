import XCTest
@testable import Prizm

/// Tests for the write-path guarantee added by `critical-integrity-fixes`:
/// **saving an item must not delete wire fields Prizm does not interpret.**
///
/// `PUT /api/ciphers/{id}` replaces the whole cipher. Vaultwarden's `update_cipher_from_data`
/// assigns `key`, `password_history` and `archived_date` unconditionally and stores the `login`
/// object verbatim, so a field missing from the request body is erased server-side. Before this
/// change, editing an item's notes — or merely toggling its favourite — destroyed the passkey,
/// the password history, the per-item key and the archived flag (FEATURE-GAP-ANALYSIS.md §2.2/2.3).
@MainActor
final class CipherWireIntegrityTests: XCTestCase {

    private var sut: CipherMapper!
    private var vaultKeys: CryptoKeys!
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A 64-byte per-item key: AES-256 encryption key ‖ HMAC-SHA256 MAC key.
    private var perItemKeys: CryptoKeys {
        CryptoKeys(
            encryptionKey: Data(repeating: 0x11, count: 32),
            macKey:        Data(repeating: 0x22, count: 32)
        )
    }

    override func setUp() async throws {
        try await super.setUp()
        sut = CipherMapper()
        vaultKeys = CryptoKeys(
            encryptionKey: Data(repeating: 0xDE, count: 32),
            macKey:        Data(repeating: 0xAD, count: 32)
        )
    }

    // MARK: - Helpers

    private func makeLoginItem(preserved: PreservedCipherFields,
                               name: String = "Example Login") -> VaultItem {
        VaultItem(
            id: "cipher-1",
            name: name,
            isFavorite: false,
            isDeleted: false,
            creationDate: baseDate,
            revisionDate: baseDate,
            content: .login(LoginContent(
                username: "alice@example.com",
                password: "hunter2",
                uris: [LoginURI(uri: "https://example.com", matchType: .defaultMatch)],
                totp: nil,
                notes: "notes",
                customFields: []
            )),
            preserved: preserved
        )
    }

    /// A representative `PreservedCipherFields` with every member populated.
    private func makePreserved(cipherKey: String? = nil) -> PreservedCipherFields {
        PreservedCipherFields(
            passwordHistory: [
                .object([
                    "password":     .string("2.old|password|mac"),
                    "lastUsedDate": .string("2024-01-01T00:00:00.000Z")
                ])
            ],
            archivedDate: "2025-05-05T10:00:00.000Z",
            cipherKey: cipherKey,
            fido2Credentials: [
                .object([
                    "credentialId": .string("cred-abc"),
                    "keyValue":     .string("2.passkey|material|mac"),
                    "counter":      .string("0"),
                    "discoverable": .bool(true)
                ])
            ],
            passwordRevisionDate: "2024-02-02T00:00:00.000Z",
            autofillOnPageLoad: true
        )
    }

    private func jsonObject(of raw: RawCipher) throws -> [String: Any] {
        let data = try JSONEncoder().encode(raw)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Decoding the wire format

    func test_rawCipherDecodesUnmodelledFields() throws {
        let json = """
        {
          "id": "cipher-1",
          "type": 1,
          "name": "2.name|ct|mac",
          "favorite": false,
          "passwordHistory": [
            { "password": "2.old|ct|mac", "lastUsedDate": "2024-01-01T00:00:00.000Z" }
          ],
          "archivedDate": "2025-05-05T10:00:00.000Z",
          "key": "2.item|key|mac",
          "login": {
            "username": "2.user|ct|mac",
            "passwordRevisionDate": "2024-02-02T00:00:00.000Z",
            "autofillOnPageLoad": true,
            "fido2Credentials": [
              { "credentialId": "cred-abc", "counter": "0", "discoverable": true }
            ]
          }
        }
        """.data(using: .utf8)!

        let raw = try JSONDecoder().decode(RawCipher.self, from: json)

        XCTAssertEqual(raw.passwordHistory?.count, 1)
        XCTAssertEqual(raw.archivedDate, "2025-05-05T10:00:00.000Z")
        XCTAssertEqual(raw.key, "2.item|key|mac")
        XCTAssertEqual(raw.login?.passwordRevisionDate, "2024-02-02T00:00:00.000Z")
        XCTAssertEqual(raw.login?.autofillOnPageLoad, true)
        XCTAssertEqual(raw.login?.fido2Credentials?.count, 1)
    }

    func test_rawCipherReEncodesUnmodelledFieldsUnchanged() throws {
        let json = """
        {
          "id": "cipher-1",
          "type": 1,
          "name": "2.name|ct|mac",
          "favorite": false,
          "passwordHistory": [
            { "password": "2.old|ct|mac", "lastUsedDate": "2024-01-01T00:00:00.000Z" }
          ],
          "archivedDate": "2025-05-05T10:00:00.000Z",
          "login": {
            "fido2Credentials": [
              { "credentialId": "cred-abc", "counter": "0", "discoverable": true }
            ]
          }
        }
        """.data(using: .utf8)!

        let raw    = try JSONDecoder().decode(RawCipher.self, from: json)
        let object = try jsonObject(of: raw)

        // A synthesised `encode(to:)` would silently omit these if the properties were ever
        // removed from the type, so assert on the serialised form, not just the struct.
        XCTAssertNotNil(object["passwordHistory"])
        XCTAssertEqual(object["archivedDate"] as? String, "2025-05-05T10:00:00.000Z")

        let login = try XCTUnwrap(object["login"] as? [String: Any])
        let credentials = try XCTUnwrap(login["fido2Credentials"] as? [[String: Any]])
        XCTAssertEqual(credentials.first?["credentialId"] as? String, "cred-abc")
        XCTAssertEqual(credentials.first?["discoverable"] as? Bool, true)
    }

    func test_rawCipherWithoutUnmodelledFieldsDecodesToNil() throws {
        let json = """
        { "id": "cipher-1", "type": 1, "name": "2.name|ct|mac", "favorite": false }
        """.data(using: .utf8)!

        let raw = try JSONDecoder().decode(RawCipher.self, from: json)
        XCTAssertNil(raw.passwordHistory)
        XCTAssertNil(raw.archivedDate)
        XCTAssertNil(raw.key)
        XCTAssertNil(raw.login)
    }

    // MARK: - Forward mapping captures them

    func test_mapCapturesUnmodelledFieldsIntoPreserved() throws {
        let json = """
        {
          "id": "cipher-1",
          "type": 1,
          "name": "2.name|ct|mac",
          "favorite": false,
          "passwordHistory": [
            { "password": "2.old|ct|mac", "lastUsedDate": "2024-01-01T00:00:00.000Z" }
          ],
          "archivedDate": "2025-05-05T10:00:00.000Z",
          "key": "2.item|key|mac",
          "login": {
            "passwordRevisionDate": "2024-02-02T00:00:00.000Z",
            "autofillOnPageLoad": false,
            "fido2Credentials": [{ "credentialId": "cred-abc" }]
          }
        }
        """.data(using: .utf8)!
        let raw = try JSONDecoder().decode(RawCipher.self, from: json)

        // The fixture's `name` and `key` are placeholders, not real EncStrings, so rebuild the
        // cipher with a genuinely wrapped per-item key and a name encrypted *with that key* —
        // the shape a cipher that carries its own key actually arrives in.
        let wrappedKey = try EncString.encrypt(data: perItemKeys.toData(), keys: vaultKeys).toString()
        let decryptable = RawCipher(
            id: raw.id, organizationId: nil, folderId: nil, type: raw.type,
            name: try EncString.encrypt(data: Data("Example".utf8), keys: perItemKeys).toString(),
            notes: nil, favorite: false, reprompt: nil, deletedDate: nil,
            creationDate: nil, revisionDate: nil, login: raw.login,
            card: nil, identity: nil, secureNote: nil, sshKey: nil, fields: nil,
            key: wrappedKey, collectionIds: [], attachments: nil,
            passwordHistory: raw.passwordHistory, archivedDate: raw.archivedDate
        )

        let item = try sut.map(raw: decryptable, keys: vaultKeys).item

        XCTAssertEqual(item.name, "Example")
        XCTAssertEqual(item.preserved.archivedDate, "2025-05-05T10:00:00.000Z")
        XCTAssertEqual(item.preserved.cipherKey, wrappedKey)
        XCTAssertEqual(item.preserved.passwordRevisionDate, "2024-02-02T00:00:00.000Z")
        XCTAssertEqual(item.preserved.autofillOnPageLoad, false)
        XCTAssertEqual(item.preserved.passwordHistory.count, 1)
        XCTAssertEqual(item.preserved.fido2Credentials.count, 1)
        XCTAssertFalse(item.preserved.isEmpty)
    }

    func test_mapWithoutUnmodelledFieldsYieldsEmptyPreserved() throws {
        let raw = RawCipher(
            id: "cipher-1", organizationId: nil, folderId: nil, type: 2,
            name: try EncString.encrypt(data: Data("Note".utf8), keys: vaultKeys).toString(),
            notes: nil, favorite: false, reprompt: nil, deletedDate: nil,
            creationDate: nil, revisionDate: nil, login: nil,
            card: nil, identity: nil, secureNote: RawSecureNoteData(type: 0), sshKey: nil,
            fields: nil, key: nil, collectionIds: [], attachments: nil
        )

        let item = try sut.map(raw: raw, keys: vaultKeys).item
        XCTAssertTrue(item.preserved.isEmpty)
    }

    // MARK: - Reverse mapping sends them back

    func test_toRawCipherCarriesEveryPreservedFieldIntoTheRequestBody() throws {
        let item  = makeLoginItem(preserved: makePreserved())
        let draft = DraftVaultItem(item)

        let raw    = try sut.toRawCipher(draft, encryptedWith: vaultKeys)
        let object = try jsonObject(of: raw)

        // Top level.
        XCTAssertEqual(raw.archivedDate, "2025-05-05T10:00:00.000Z")
        XCTAssertEqual(object["archivedDate"] as? String, "2025-05-05T10:00:00.000Z")

        let history = try XCTUnwrap(object["passwordHistory"] as? [[String: Any]])
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?["password"] as? String, "2.old|password|mac")

        // Nested in `login` — Vaultwarden stores this object verbatim.
        let login = try XCTUnwrap(object["login"] as? [String: Any])
        XCTAssertEqual(login["passwordRevisionDate"] as? String, "2024-02-02T00:00:00.000Z")
        XCTAssertEqual(login["autofillOnPageLoad"] as? Bool, true)

        let credentials = try XCTUnwrap(login["fido2Credentials"] as? [[String: Any]])
        XCTAssertEqual(credentials.count, 1)
        XCTAssertEqual(credentials.first?["credentialId"] as? String, "cred-abc")
        XCTAssertEqual(credentials.first?["keyValue"] as? String, "2.passkey|material|mac")
    }

    func test_toRawCipherLeavesEditableFieldsEncryptedWithTheVaultKey() throws {
        // Preservation must not come at the cost of the ordinary encryption path.
        let item  = makeLoginItem(preserved: makePreserved())
        let draft = DraftVaultItem(item)

        let raw = try sut.toRawCipher(draft, encryptedWith: vaultKeys)

        let name = try EncString(string: raw.name).decrypt(keys: vaultKeys)
        XCTAssertEqual(String(data: name, encoding: .utf8), "Example Login")

        let username = try XCTUnwrap(raw.login?.username)
        XCTAssertEqual(
            String(data: try EncString(string: username).decrypt(keys: vaultKeys), encoding: .utf8),
            "alice@example.com"
        )
    }

    func test_toRawCipherForNewItemOmitsUnmodelledFields() throws {
        // A brand-new item has nothing to preserve; it must not invent values.
        let item = VaultItem(
            id: "new-1", name: "Brand New", isFavorite: false, isDeleted: false,
            creationDate: baseDate, revisionDate: baseDate,
            content: .login(LoginContent(username: nil, password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: []))
        )

        let raw = try sut.toRawCipher(DraftVaultItem(item), encryptedWith: vaultKeys)

        XCTAssertNil(raw.key)
        XCTAssertNil(raw.archivedDate)
        XCTAssertEqual(raw.passwordHistory?.isEmpty, true)
        XCTAssertNil(raw.login?.fido2Credentials)
        XCTAssertNil(raw.login?.passwordRevisionDate)
        XCTAssertNil(raw.login?.autofillOnPageLoad)
    }

    func test_draftCarriesPreservedThroughTheEditFlow() {
        // `toggleFavorite` and the edit sheet both build a draft from the item, so the carrier has
        // to survive that conversion or the favourite toggle would still delete the passkey.
        let item = makeLoginItem(preserved: makePreserved())
        let draft = DraftVaultItem(item)
        XCTAssertEqual(draft.preserved, item.preserved)

        var toggled = draft
        toggled.isFavorite.toggle()
        XCTAssertEqual(toggled.preserved, item.preserved)

        XCTAssertEqual(VaultItem(toggled).preserved, item.preserved)
    }

    // MARK: - Per-item cipher key

    func test_toRawCipherEncryptsWithThePerItemKeyAndReturnsIt() throws {
        let wrapped = try EncString.encrypt(data: perItemKeys.toData(), keys: vaultKeys).toString()
        let item    = makeLoginItem(preserved: makePreserved(cipherKey: wrapped))

        let raw = try sut.toRawCipher(DraftVaultItem(item), encryptedWith: vaultKeys)

        // The key travels back unchanged — sending nil here makes the server drop it.
        XCTAssertEqual(raw.key, wrapped)

        // And the fields are encrypted with the per-item key, not the vault key.
        let name = try EncString(string: raw.name).decrypt(keys: perItemKeys)
        XCTAssertEqual(String(data: name, encoding: .utf8), "Example Login")
    }

    func test_toRawCipherWithoutPerItemKeyUsesTheVaultKeyAndSendsNilKey() throws {
        let item = makeLoginItem(preserved: makePreserved(cipherKey: nil))
        let raw  = try sut.toRawCipher(DraftVaultItem(item), encryptedWith: vaultKeys)

        XCTAssertNil(raw.key)
        let name = try EncString(string: raw.name).decrypt(keys: vaultKeys)
        XCTAssertEqual(String(data: name, encoding: .utf8), "Example Login")
    }

    func test_toRawCipherRefusesToWriteWhenThePerItemKeyCannotBeUnwrapped() throws {
        // A key wrapped with *other* keys: re-encrypting with the vault key would produce an item
        // no client can read, so the mapper must throw rather than guess.
        let foreignKeys = CryptoKeys(
            encryptionKey: Data(repeating: 0x33, count: 32),
            macKey:        Data(repeating: 0x44, count: 32)
        )
        let wrapped = try EncString.encrypt(data: perItemKeys.toData(), keys: foreignKeys).toString()
        let item    = makeLoginItem(preserved: makePreserved(cipherKey: wrapped))

        XCTAssertThrowsError(try sut.toRawCipher(DraftVaultItem(item), encryptedWith: vaultKeys)) { error in
            XCTAssertEqual(error as? CipherMapperError, .fieldDecryptionFailed("key"))
        }
    }

    func test_mapDecryptsFieldsWithThePerItemKeyNotTheVaultKey() throws {
        // The read half of the same rule. When a cipher carries its own key, that key protects
        // name, notes and the type-specific payload; the vault key is used only to unwrap it.
        // Decrypting with the vault key instead fails MAC verification, which made every
        // per-item-keyed item unreadable (and un-editable, so the write fix could never help).
        let wrappedKey = try EncString.encrypt(data: perItemKeys.toData(), keys: vaultKeys).toString()
        let raw = RawCipher(
            id: "cipher-1", organizationId: nil, folderId: nil, type: 1,
            name: try EncString.encrypt(data: Data("Example Login".utf8), keys: perItemKeys).toString(),
            notes: nil, favorite: false, reprompt: nil, deletedDate: nil,
            creationDate: nil, revisionDate: nil,
            login: RawLoginData(
                username: try EncString.encrypt(data: Data("alice@example.com".utf8),
                                                keys: perItemKeys).toString(),
                password: try EncString.encrypt(data: Data("hunter2".utf8),
                                                keys: perItemKeys).toString(),
                uris: [], totp: nil
            ),
            card: nil, identity: nil, secureNote: nil, sshKey: nil, fields: nil,
            key: wrappedKey, collectionIds: [], attachments: nil
        )

        let item = try sut.map(raw: raw, keys: vaultKeys).item

        guard case .login(let login) = item.content else {
            return XCTFail("Expected .login")
        }
        XCTAssertEqual(item.name, "Example Login")
        XCTAssertEqual(login.username, "alice@example.com")
        XCTAssertEqual(login.password, "hunter2")
    }

    func test_perItemKeySurvivesAFullRoundTrip() throws {
        let wrapped = try EncString.encrypt(data: perItemKeys.toData(), keys: vaultKeys).toString()
        let original = makeLoginItem(preserved: makePreserved(cipherKey: wrapped))

        let raw       = try sut.toRawCipher(DraftVaultItem(original), encryptedWith: vaultKeys)
        let reMapped  = try sut.map(raw: raw, keys: vaultKeys).item

        XCTAssertEqual(reMapped.preserved.cipherKey, wrapped)
        XCTAssertEqual(reMapped.preserved.fido2Credentials, original.preserved.fido2Credentials)
        XCTAssertEqual(reMapped.preserved.passwordHistory, original.preserved.passwordHistory)
        XCTAssertEqual(reMapped.preserved.archivedDate, original.preserved.archivedDate)

        guard case .login(let before) = original.content,
              case .login(let after)  = reMapped.content else {
            return XCTFail("Expected .login on both sides")
        }
        XCTAssertEqual(after.username, before.username)
        XCTAssertEqual(after.password, before.password)
    }

    // MARK: - JSONValue round trip

    func test_jsonValuePreservesNestedShapesAndTypes() throws {
        let original = JSONValue.object([
            "text":    .string("value"),
            "flag":    .bool(false),
            "count":   .number(7),
            "nothing": .null,
            "list":    .array([.string("a"), .number(1), .object(["k": .bool(true)])])
        ])

        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
