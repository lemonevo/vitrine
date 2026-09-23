import XCTest
@testable import Prizm

/// Failing tests for CipherMapper (T017).
/// These tests will fail until CipherMapper + RawCipher are implemented (T020, T021).
@MainActor
final class CipherMapperTests: XCTestCase {

    private var sut: CipherMapper!
    private var mockKeys: CryptoKeys!

    override func setUp() async throws {
        try await super.setUp()
        sut = CipherMapper()
        mockKeys = CryptoKeys(
            encryptionKey: Data(repeating: 0xDE, count: 32),
            macKey:        Data(repeating: 0xAD, count: 32)
        )
    }

    // MARK: - Helpers

    /// Returns a minimal RawCipher with only required fields set.
    private func makeRawCipher(
        id:             String    = "uuid-test",
        organizationId: String?   = nil,
        folderId:       String?   = nil,
        type:           Int,
        name:           String,
        notes:          String?   = nil,
        favorite:       Bool      = false,
        deletedDate:    String?   = nil,
        revisionDate:   String?   = nil,
        login:          RawLoginData?      = nil,
        card:           RawCardData?       = nil,
        identity:       RawIdentityData?   = nil,
        secureNote:     RawSecureNoteData? = nil,
        sshKey:         RawSSHKeyData?     = nil
    ) -> RawCipher {
        RawCipher(
            id:             id,
            organizationId: organizationId,
            folderId:       folderId,
            type:           type,
            name:           name,
            notes:          notes,
            favorite:       favorite,
            reprompt:       nil,
            deletedDate:    deletedDate,
            creationDate:   nil,
            revisionDate:   revisionDate,
            login:          login,
            card:           card,
            identity:       identity,
            secureNote:     secureNote,
            sshKey:         sshKey,
            fields:         [],
            key:            nil,
            attachments:    nil
        )
    }

    /// Builds a minimal encrypted string for a known plaintext using mockKeys.
    private func enc(_ plaintext: String) throws -> String {
        let data = plaintext.data(using: .utf8)!
        return try EncString.encrypt(data: data, keys: mockKeys).toString()
    }

    // MARK: - Login cipher

    func testMapLoginCipher() throws {
        let raw = makeRawCipher(
            id:   "uuid-login",
            type: 1,
            name: try enc("My Login"),
            login: RawLoginData(
                username: try enc("alice@example.com"),
                password: try enc("s3cr3t"),
                uris:     [RawURI(uri: try enc("https://example.com"), match: nil)],
                totp:     nil
            )
        )

        let (item, _) = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertEqual(item.id, "uuid-login")
        XCTAssertEqual(item.name, "My Login")
        XCTAssertFalse(item.isFavorite)

        guard case .login(let login) = item.content else {
            return XCTFail("Expected .login content")
        }
        XCTAssertEqual(login.username, "alice@example.com")
        XCTAssertEqual(login.password, "s3cr3t")
        XCTAssertEqual(login.uris.first?.uri, "https://example.com")
    }

    // MARK: - Secure Note cipher

    func testMapSecureNoteCipher() throws {
        let raw = makeRawCipher(
            id:         "uuid-note",
            type:       2,
            name:       try enc("My Note"),
            notes:      try enc("Top secret notes"),
            favorite:   true,
            secureNote: RawSecureNoteData(type: 0)
        )

        let (item, _) = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertEqual(item.name, "My Note")
        XCTAssertTrue(item.isFavorite)

        guard case .secureNote(let note) = item.content else {
            return XCTFail("Expected .secureNote content")
        }
        XCTAssertEqual(note.notes, "Top secret notes")
    }

    // MARK: - Card cipher

    func testMapCardCipher() throws {
        let raw = makeRawCipher(
            id:   "uuid-card",
            type: 3,
            name: try enc("Visa"),
            card: RawCardData(
                cardholderName: try enc("Alice Smith"),
                brand:          try enc("Visa"),
                number:         try enc("4111111111111111"),
                expMonth:       try enc("12"),
                expYear:        try enc("2028"),
                code:           try enc("123")
            )
        )

        let (item, _) = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertEqual(item.name, "Visa")

        guard case .card(let card) = item.content else {
            return XCTFail("Expected .card content")
        }
        XCTAssertEqual(card.cardholderName, "Alice Smith")
        XCTAssertEqual(card.number, "4111111111111111")
    }

    // MARK: - Identity cipher

    func testMapIdentityCipher() throws {
        let raw = makeRawCipher(
            id:       "uuid-id",
            type:     4,
            name:     try enc("My Identity"),
            identity: RawIdentityData(
                title:          nil,
                firstName:      try enc("Alice"),
                middleName:     nil,
                lastName:       try enc("Smith"),
                address1:       nil, address2: nil, address3: nil,
                city:           nil, state: nil, postalCode: nil, country: nil,
                company:        nil,
                email:          try enc("alice@example.com"),
                phone:          nil, ssn: nil, username: nil,
                passportNumber: nil, licenseNumber: nil
            )
        )

        let (item, _) = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertEqual(item.name, "My Identity")

        guard case .identity(let identity) = item.content else {
            return XCTFail("Expected .identity content")
        }
        XCTAssertEqual(identity.firstName, "Alice")
        XCTAssertEqual(identity.lastName, "Smith")
        XCTAssertEqual(identity.email, "alice@example.com")
    }

    // MARK: - SSH Key cipher

    func testMapSshKeyCipher() throws {
        let raw = makeRawCipher(
            id:     "uuid-ssh",
            type:   5,
            name:   try enc("My SSH Key"),
            sshKey: RawSSHKeyData(
                privateKey:     try enc("-----BEGIN OPENSSH PRIVATE KEY-----\n..."),
                publicKey:      try enc("ssh-ed25519 AAAA..."),
                keyFingerprint: try enc("SHA256:abc123")
            )
        )

        let (item, _) = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertEqual(item.name, "My SSH Key")

        guard case .sshKey(let ssh) = item.content else {
            return XCTFail("Expected .sshKey content")
        }
        XCTAssertTrue((ssh.privateKey ?? "").hasPrefix("-----BEGIN"))
        XCTAssertTrue((ssh.publicKey ?? "").hasPrefix("ssh-ed25519"))
        XCTAssertEqual(ssh.keyFingerprint, "SHA256:abc123")
    }

    // MARK: - Organisation cipher filtered

    /// Ciphers belonging to an organisation must be filtered out (organizationId != nil).
    func testOrgCipherIsFiltered() throws {
        let raw = makeRawCipher(
            id:             "uuid-org",
            organizationId: "org-uuid-123",
            type:           1,
            name:           try enc("Org Login"),
            login: RawLoginData(username: try enc("user"), password: try enc("pass"),
                                uris: [], totp: nil)
        )

        XCTAssertThrowsError(try sut.map(raw: raw, keys: mockKeys)) { error in
            XCTAssertEqual(error as? CipherMapperError, .organisationCipherSkipped)
        }
    }

    // MARK: - Deleted cipher

    /// A cipher with a deletedDate must have isDeleted == true.
    func testDeletedCipherIsMarked() throws {
        let raw = makeRawCipher(
            id:          "uuid-del",
            type:        2,
            name:        try enc("Deleted Note"),
            deletedDate: "2025-01-01T00:00:00Z",
            secureNote:  RawSecureNoteData(type: 0)
        )

        let (item, _) = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertTrue(item.isDeleted)
    }

    // MARK: - folderId pass-through

    func testMapCipher_folderIdPassedThrough() throws {
        let raw = makeRawCipher(
            id:       "uuid-folder",
            folderId: "folder-abc-123",
            type:     2,
            name:     try enc("Note in folder"),
            secureNote: RawSecureNoteData(type: 0)
        )
        let item = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertEqual(item.item.folderId, "folder-abc-123")
    }

    func testMapCipher_nilFolderIdPassedThrough() throws {
        let raw = makeRawCipher(
            id:   "uuid-no-folder",
            type: 2,
            name: try enc("Unfoldered note"),
            secureNote: RawSecureNoteData(type: 0)
        )
        let item = try sut.map(raw: raw, keys: mockKeys)
        XCTAssertNil(item.item.folderId)
    }

    func testToRawCipher_folderIdIncluded() throws {
        let item = VaultItem(
            id: "uuid-rev", name: "Test", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .secureNote(SecureNoteContent(notes: nil, customFields: [])),
            folderId: "folder-xyz"
        )
        let draft = DraftVaultItem(item)
        let raw = try sut.toRawCipher(draft, encryptedWith: mockKeys)
        XCTAssertEqual(raw.folderId, "folder-xyz")
    }

    func testToRawCipher_nilFolderIdIncluded() throws {
        let item = VaultItem(
            id: "uuid-rev2", name: "Test", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
        let draft = DraftVaultItem(item)
        let raw = try sut.toRawCipher(draft, encryptedWith: mockKeys)
        XCTAssertNil(raw.folderId)
    }

    // MARK: - The optimistic-lock handshake

    /// The value sent as `lastKnownRevisionDate` must be the server's own string, not a reformatted
    /// `Date`. The server compares the two as instants to decide whether this client is editing a
    /// stale copy, so an approximation is the one thing it cannot be.
    private let serverRevision = "2026-09-22T18:49:53.123456Z"

    func testMapCipher_keepsTheServersRevisionDateVerbatim() throws {
        let raw = makeRawCipher(
            id: "uuid-rev-date", type: 2, name: try enc("Note"),
            revisionDate: serverRevision,
            secureNote: RawSecureNoteData(type: 0)
        )

        let (item, _) = try sut.map(raw: raw, keys: mockKeys)

        XCTAssertEqual(item.preserved.revisionDate, serverRevision)
    }

    func testToRawCipher_sendsTheRevisionItWasGiven() throws {
        let raw = makeRawCipher(
            id: "uuid-rev-send", type: 2, name: try enc("Note"),
            revisionDate: serverRevision,
            secureNote: RawSecureNoteData(type: 0)
        )
        let (item, _) = try sut.map(raw: raw, keys: mockKeys)

        let outbound = try sut.toRawCipher(DraftVaultItem(item), encryptedWith: mockKeys)

        XCTAssertEqual(outbound.lastKnownRevisionDate, serverRevision)
        // The model carrying the value is not the property under test — the bytes are. A field the
        // encoder drops would leave the check disabled while this test still passed on the model.
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(outbound)) as? [String: Any]
        )
        XCTAssertEqual(json["lastKnownRevisionDate"] as? String, serverRevision,
                       "the field has to be in the request body, not only in the struct")
    }

    func testToRawCipher_withoutAKnownRevision_omitsTheField() throws {
        // A create draft carries no `preserved`, so there is no revision to declare. Omitting the
        // key is what the server accepts as "no check" — the behaviour every older client has — and
        // is right for a new item. Sending some default instant there would be a lie about a copy
        // that does not exist yet.
        let draft = DraftVaultItem.blank(type: .secureNote)

        let outbound = try sut.toRawCipher(draft, encryptedWith: mockKeys)

        XCTAssertNil(outbound.lastKnownRevisionDate)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(outbound)) as? [String: Any]
        )
        XCTAssertNil(json["lastKnownRevisionDate"],
                     "an unknown revision must omit the key rather than send null")
    }

    // MARK: - Password history

    private func makeLoginDraft(password: String?,
                                replacedFrom: String?,
                                preserved: PreservedCipherFields = .empty) -> DraftVaultItem {
        let item = VaultItem(
            id: "uuid-pw", name: "Login", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .login(LoginContent(username: "user", password: replacedFrom, uris: [],
                                         totp: nil, notes: nil, customFields: [])),
            preserved: preserved
        )
        var draft = DraftVaultItem(item)
        guard case .login(var login) = draft.content else { return draft }
        login.password = password
        draft.content = .login(login)
        return draft
    }

    /// The server keeps no history of its own, so a client that only round-trips the array records
    /// nothing at all. The replaced password has to be added by this side.
    func testToRawCipher_changedPassword_appendsTheReplacedOne() throws {
        let earlier = JSONValue.object([
            "password":     .string("2.previous=="),
            "lastUsedDate": .string("2026-01-01T00:00:00.000Z"),
        ])
        let draft = makeLoginDraft(password: "new-secret", replacedFrom: "old-secret",
                                   preserved: PreservedCipherFields(passwordHistory: [earlier]))

        let raw = try sut.toRawCipher(draft, encryptedWith: mockKeys)

        let history = try XCTUnwrap(raw.passwordHistory)
        XCTAssertEqual(history.count, 2, "the entry it arrived with, plus the password being replaced")
        XCTAssertEqual(history.first, earlier, "the existing history must survive an edit")

        let appended = try XCTUnwrap(history.last)
        guard case .object(let fields) = appended,
              case .string(let encrypted) = try XCTUnwrap(fields["password"]) else {
            return XCTFail("Expected an object carrying an encrypted password, got \(appended)")
        }
        let plaintext = try EncString(string: encrypted).decrypt(keys: mockKeys)
        XCTAssertEqual(String(data: plaintext, encoding: .utf8), "old-secret",
                       "the entry must be the password being replaced — not the new one, and not in the clear")
        XCTAssertNotNil(fields["lastUsedDate"], "an entry with no date cannot be shown as history")
    }

    func testToRawCipher_unchangedPassword_addsNothing() throws {
        let draft = makeLoginDraft(password: "same-secret", replacedFrom: "same-secret")

        let raw = try sut.toRawCipher(draft, encryptedWith: mockKeys)

        XCTAssertEqual(raw.passwordHistory ?? [], [],
                       "saving an item without touching its password must not invent an entry")
    }

    func testToRawCipher_clearedPassword_addsNothing() throws {
        // Clearing the field is a deliberate removal, not a replacement. Recording it would put a
        // password the user has just deleted into the history they are shown.
        let draft = makeLoginDraft(password: "", replacedFrom: "old-secret")

        let raw = try sut.toRawCipher(draft, encryptedWith: mockKeys)

        XCTAssertEqual(raw.passwordHistory ?? [], [])
    }
}
