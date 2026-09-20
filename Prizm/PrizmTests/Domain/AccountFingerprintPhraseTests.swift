import XCTest
@testable import Prizm

// MARK: - AccountFingerprintPhraseTests

/// The fingerprint phrase, against known-answer vectors from the reference implementation.
///
/// **Every value asserted here comes from Bitwarden's own code, not from Prizm.** That is the
/// whole point of the requirement this covers: the phrase exists to be compared with what another
/// client shows, so a test that only checked Prizm against itself would prove nothing at all.
///
/// Vectors:
/// - the end-to-end one is the unit test in
///   `bitwarden/sdk-internal` → `crates/bitwarden-crypto/src/fingerprint.rs`, which carries a real
///   294-byte SPKI public key and a real user id;
/// - the single-step one is the TypeScript spec's `hashPhrase` expectation, reachable because a
///   key of 64 bytes or fewer becomes the HKDF prk directly.
final class AccountFingerprintPhraseTests: XCTestCase {

    // MARK: - The reference vector

    /// The SPKI public key from the reference's test, byte for byte.
    private static let referencePublicKey: [UInt8] = [
        48, 130, 1, 34, 48, 13, 6, 9, 42, 134, 72, 134, 247, 13, 1, 1, 1, 5, 0, 3, 130, 1, 15, 0, 48,
        130, 1, 10, 2, 130, 1, 1, 0, 187, 38, 44, 241, 110, 205, 89, 253, 25, 191, 126, 84, 121, 202,
        61, 223, 189, 244, 118, 212, 74, 139, 130, 97, 115, 164, 167, 106, 191, 188, 233, 218, 196,
        250, 187, 146, 125, 160, 150, 49, 198, 224, 176, 10, 0, 143, 99, 230, 232, 160, 51, 104, 154,
        211, 33, 80, 170, 4, 68, 80, 219, 115, 167, 114, 156, 227, 125, 193, 128, 123, 39, 254, 191,
        124, 63, 129, 44, 63, 18, 56, 161, 48, 158, 0, 27, 146, 2, 99, 136, 75, 21, 135, 6, 118, 12,
        26, 251, 184, 172, 249, 53, 78, 210, 46, 143, 17, 104, 202, 65, 173, 229, 219, 233, 144, 163,
        101, 216, 238, 152, 54, 158, 1, 195, 50, 203, 21, 226, 12, 82, 170, 175, 170, 160, 21, 247,
        248, 80, 97, 123, 0, 152, 116, 229, 126, 221, 199, 155, 194, 192, 51, 207, 177, 240, 160, 84,
        241, 41, 88, 176, 53, 111, 28, 173, 177, 232, 158, 22, 79, 133, 152, 31, 32, 12, 196, 147,
        58, 57, 50, 252, 208, 131, 150, 179, 132, 178, 150, 234, 251, 143, 125, 163, 144, 20, 46, 71,
        168, 252, 164, 86, 120, 124, 56, 252, 206, 210, 236, 212, 139, 127, 189, 236, 40, 46, 2, 238,
        13, 216, 40, 48, 85, 133, 229, 181, 155, 176, 217, 241, 154, 153, 213, 112, 222, 72, 219, 197,
        3, 219, 56, 77, 109, 47, 72, 251, 131, 36, 240, 96, 169, 31, 82, 93, 166, 242, 3, 33, 213,
        2, 3, 1, 0, 1
    ]

    private static let referenceUserId    = "a09726a0-9590-49d1-a5f5-afe300b6a515"
    private static let referencePhrase    = "turban-deftly-anime-chatroom-unselfish"

    func testReferenceVector_producesThePublishedPhrase() throws {
        let phrase = try AccountFingerprintPhrase.phrase(
            material:  Self.referenceUserId,
            publicKey: Data(Self.referencePublicKey),
            wordList:  try Self.wordList()
        )
        XCTAssertEqual(phrase, Self.referencePhrase)
    }

    /// The word-selection step, on its own, against the TypeScript spec's expectation.
    ///
    /// Covering the two halves separately is the point: with only the end-to-end vector, a wrong
    /// byte order and a wrong HKDF both surface as "the phrase is wrong", and the two faults are
    /// indistinguishable without reading the implementation again.
    ///
    /// These 32 bytes are the reference spec's mocked key fingerprint — a value that has already
    /// been through HKDF-Expand — and the expected phrase is what its spec asserts.
    func testWordSelection_matchesTheReferenceStep() throws {
        let hash = try XCTUnwrap(Data(
            base64Encoded: "V5AQSk83YXd6kZqCncC6d9J72R7UZ60Xl1eIoDoWgTc="
        ))

        let phrase = try AccountFingerprintPhrase.phrase(forHash: hash, wordList: try Self.wordList())

        XCTAssertEqual(phrase, "predefine-hunting-pastime-enrich-unhearing")
    }

    /// The prk branch the end-to-end vector cannot reach.
    ///
    /// The Rust reference passes the whole key to HKDF where the TypeScript one passes
    /// `SHA256(key)`; they agree only because HMAC hashes a key longer than its 64-byte block
    /// first, which is why the 294-byte key above works. A key at or under the block size takes
    /// the other branch, and there is no reference vector for it — so this pins it against
    /// HKDF-Expand computed independently (RFC 5869, HMAC-SHA-256) rather than against itself:
    ///
    ///     HMAC-SHA256(key = 32 x 0x41, "test@example.com" || 0x01)
    ///         = W4ScqP+kzBZzJgayK/HLnsw+A+owFBMb4CPI5OX/fvU=
    ///
    /// The comparison is made on the *phrase* rather than on the intermediate hash, so only the
    /// public entry points are used — no test-only door into the implementation.
    func testKeyAtOrUnderTheBlockSize_isUsedAsThePRKDirectly() throws {
        let shortKey     = Data(repeating: 0x41, count: 32)
        let expectedHash = try XCTUnwrap(
            Data(base64Encoded: "W4ScqP+kzBZzJgayK/HLnsw+A+owFBMb4CPI5OX/fvU=")
        )

        let fromKey  = try AccountFingerprintPhrase.phrase(
            material: "test@example.com", publicKey: shortKey, wordList: try Self.wordList())
        let fromHash = try AccountFingerprintPhrase.phrase(
            forHash: expectedHash, wordList: try Self.wordList())

        XCTAssertEqual(fromKey, fromHash)
    }

    // MARK: - Properties the spec asks for

    func testPhrase_isFiveWords() throws {
        let phrase = try AccountFingerprintPhrase.phrase(
            material:  Self.referenceUserId,
            publicKey: Data(Self.referencePublicKey),
            wordList:  try Self.wordList()
        )
        XCTAssertEqual(phrase.split(separator: "-").count, 5)
    }

    func testPhrase_isStableAcrossCalls() throws {
        let wordList = try Self.wordList()
        let first  = try AccountFingerprintPhrase.phrase(
            material: Self.referenceUserId, publicKey: Data(Self.referencePublicKey),
            wordList: wordList)
        let second = try AccountFingerprintPhrase.phrase(
            material: Self.referenceUserId, publicKey: Data(Self.referencePublicKey),
            wordList: wordList)
        XCTAssertEqual(first, second)
    }

    /// A different account must not collide. The material is the only thing that changes, which is
    /// what makes the phrase an identity check rather than a property of the server.
    func testDifferentAccount_producesADifferentPhrase() throws {
        let wordList = try Self.wordList()
        let mine = try AccountFingerprintPhrase.phrase(
            material: Self.referenceUserId, publicKey: Data(Self.referencePublicKey),
            wordList: wordList)
        let other = try AccountFingerprintPhrase.phrase(
            material: "3d9b2f4e-1c7a-4b8d-9e2f-6a5c8d1b4e70",
            publicKey: Data(Self.referencePublicKey), wordList: wordList)
        XCTAssertNotEqual(mine, other)
    }

    /// The word list is shared with the passphrase generator. If it is ever swapped, this fails
    /// rather than letting the fingerprint change silently into something that matches no client.
    func testWordList_isTheReferenceSize() throws {
        XCTAssertEqual(try Self.wordList().count, 7776)
    }

    // MARK: - Fixture

    /// Read from the repository rather than `Bundle.main`: `swift test` has no resource bundle,
    /// which is why the generator's own word-list cases are among the known baseline failures.
    private static func wordList() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)          // .../Prizm/PrizmTests/Data/<file>
            .deletingLastPathComponent()                    // Data
            .deletingLastPathComponent()                    // PrizmTests
            .deletingLastPathComponent()                    // Prizm
            .deletingLastPathComponent()                    // repository root
            .appendingPathComponent("Prizm/Resources/eff-large-wordlist.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let words = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard words.count == 7776 else {
            throw WordListFixtureError.unexpectedCount(words.count)
        }
        return words
    }

    private enum WordListFixtureError: Error {
        case unexpectedCount(Int)
    }
}

// MARK: - SPKIEncoderTests

/// The PKCS#1 → SPKI wrap, checked against `openssl`, not against itself.
final class SPKIEncoderTests: XCTestCase {

    /// `openssl rsa -RSAPublicKey_out -outform DER` for one generated key.
    private static let pkcs1 = "MIIBCgKCAQEAt0bsA/ADZCI6R7PPCAczgx7Ra/FEvXdbd/leKVsIoCF2N32j7qqIIBvL5YltZaPNUQW8t5vpP//xtrajEqvneP2THSr5SLH++G8vMiX03qZ1aK5pZv1nfy1g6TSHDMNarewYqj0KOd+flMtlz3HFUQnlU5yRITv1MkP9q09/K1fXVQzbuLR/gHBapTU213lawZI1ub1Yo/+qoCDIGxIB1lrl6rX+ayrPK97BaciT2Ey/CJZZCQlKbUg5gWy7sgQ1QdUySQc8kOxTBG5ahWdHgrTt3jm/g65eB0Z8ZfNiOTA/ZG4ZsW/sdpUc9q/trcQiBHpJthRU1Y/cjNl13kp0EQIDAQAB"
    /// `openssl rsa -pubout -outform DER` for the same key.
    private static let spki  = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAt0bsA/ADZCI6R7PPCAczgx7Ra/FEvXdbd/leKVsIoCF2N32j7qqIIBvL5YltZaPNUQW8t5vpP//xtrajEqvneP2THSr5SLH++G8vMiX03qZ1aK5pZv1nfy1g6TSHDMNarewYqj0KOd+flMtlz3HFUQnlU5yRITv1MkP9q09/K1fXVQzbuLR/gHBapTU213lawZI1ub1Yo/+qoCDIGxIB1lrl6rX+ayrPK97BaciT2Ey/CJZZCQlKbUg5gWy7sgQ1QdUySQc8kOxTBG5ahWdHgrTt3jm/g65eB0Z8ZfNiOTA/ZG4ZsW/sdpUc9q/trcQiBHpJthRU1Y/cjNl13kp0EQIDAQAB"

    func testEncoding_matchesOpenSSL() throws {
        let pkcs1 = try XCTUnwrap(Data(base64Encoded: Self.pkcs1))
        let expected = try XCTUnwrap(Data(base64Encoded: Self.spki))

        XCTAssertEqual(SPKIEncoder.encode(pkcs1PublicKey: pkcs1), expected)
    }

    /// The reference hashes the SPKI form, so the output has to be 24 bytes longer than the
    /// PKCS#1 it wraps — and the prefix has to name rsaEncryption, not some other algorithm.
    func testEncoding_prefixesTheRSAAlgorithmIdentifier() throws {
        let pkcs1 = try XCTUnwrap(Data(base64Encoded: Self.pkcs1))
        let encoded = SPKIEncoder.encode(pkcs1PublicKey: pkcs1)

        XCTAssertEqual(encoded.count, pkcs1.count + 24)
        XCTAssertEqual(
            [UInt8](encoded.prefix(19)),
            [0x30, 0x82, 0x01, 0x22,
             0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
             0x05, 0x00]
        )
    }

    /// The unused-bits octet inside the BIT STRING. Omitting it produces a structure that parses
    /// under a lenient decoder and hashes differently — the failure mode this whole type exists
    /// to prevent.
    func testEncoding_startsTheBitStringWithAZeroOctet() throws {
        let pkcs1 = try XCTUnwrap(Data(base64Encoded: Self.pkcs1))
        let encoded = SPKIEncoder.encode(pkcs1PublicKey: pkcs1)

        XCTAssertEqual(encoded[23], 0x00)
        XCTAssertEqual([UInt8](encoded.suffix(pkcs1.count)), [UInt8](pkcs1))
    }
}
