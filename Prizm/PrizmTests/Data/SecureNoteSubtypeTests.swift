import XCTest
@testable import Prizm

/// Secure note subtypes: the value, its mapping, and the round trip that was losing it.
@MainActor
final class SecureNoteSubtypeTests: XCTestCase {

    // MARK: - 1.1.1 / 1.1.2 the mapping, asserted per case

    /// Asserted as integers rather than as "they round-trip", because a mapping that is wrong in the
    /// same way in both directions would round-trip perfectly and still mislabel a passport as a
    /// bank account.
    func testSubtype_documentedIntegers_mapToTheirCases() {
        let expected: [(Int, SecureNoteSubtype)] = [
            (0, .generic), (1, .bankAccount), (2, .driversLicense), (3, .passport),
            (4, .medicalRecord), (5, .membership), (6, .socialSecurity), (7, .wifi),
            (8, .softwareLicense)
        ]

        for (raw, subtype) in expected {
            XCTAssertEqual(SecureNoteSubtype(rawValue: raw), subtype, "raw \(raw)")
            XCTAssertEqual(subtype.rawValue, raw, "\(subtype) should be \(raw)")
        }
    }

    func testSubtype_documentedCases_areAllDistinct() {
        let raws = [SecureNoteSubtype.generic, .bankAccount, .driversLicense, .passport,
                    .medicalRecord, .membership, .socialSecurity, .wifi, .softwareLicense]
            .map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "two subtypes must not share an integer")
    }

    // MARK: - 1.1.3 / 1.1.4 an unknown value is carried, not flattened

    func testSubtype_unknownInteger_isNotFlattenedToGeneric() {
        XCTAssertEqual(SecureNoteSubtype(rawValue: 42), .unknown(42))
        XCTAssertNotEqual(SecureNoteSubtype(rawValue: 42), .generic)
    }

    func testSubtype_unknownInteger_roundTrips() {
        XCTAssertEqual(SecureNoteSubtype(rawValue: 99).rawValue, 99)
    }

    /// The case that makes "we did not recognise this" representable even when the number is zero:
    /// a future Bitwarden that moves Generic would otherwise be indistinguishable from today's.
    func testSubtype_unknownZero_isDistinguishableFromGeneric() {
        XCTAssertNotEqual(SecureNoteSubtype.unknown(0), SecureNoteSubtype.generic)
        XCTAssertEqual(SecureNoteSubtype.unknown(0).rawValue, 0)
    }

    // MARK: - 1.1.5 / 4.4 generic is the default

    func testSecureNoteContent_defaultsToGeneric() {
        let content = SecureNoteContent(notes: nil, customFields: [])
        XCTAssertEqual(content.subtype, .generic)
    }
}

/// The wire round trip — the half that was silently resetting the subtype to Generic.
@MainActor
final class SecureNoteSubtypeWireTests: XCTestCase {

    private let keys = CryptoKeys(
        encryptionKey: Data(repeating: 0x11, count: 32),
        macKey:        Data(repeating: 0x22, count: 32)
    )

    private func rawCipher(secureNoteType: Int?) throws -> RawCipher {
        let encryptedName = try EncString.encrypt(data: Data("My Note".utf8), keys: keys).toString()
        let note = try secureNoteType.map { try RawSecureNoteData(type: $0) }
        return RawCipher(
            id: "cipher-1", organizationId: nil, folderId: nil, type: 2,
            name: encryptedName, notes: nil, favorite: false, reprompt: nil,
            deletedDate: nil, creationDate: nil, revisionDate: nil,
            login: nil, card: nil, identity: nil, secureNote: note, sshKey: nil,
            fields: [], key: nil, collectionIds: [], attachments: nil
        )
    }

    private func item(subtype: SecureNoteSubtype) -> VaultItem {
        VaultItem(
            id: "cipher-1", name: "My Note", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .secureNote(SecureNoteContent(notes: nil, customFields: [], subtype: subtype))
        )
    }

    // MARK: - 2.1 decoding

    func testMap_readsTheSubtype() throws {
        let (mapped, _) = try CipherMapper().map(raw: try rawCipher(secureNoteType: 3), keys: keys)

        guard case .secureNote(let content) = mapped.content else {
            return XCTFail("Expected a secure note")
        }
        XCTAssertEqual(content.subtype, .passport)
    }

    func testMap_unknownSubtype_isCarried() throws {
        let (mapped, _) = try CipherMapper().map(raw: try rawCipher(secureNoteType: 77), keys: keys)

        guard case .secureNote(let content) = mapped.content else {
            return XCTFail("Expected a secure note")
        }
        XCTAssertEqual(content.subtype, .unknown(77))
    }

    /// 2.3 The server omits the payload for notes that predate the feature.
    func testMap_absentPayload_isGeneric() throws {
        let (mapped, _) = try CipherMapper().map(raw: try rawCipher(secureNoteType: nil), keys: keys)

        guard case .secureNote(let content) = mapped.content else {
            return XCTFail("Expected a secure note")
        }
        XCTAssertEqual(content.subtype, .generic)
    }

    // MARK: - 2.2 encoding: this is the assertion that would have caught the bug

    func testToRawCipher_writesTheSubtypeBack() throws {
        let raw = try CipherMapper().toRawCipher(
            DraftVaultItem(item(subtype: .passport)), encryptedWith: keys
        )

        XCTAssertEqual(
            raw.secureNote?.type, 3,
            "the subtype was hardcoded to 0 here, so every save reset it to Generic"
        )
    }

    func testToRawCipher_unknownSubtype_writesItsInteger() throws {
        let raw = try CipherMapper().toRawCipher(
            DraftVaultItem(item(subtype: .unknown(77))), encryptedWith: keys
        )

        XCTAssertEqual(raw.secureNote?.type, 77)
    }

    /// The whole point, end to end: what came off the wire goes back on it unchanged.
    func testRoundTrip_preservesEveryDocumentedSubtype() throws {
        let mapper = CipherMapper()
        let subtypes: [SecureNoteSubtype] = [
            .generic, .bankAccount, .driversLicense, .passport, .medicalRecord,
            .membership, .socialSecurity, .wifi, .softwareLicense, .unknown(42)
        ]

        for subtype in subtypes {
            let raw    = try mapper.toRawCipher(DraftVaultItem(item(subtype: subtype)), encryptedWith: keys)
            let (back, _) = try mapper.map(raw: raw, keys: keys)

            guard case .secureNote(let content) = back.content else {
                return XCTFail("Expected a secure note for \(subtype)")
            }
            XCTAssertEqual(content.subtype, subtype, "\(subtype) did not survive the round trip")
        }
    }
}
