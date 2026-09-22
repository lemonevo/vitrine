import Foundation
import XCTest
@testable import Prizm

/// The invariant `CipherMapperReverseTests` cannot express, and why that gap has bitten four times.
///
/// **What the existing tests do.** `VaultItem` → `DraftVaultItem` → `RawCipher` → `VaultItem`, then
/// compare the two items. Every assertion is about a field the model already has. That is a useful
/// test of the encrypt/decrypt cycle, and it is structurally incapable of catching the defect this
/// file guards: **a wire field the decoder reads but the encoder does not write.** A field with no
/// place in `VaultItem` cannot appear in an assertion about `VaultItem`.
///
/// **Why that matters more here than in most clients.** Vaultwarden stores the cipher object verbatim
/// (`cipher.data = type_data.to_string()`), and `PUT /ciphers/{id}` replaces the whole thing. So a
/// field missing from the request body is not left alone — it is deleted. Four instances have been
/// found (SSH key fingerprint, secure-note subtype, offline re-encode, collection permissions), and
/// one of them had the loss written into `CipherMapperReverseTests` as an expected assertion.
///
/// **The direction that catches it.** Wire → model → wire, then compare the two wire forms. Every
/// path that arrived with a value must leave with a value, and every path whose value is not a
/// re-encrypted secret must leave unchanged. This says nothing about whether Prizm *understands* a
/// field; it says it must not *lose* one.
///
/// **What it cannot catch.** A field the decoder also ignores — that never reaches the model, so it
/// is invisible from here too. That half belongs to the decoder's own tests.
@MainActor
final class CipherEncoderInvariantTests: XCTestCase {

    private var sut: CipherMapper!
    private let keys = CryptoKeys(
        encryptionKey: Data(repeating: 0xDE, count: 32),
        macKey:        Data(repeating: 0xAD, count: 32)
    )

    override func setUp() async throws {
        try await super.setUp()
        sut = CipherMapper()
        encryptedPaths = []
    }

    // MARK: - The tolerated exceptions
    //
    // Every entry is a deliberate hole in the invariant, so each needs a reason that stands on its
    // own. Adding one to silence a failing test is how this file stops doing its job — which is why
    // `test_theComparisonDetectsALostField` exists.

    /// Paths allowed to arrive with a value and go out without one.
    private static let toleratedOmissions: Set<String> = [
        // Server-maintained timestamps. The client has nothing to say about when an item began or was
        // last written, and sending its own copy of the latter would claim a write that has not
        // happened.
        "creationDate",
        "revisionDate",
        // Trashed items are restored and permanently deleted through their own endpoints, and no UI
        // path builds a draft from a trashed item.
        "deletedDate"
    ]

    /// Subtrees excused by prefix, for the fields whose values are not leaves.
    ///
    /// Attachments are sent as `nil` on purpose: Vaultwarden guards its only attachment write with
    /// `if let Some(attachments)`, so an absent key leaves stored attachments untouched, and they have
    /// their own endpoints. They need a prefix rather than a path because the flattener writes a
    /// *container marker* for the array itself and skips containers before the omission check — so a
    /// bare `"attachments"` entry, which is what used to be here, could never match anything. It looked
    /// like a hole in the invariant and was in fact inert decoration; the leaves
    /// (`attachments.0.fileName`) were never excused at all, and no fixture carried attachments either,
    /// so the one field this entry claimed to cover went untested in both directions.
    private static let toleratedOmissionSubtrees: [String] = ["attachments."]

    /// Paths whose value is an EncString, recorded by `enc(_:at:)` as the fixture is built. These are
    /// re-encrypted with a fresh IV and HMAC, so the bytes legitimately differ and only presence is
    /// asserted.
    ///
    /// Tracked per fixture rather than detected by pattern, because a regex for "looks encrypted" is
    /// exactly the kind of guess that would quietly start skipping a field that stopped being one.
    private var encryptedPaths: Set<String> = []

    // MARK: - Fixture helpers

    /// Encrypts a value the way the server would have sent it, recording where it landed.
    private func enc(_ plaintext: String, at path: String) -> String {
        encryptedPaths.insert(path)
        return try! EncString.encrypt(data: Data(plaintext.utf8), keys: keys).toString()
    }

    private func wireJSON(_ raw: RawCipher) throws -> [String: Any] {
        let data = try JSONEncoder().encode(raw)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// Flattens to dot-separated paths, indexing arrays: `login.uris.0.match`.
    ///
    /// Nulls are dropped rather than stored, so "absent" and "explicitly null" both read as missing —
    /// which is the distinction that matters here. Vaultwarden deletes on either.
    private func flatten(_ value: Any, at path: String, into out: inout [String: Any]) {
        switch value {
        case let dict as [String: Any]:
            out[path] = Self.container
            for (key, child) in dict { flatten(child, at: path.isEmpty ? key : "\(path).\(key)", into: &out) }
        case let array as [Any]:
            out[path] = Self.container
            for (index, child) in array.enumerated() { flatten(child, at: "\(path).\(index)", into: &out) }
        case is NSNull:
            break
        default:
            out[path] = value
        }
    }

    private static let container = "\u{0}container"

    private func flattened(_ raw: RawCipher) throws -> [String: Any] {
        var out: [String: Any] = [:]
        try flatten(wireJSON(raw), at: "", into: &out)
        return out
    }

    // MARK: - The comparison

    /// Every way in which `after` fails to carry forward what `before` contained.
    ///
    /// Split out from the assertion so it can be turned on itself — see
    /// `test_theComparisonDetectsALostField`.
    private func violations(before: [String: Any], after: [String: Any]) -> [String] {
        var found: [String] = []

        for (path, value) in before {
            if value as? String == Self.container { continue }

            guard let outgoing = after[path] else {
                if !Self.isTolerated(path) {
                    found.append("LOST \(path): arrived as \(value), sent back as nothing")
                }
                continue
            }

            // Encrypted fields are waived for equality — a fresh IV and HMAC make the bytes differ
            // legitimately — but never for presence, which is the check above.
            if encryptedPaths.contains(path) { continue }

            if String(describing: value) != String(describing: outgoing) {
                found.append("CHANGED \(path): arrived as \(value), went out as \(outgoing)")
            }
        }
        return found
    }

    /// Is this path excused from the presence check?
    private static func isTolerated(_ path: String) -> Bool {
        toleratedOmissions.contains(path)
            || toleratedOmissionSubtrees.contains { path.hasPrefix($0) }
    }

    private func assertNothingIsLost(_ input: RawCipher,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let item   = try sut.map(raw: input, keys: keys).item
        let output = try sut.toRawCipher(DraftVaultItem(item), encryptedWith: keys)

        let found = violations(before: try flattened(input), after: try flattened(output))
        XCTAssertTrue(found.isEmpty,
                      "\n" + found.sorted().joined(separator: "\n") +
                      "\n(A new exception needs a reason, not just a green test.)",
                      file: file, line: line)
    }

    // MARK: - Fixtures

    /// A login carrying every field the decoder reads, including the ones that have been lost before.
    private func fullLoginCipher() -> RawCipher {
        RawCipher(
            id: "cipher-1",
            organizationId: nil,
            folderId: "folder-1",
            type: 1,
            name:  enc("GitHub", at: "name"),
            notes: enc("recovery codes attached", at: "notes"),
            favorite: true,
            reprompt: 1,
            deletedDate: nil,
            creationDate: "2024-03-12T10:00:00.000Z",
            revisionDate: "2026-09-18T08:30:00.000Z",
            login: RawLoginData(
                username: enc("alice@example.com", at: "login.username"),
                password: enc("hunter2",           at: "login.password"),
                uris: [
                    RawURI(uri: enc("https://github.com/login", at: "login.uris.0.uri"), match: 1),
                    RawURI(uri: enc("https://github.com",       at: "login.uris.1.uri"), match: nil),
                    // 6 is "Never". It used to have no case in `URIMatchType`, so it decoded to nil and
                    // the next save erased it. 7 is a value no build of this app names, and must come
                    // back out as 7 rather than as nothing.
                    RawURI(uri: enc("https://evil.example",     at: "login.uris.2.uri"), match: 6),
                    RawURI(uri: enc("https://future.example",   at: "login.uris.3.uri"), match: 7)
                ],
                totp: enc("JBSWY3DPEHPK3PXP", at: "login.totp"),
                fido2Credentials: [
                    .object(["type": .number(0), "credentialId": .string("cred-1"),
                             "keySource": .string("local")])
                ],
                passwordRevisionDate: "2026-01-02T03:04:05.000Z",
                autofillOnPageLoad: true
            ),
            card: nil, identity: nil, secureNote: nil, sshKey: nil,
            fields: [
                RawField(type: 0, name: enc("Team", at: "fields.0.name"),
                         value: enc("Platform", at: "fields.0.value"), linkedId: nil),
                RawField(type: 1, name: enc("PIN", at: "fields.1.name"),
                         value: enc("1234", at: "fields.1.value"), linkedId: nil),
                RawField(type: 3, name: enc("Linked user", at: "fields.2.name"),
                         value: nil, linkedId: 100)
            ],
            key: nil,
            collectionIds: [],
            // The subtree tolerance is only meaningful if a fixture actually exercises it. With
            // `attachments: nil` here, the guard could neither catch attachments being dropped nor
            // notice that its own excuse for dropping them had stopped matching anything.
            attachments: [
                AttachmentDTO(id: "attachment-1",
                              fileName: enc("recovery-codes.txt", at: "attachments.0.fileName"),
                              key:      enc("2.iv|ct|mac",        at: "attachments.0.key"),
                              size:     "1024",
                              sizeName: "1 KB",
                              url:      "https://vault.example/attachments/attachment-1")
            ],
            passwordHistory: [
                .object(["type": .number(0),
                         "password": .string("2.aaa|bbb|ccc"),
                         "lastUsedDate": .string("2025-01-01T00:00:00.000Z")])
            ],
            archivedDate: "2026-05-05T00:00:00.000Z"
        )
    }

    func test_login_losesNothing() throws {
        try assertNothingIsLost(fullLoginCipher())
    }

    /// The subtype is a plain integer rather than an EncString, so it is checked by the equality half
    /// of the assertion — the half that would have caught it originally. A `switch` falling back to
    /// `.generic` sent `0`, turning a passport note into a generic one on the next save.
    func test_secureNote_preservesTheSubtypeInteger() throws {
        try assertNothingIsLost(RawCipher(
            id: "note-1", organizationId: nil, folderId: nil, type: 2,
            name: enc("Passport", at: "name"), notes: nil, favorite: false, reprompt: 0,
            deletedDate: nil, creationDate: nil, revisionDate: nil,
            login: nil, card: nil, identity: nil,
            secureNote: RawSecureNoteData(type: 3),
            sshKey: nil, fields: nil, key: nil, collectionIds: [], attachments: nil
        ))
    }

    /// The original instance of the pattern. A fingerprint is an EncString like its neighbours, so
    /// this exercises the presence half — sending `nil` is invisible to an equality check and fatal
    /// to the server's copy.
    func test_sshKey_preservesTheFingerprint() throws {
        try assertNothingIsLost(RawCipher(
            id: "ssh-1", organizationId: nil, folderId: nil, type: 5,
            name: enc("deploy-key", at: "name"), notes: enc("production", at: "notes"),
            favorite: false, reprompt: 0, deletedDate: nil, creationDate: nil, revisionDate: nil,
            login: nil, card: nil, identity: nil, secureNote: nil,
            sshKey: RawSSHKeyData(
                privateKey:     enc("-----BEGIN OPENSSH PRIVATE KEY-----", at: "sshKey.privateKey"),
                publicKey:      enc("ssh-ed25519 AAAA", at: "sshKey.publicKey"),
                keyFingerprint: enc("SHA256:abc123", at: "sshKey.keyFingerprint")
            ),
            fields: nil, key: nil, collectionIds: [], attachments: nil
        ))
    }

    func test_card_losesNothing() throws {
        try assertNothingIsLost(RawCipher(
            id: "card-1", organizationId: nil, folderId: nil, type: 3,
            name: enc("Visa", at: "name"), notes: nil, favorite: false, reprompt: 0,
            deletedDate: nil, creationDate: nil, revisionDate: nil,
            login: nil,
            card: RawCardData(
                cardholderName: enc("Jane Doe", at: "card.cardholderName"),
                brand:  enc("Visa", at: "card.brand"),
                number: enc("4111111111111111", at: "card.number"),
                expMonth: enc("12", at: "card.expMonth"),
                expYear:  enc("2028", at: "card.expYear"),
                code:     enc("123", at: "card.code")
            ),
            identity: nil, secureNote: nil, sshKey: nil, fields: nil, key: nil,
            collectionIds: [], attachments: nil
        ))
    }

    func test_identity_losesNothing() throws {
        try assertNothingIsLost(RawCipher(
            id: "id-1", organizationId: nil, folderId: nil, type: 4,
            name: enc("Alice Chen", at: "name"), notes: nil, favorite: false, reprompt: 0,
            deletedDate: nil, creationDate: nil, revisionDate: nil,
            login: nil, card: nil,
            identity: RawIdentityData(
                title: enc("Dr", at: "identity.title"),
                firstName: enc("Alice", at: "identity.firstName"),
                middleName: nil, lastName: enc("Chen", at: "identity.lastName"),
                address1: enc("1 Main St", at: "identity.address1"), address2: nil, address3: nil,
                city: enc("Springfield", at: "identity.city"), state: enc("IL", at: "identity.state"),
                postalCode: enc("62701", at: "identity.postalCode"),
                country: enc("US", at: "identity.country"),
                company: enc("ACME", at: "identity.company"),
                email: enc("a@b.c", at: "identity.email"), phone: enc("555", at: "identity.phone"),
                ssn: enc("123", at: "identity.ssn"), username: enc("alice", at: "identity.username"),
                passportNumber: enc("X1", at: "identity.passportNumber"),
                licenseNumber: enc("D1", at: "identity.licenseNumber")
            ),
            secureNote: nil, sshKey: nil, fields: nil, key: nil,
            collectionIds: [], attachments: nil
        ))
    }

    // MARK: - The guard on the guard

    /// **A check that cannot fail is worse than no check**, because it is the thing people stop
    /// questioning. This turns the comparison on a loss manufactured by hand rather than by a bug.
    func test_theComparisonDetectsALostField() throws {
        let cipher = fullLoginCipher()
        var after  = try flattened(cipher)
        let value  = try XCTUnwrap(after["reprompt"] as? Int)
        XCTAssertEqual(value, 1, "the fixture must really carry the field being used as the probe")

        // Removed from the *outgoing* side: the failure being simulated is the encoder dropping a
        // field that arrived, not the fixture forgetting to include one.
        after.removeValue(forKey: "reprompt")
        let found = violations(before: try flattened(cipher), after: after)
        XCTAssertEqual(found.count, 1, "expected exactly the planted loss, got: \(found)")
        XCTAssertTrue(found.first?.contains("LOST reprompt") == true, "got: \(found)")
    }

    /// The mirror: a value quietly rewritten rather than dropped has to be caught too, which is the
    /// half that covers the secure-note subtype.
    func test_theComparisonDetectsAChangedValue() throws {
        let cipher = fullLoginCipher()
        var after  = try flattened(cipher)
        after["favorite"] = false
        let found = violations(before: try flattened(cipher), after: after)
        XCTAssertTrue(found.contains { $0.contains("CHANGED favorite") }, "got: \(found)")
    }

    /// An encrypted field is waived for equality but **not** for presence — otherwise the list of
    /// encrypted paths would itself become a way to hide a loss.
    func test_encryptedFieldsAreStillCheckedForPresence() throws {
        let cipher = fullLoginCipher()
        var after = try flattened(cipher)
        after["login.password"] = nil
        let found = violations(before: try flattened(cipher), after: after)
        XCTAssertTrue(found.contains { $0.contains("LOST login.password") },
                      "a dropped EncString must still fail, got: \(found)")
    }

    /// A trashed item, which is the only way the `deletedDate` tolerance gets exercised. An excuse that
    /// no fixture triggers is not an excuse, it is a blind spot with a comment attached.
    func test_trashedItem_losesNothing() throws {
        try assertNothingIsLost(RawCipher(
            id: "trash-1", organizationId: nil, folderId: nil, type: 1,
            name: enc("Old GitHub", at: "name"), notes: nil, favorite: false, reprompt: 0,
            deletedDate: "2026-09-01T00:00:00.000Z", creationDate: nil, revisionDate: nil,
            login: RawLoginData(username: nil, password: nil, uris: [], totp: nil),
            card: nil, identity: nil, secureNote: nil, sshKey: nil,
            fields: nil, key: nil, collectionIds: [], attachments: nil
        ))
    }

    /// The URI strategies are the fifth instance of this file's defect class, and the only one that
    /// changes what a browser does with a credential. `URIMatchType` used to number its own cases from
    /// `domain = 0`, one below Bitwarden's `UriMatchStrategySetting`, so every choice above the first
    /// was written as its neighbour and 6 ("Never") had no case at all.
    ///
    /// The equality half of the invariant is what catches this: a mapping wrong identically in both
    /// directions round-trips perfectly, so the round trip alone passing proves nothing — the fixture
    /// has to carry the numbers, and the assertion has to be about the numbers.
    func test_uriMatchStrategiesSurviveAtTheirOwnValues() throws {
        let cipher = fullLoginCipher()
        let item   = try sut.map(raw: cipher, keys: keys).item
        let after  = try flattened(sut.toRawCipher(DraftVaultItem(item), encryptedWith: keys))

        XCTAssertEqual(after["login.uris.0.match"] as? Int, 1)
        XCTAssertEqual(after["login.uris.2.match"] as? Int, 6,
                       "a 'Never' rule came back as something else — the browser would autofill here")
        XCTAssertEqual(after["login.uris.3.match"] as? Int, 7,
                       "an unrecognised strategy must be carried, not normalised away")
        XCTAssertNil(after["login.uris.1.match"], "no choice made stays no choice made")

        try assertNothingIsLost(cipher)
    }

    /// Every entry in the tolerated lists has to be **true and in use**. A tolerance that no longer
    /// corresponds to anything the encoder drops will excuse the next field that shares its name; one
    /// that never matches anything at all — which is exactly what the old `"attachments"` entry was,
    /// because the flattener skips containers before the omission check — hides nothing but reads like
    /// it does.
    func test_tolerancesAreAllStillTrueAndStillExercised() throws {
        let cipher = fullLoginCipher()
        let item   = try sut.map(raw: cipher, keys: keys).item
        let before = try flattened(cipher)
        let after  = try flattened(sut.toRawCipher(DraftVaultItem(item), encryptedWith: keys))

        for path in Self.toleratedOmissions where path != "deletedDate" {
            XCTAssertNotNil(before[path],
                            "\(path) is tolerated but no fixture carries it — the entry excuses nothing")
            XCTAssertNil(after[path], """
            \(path) is listed as tolerated but the encoder now sends it — remove the entry, or it will \
            excuse a real loss later
            """)
        }

        for prefix in Self.toleratedOmissionSubtrees {
            let carried = before.keys.filter { $0.hasPrefix(prefix) }
            XCTAssertFalse(carried.isEmpty,
                           "\(prefix)* is tolerated but no fixture carries it — the entry excuses nothing")
            for path in carried {
                XCTAssertNil(after[path],
                             "\(path) sits under a tolerated subtree but the encoder now sends it")
            }
        }
    }
}
