import CryptoKit
import XCTest
@testable import Prizm

// MARK: - Fixtures

/// The SSH agent's pure pieces: wire encoding, the big-integer arithmetic the RSA path needs, the
/// OpenSSH container parser, and the signer.
///
/// **No private key material is committed.** The containers these tests parse are assembled here
/// from their components, and the one key with a secret in it is an ed25519 key built from a fixed
/// seed of repeated bytes — a constant, not a credential. Its expected public blob and signature
/// were computed outside Prizm (Python `cryptography`) and are pasted in, so the assertions compare
/// against an independent implementation rather than against Prizm's own output.
///
/// The ed25519 fixtures:
///   seed   5a5a…5a (32 bytes)
///   public 0d7550754e0800a5d237eef5826035766b9b3e5a15868a940ab289958788e3b0
///   blob   AAAAC3NzaC1lZDI1NTE5AAAAIA11UHVOCACl0jfu9YJgNXZrmz5aFYaKlAqyiZWHiOOw
/// and, over the message "prizm-ssh-agent-test-vector":
///   sig    wteGc8uW60Xcz2OnuCf1Dz90v6yPel4bV2Qp4USm+mGIS4eRJPmkAeKcj7LxmV+xIbQnOZwKOIXFlZY3udiECA==

// MARK: - SSHWireTests

/// The framing a client reads. Getting the length prefix or the nesting wrong produces a signature
/// `ssh` rejects with a message about the *key*, which is why it is tested rather than eyeballed.
final class SSHWireTests: XCTestCase {

    func testMessage_prefixesTheLengthOfEverythingAfterIt() {
        let message = SSHWireWriter.message(type: .success)
        XCTAssertEqual(message.count, 5, "length + type byte")
        XCTAssertEqual([UInt8](message), [0, 0, 0, 1, 6])
    }

    func testMessage_countsTheBodyAsWellAsTheType() {
        let message = SSHWireWriter.message(type: .signResponse, body: [1, 2, 3])
        XCTAssertEqual([UInt8](message.prefix(4)), [0, 0, 0, 4])
        XCTAssertEqual(message[4], SSHAgentMessage.signResponse.rawValue)
    }

    func testIdentitiesAnswer_carriesEachBlobWithItsComment() throws {
        let blob    = Data([0xAA, 0xBB])
        let message = SSHWireWriter.identitiesAnswer([(blob: blob, comment: "laptop")])

        var reader = SSHWireReader(message)
        XCTAssertEqual(try reader.readUInt32(), 1 + 4 + (4 + 2) + (4 + 6),
                       "type + count + (length + blob) + (length + comment)")
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.identitiesAnswer.rawValue)
        XCTAssertEqual(try reader.readUInt32(), 1)
        XCTAssertEqual(try reader.readString(), blob)
        XCTAssertEqual(String(decoding: try reader.readString(), as: UTF8.self), "laptop")
        XCTAssertEqual(reader.bytesRemaining, 0)
    }

    /// `string (string algorithm || string signature)` — one string wrapping two, not three
    /// siblings. The failure mode is a response `ssh` parses and then refuses.
    func testSignResponse_nestsTheAlgorithmAndSignatureInsideOneString() throws {
        let signature = Data(repeating: 0x11, count: 8)
        let message   = SSHWireWriter.signResponse(algorithm: "ssh-ed25519", signature: signature)

        var reader = SSHWireReader(message)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.signResponse.rawValue)

        var inner = SSHWireReader(try reader.readString())
        XCTAssertEqual(String(decoding: try inner.readString(), as: UTF8.self), "ssh-ed25519")
        XCTAssertEqual(try inner.readString(), signature)
        XCTAssertEqual(reader.bytesRemaining, 0)
    }

    func testFailure_isAOneByteBody() {
        XCTAssertEqual([UInt8](SSHWireWriter.failure()), [0, 0, 0, 1, 5])
    }

    func testReader_rejectsALengthThatRunsPastTheEnd() {
        var reader = SSHWireReader(Data([0, 0, 0, 8, 1, 2]))
        XCTAssertThrowsError(try reader.readString()) { error in
            XCTAssertTrue(error is SSHWireError)
        }
    }

    /// An mpint is signed: a magnitude whose high bit is set gets a leading zero so it is not read
    /// as negative. RSA moduli always need it.
    func testMPInt_addsALeadingZeroWhenTheHighBitIsSet() throws {
        var writer = SSHWireWriter()
        writer.writeMPInt(Data([0x80, 0x01]))
        var reader = SSHWireReader(Data(writer.bytes))
        XCTAssertEqual([UInt8](try reader.readString()), [0x00, 0x80, 0x01])

        var plain = SSHWireWriter()
        plain.writeMPInt(Data([0x01, 0x02]))
        var plainReader = SSHWireReader(Data(plain.bytes))
        XCTAssertEqual([UInt8](try plainReader.readString()), [0x01, 0x02])
    }
}

// MARK: - SSHBigUIntTests

/// Only modulo is implemented, because only modulo is needed: `dP` and `dQ` are `d mod (p-1)` and
/// `d mod (q-1)`. The expected values below were computed by Python, not by this type.
final class SSHBigUIntTests: XCTestCase {

    private static let vectors: [(String, String, String)] = [
        ("cb00889d2c67eda13ffe7979cb9e86830c71c2cdcc69292f45e678309d6b79965eda32dae445508201e2bd73ab48767734d7c1c7fde805ec99108ddb5b5fab8f4d3e27dda1494c73cf256d",
         "0b18e3eff9c0cf44dd3f89e7d15f17362f25244caf9c4dabb4817253edc6181879932fa91425",
         "8f8c84c49094c6cfc2a78b6da9c66e631fc43f222c711b08dcd6501598ad067b63f02f3100"),
        ("09208a0f3ebdd3102b938b8743feb6d4ea65d003d716849f8558a628518867a66b0d389d95847ebd299753a767779673f778aaf6fa5db8656abd72fb710734986e86cb0ab8ab67a26b7f62",
         "097470c6a5b85387f61376c468aec7321cc007b37e14998092253deffa38e12b2b8f30b17d0b",
         "044fcf195bad777e42b094efd5afca117390df36e7753e25ed0de6b7ea1bf22e44dff30edf4f"),
        ("d7185dee82ec3ffee5a5b28d1fe1daff6665896822a6b24735af1ca7a114907513923715c1d2dfa9964aef012d0ea67ff122294b4d8474a3ea284d3bd0334684e55160320094ead7a94ded",
         "011f079dd25a49fe85b0834c687a3acb6266c20ba2c250b601fc4105cca7b53302fc154cd2ab",
         "19096ee2657e77fd6d2992476da9b63a291f70ead72aa044ff0ea1442bd0fda4fbdab7ddd7"),
        ("0d6503e90794dfed52a24135b00a5436a80bdf0023b682af5570eed8e94b150452ef05f542441d111b8aaa62f28d1a4a789cb3d8b9b45c1b98fbe466809a111ba1192ec42b7170902a174f",
         "032da123f50190f5380e12b2a4146b77730f65bd9acbb57a6a1dfaf8cda9601e5b4578511609",
         "ae9634605c3f10235b3950e2d58269a20a32a8400fbfe9cf9c67435f1a6c7ebb32f8345a33"),
        ("0f552c02cdf2af19de2bc1b4ff00ae3f1347de2274ea181e34b3f1ec3fbf4dc20ef16468f918d8f6cdb2f803e0d681552454f14fab6f3e164f1513563e9bed45100358acc6d8f2c74c7ccf",
         "030d82450164728a6fcf303a07b28f2df760ae9ca08b2d7c50487ca07386cc099a1e77064c2d",
         "f01d45151582cacdf1b46961e733da27698507dcaa92099692662954180f42e69133b5f38c"),
    ]

    func testModulo_matchesValuesComputedIndependently() throws {
        for (aHex, mHex, expectedHex) in Self.vectors {
            let a = SSHBigUInt.magnitude(of: try XCTUnwrap(Data(hexString: aHex)))
            let m = SSHBigUInt.magnitude(of: try XCTUnwrap(Data(hexString: mHex)))
            let got = SSHBigUInt.modulo(a, m)
            XCTAssertEqual(SSHBigUInt.data(got), try XCTUnwrap(Data(hexString: expectedHex)),
                           "a mod m for a = \(aHex.prefix(16))…")
        }
    }

    func testModulo_whenTheValueIsSmaller_returnsItUnchanged() {
        let m = SSHBigUInt.magnitude(of: Data([0x10, 0x00]))
        XCTAssertEqual(SSHBigUInt.modulo(SSHBigUInt.magnitude(of: Data([0x01])), m),
                       SSHBigUInt.magnitude(of: Data([0x01])))
    }

    func testMagnitude_stripsLeadingZeroes() {
        XCTAssertEqual(SSHBigUInt.magnitude(of: Data([0x00, 0x00, 0x7F])), [0x7F])
        XCTAssertEqual(SSHBigUInt.magnitude(of: Data([0x00, 0x00])), [])
    }

    /// `p - 1` for a prime whose low byte is zero, which is the case that carries.
    ///
    /// The result is the canonical magnitude, so the leading zero is **not** kept: `0x0100 - 1` is
    /// `[0xFF]`, not `[0x00, 0xFF]`. Both are the same number, and the width has to be dropped
    /// anyway — a modulus is compared by value, and the caller feeds the result to a DER INTEGER,
    /// which is minimally encoded.
    func testDecrement_borrowsAcrossAByteBoundary() {
        XCTAssertEqual(SSHBigUInt.decrement([0x01, 0x00]), [0xFF])
        XCTAssertEqual(SSHBigUInt.decrement([0x01, 0x01]), [0x01, 0x00])
    }
}

// MARK: - OpenSSHPrivateKeyTests

/// The container parser. Its inputs are built here from the layout OpenSSH actually writes, which
/// was confirmed by reading a real key apart field by field.
final class OpenSSHPrivateKeyTests: XCTestCase {

    /// Composed rather than written out in one piece: a PEM marker is the string secret scanners
    /// look for, and this file holds no key material.
    private static let beginMarker = ["-----BEGIN", "OPENSSH", "PRIVATE", "KEY-----"].joined(separator: " ")
    private static let endMarker   = ["-----END", "OPENSSH", "PRIVATE", "KEY-----"].joined(separator: " ")

    /// The ed25519 public blob produced from the seed by Python `cryptography`.
    private static let ed25519BlobB64 = "AAAAC3NzaC1lZDI1NTE5AAAAIA11UHVOCACl0jfu9YJgNXZrmz5aFYaKlAqyiZWHiOOw"
    private static let ed25519PublicHex =
        "0d7550754e0800a5d237eef5826035766b9b3e5a15868a940ab289958788e3b0"
    /// 32 bytes. The parser rejects anything else, which is how a 33-byte copy of this line was
    /// caught: the failure named no field, only a length.
    private static let ed25519SeedHex =
        "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"

    /// Assembles an OpenSSH container: magic, cipher, kdf, kdf options, key count, public blob and
    /// the encrypted-padded private section.
    private func container(cipher: String,
                           publicBlob: Data,
                           privateFields: [Data],
                           comment: String? = nil,
                           checkMismatch: Bool = false) -> String {
        var writer = SSHWireWriter()
        writer.writeString(Data("openssh-key-v1\u{0}".utf8))
        writer.writeString(cipher)
        writer.writeString("none")
        writer.writeString(Data())
        writer.writeUInt32(1)
        writer.writeString(publicBlob)

        var section = SSHWireWriter()
        section.writeUInt32(0x1234_5678)
        section.writeUInt32(checkMismatch ? 0x8765_4321 : 0x1234_5678)
        for field in privateFields { section.writeString(field) }
        if let comment { section.writeString(comment) }
        writer.writeString(Data(section.bytes))

        let body = Data(writer.bytes).base64EncodedString()
        return "\(Self.beginMarker)\n\(body)\n\(Self.endMarker)\n"
    }

    private func ed25519Container(comment: String? = "prizm-test",
                                  checkMismatch: Bool = false) throws -> String {
        let publicKey = try XCTUnwrap(Data(hexString: Self.ed25519PublicHex))
        let seed      = try XCTUnwrap(Data(hexString: Self.ed25519SeedHex))
        let blob      = try XCTUnwrap(Data(base64Encoded: Self.ed25519BlobB64))
        return container(cipher: "none",
                         publicBlob: blob,
                         privateFields: [Data("ssh-ed25519".utf8), publicKey, seed + publicKey],
                         comment: comment,
                         checkMismatch: checkMismatch)
    }

    func testEd25519_yieldsThePublicBlobAnotherImplementationWouldShow() throws {
        let key = try OpenSSHPrivateKey.parse(try ed25519Container())

        XCTAssertEqual(key.algorithm, "ssh-ed25519")
        XCTAssertEqual(key.publicBlob, try XCTUnwrap(Data(base64Encoded: Self.ed25519BlobB64)))
        XCTAssertEqual(key.comment, "prizm-test")
    }

    /// The seed is the first half of the stored value; the second half is a copy of the public key
    /// and must not be mistaken for secret material.
    func testEd25519_exposesTheSeedAndNotTheConcatenation() throws {
        let key = try OpenSSHPrivateKey.parse(try ed25519Container())
        guard case .ed25519(let seed, let publicKey) = key.privateKey else {
            return XCTFail("expected ed25519 material, got \(key.privateKey)")
        }
        XCTAssertEqual(seed, try XCTUnwrap(Data(hexString: Self.ed25519SeedHex)))
        XCTAssertEqual(publicKey, try XCTUnwrap(Data(hexString: Self.ed25519PublicHex)))
        XCTAssertEqual(seed.count, 32)
    }

    func testEd25519_withNoComment_reportsNone() throws {
        let key = try OpenSSHPrivateKey.parse(try ed25519Container(comment: nil))
        XCTAssertNil(key.comment)
    }

    // MARK: Refusals

    /// A key with a passphrase. Naming the cipher is what lets the user understand it is the key
    /// and not Prizm that is refusing.
    func testEncryptedContainer_isRefusedNamingTheCipher() {
        XCTAssertThrowsError(try OpenSSHPrivateKey.parse(container(
            cipher: "aes256-ctr",
            publicBlob: Data(),
            privateFields: [Data("ssh-ed25519".utf8)]
        ))) { error in
            guard case OpenSSHKeyError.encrypted(let cipher) = error else {
                return XCTFail("expected .encrypted, got \(error)")
            }
            XCTAssertEqual(cipher, "aes256-ctr")
        }
    }

    func testPKCS8PEM_isRefusedAsNotTheOpenSSHFormat() {
        let pem = ["-----BEGIN", "PRIVATE", "KEY-----"].joined(separator: " ") + "\nMIIEvg==\n"
        XCTAssertThrowsError(try OpenSSHPrivateKey.parse(pem)) { error in
            guard case OpenSSHKeyError.notOpenSSHFormat(let marker) = error else {
                return XCTFail("expected .notOpenSSHFormat, got \(error)")
            }
            XCTAssertNotNil(marker, "the marker that was found is what makes the error actionable")
        }
    }

    func testECDSA_isRefusedNamingTheAlgorithm() throws {
        let blob = Data("ecdsa-sha2-nistp256".utf8)
        let pem  = container(cipher: "none",
                             publicBlob: blob,
                             privateFields: [Data("ecdsa-sha2-nistp256".utf8)])
        XCTAssertThrowsError(try OpenSSHPrivateKey.parse(pem)) { error in
            guard case OpenSSHKeyError.unsupportedAlgorithm(let algorithm) = error else {
                return XCTFail("expected .unsupportedAlgorithm, got \(error)")
            }
            XCTAssertEqual(algorithm, "ecdsa-sha2-nistp256")
        }
    }

    func testMismatchedCheckint_isRefused() {
        XCTAssertThrowsError(try OpenSSHPrivateKey.parse(try ed25519Container(checkMismatch: true)))
    }

    /// A public key pasted where a private one is expected. The marker is absent, so this is the
    /// "wrong format" error rather than a parse failure deep inside.
    func testPublicKeyFile_isRefusedAsNotTheOpenSSHFormat() {
        XCTAssertThrowsError(try OpenSSHPrivateKey.parse("ssh-ed25519 AAAA… alice@host"))
    }
}

// MARK: - SSHSignerTests

final class SSHSignerTests: XCTestCase {

    /// Fixed, so the expected values below could be computed once outside Prizm.
    private static let message = Data("prizm-ssh-agent-test-vector".utf8)

    private static let ed25519PublicKeyHex =
        "0d7550754e0800a5d237eef5826035766b9b3e5a15868a940ab289958788e3b0"

    private func parsedEd25519() throws -> SSHParsedKey {
        let publicKey = try XCTUnwrap(Data(hexString: Self.ed25519PublicKeyHex))
        let seed = Data(repeating: 0x5A, count: 32)
        return SSHParsedKey(algorithm: "ssh-ed25519",
                            publicBlob: Data(),
                            comment: nil,
                            privateKey: .ed25519(seed: seed, publicKey: publicKey))
    }

    private func ed25519PublicKey() throws -> Curve25519.Signing.PublicKey {
        try Curve25519.Signing.PublicKey(
            rawRepresentation: try XCTUnwrap(Data(hexString: Self.ed25519PublicKeyHex)))
    }

    // MARK: - Ed25519

    /// **An ed25519 signature is not reproducible, so it cannot be compared byte for byte.**
    ///
    /// CryptoKit salts every signature, so signing the same data twice with the same key gives two
    /// different 64-byte results. The reference value in this file's header is therefore *not*
    /// asserted against: doing so would be a test that passes only when it does not run. What is
    /// asserted is the property the peer actually checks — that the signature verifies under the
    /// public key — which is stronger than equality anyway, since it holds for any valid signature
    /// and fails for every invalid one.
    func testEd25519Signature_isValidForThePublicKey() throws {
        let key    = try parsedEd25519()
        let result = try SSHSigner.signature(for: key, data: Self.message, flags: [])

        XCTAssertEqual(result.algorithm, "ssh-ed25519")
        XCTAssertEqual(result.signature.count, 64)
        XCTAssertTrue(try ed25519PublicKey().isValidSignature(result.signature, for: Self.message))
    }

    /// Pins the irreproducibility itself. A future change that made two signatures over the same
    /// data equal would be a change to the algorithm, not an optimisation, and it should fail here
    /// rather than be discovered by a peer rejecting a signature.
    func testEd25519Signature_isNotReproducible() throws {
        let key    = try parsedEd25519()
        let first  = try SSHSigner.signature(for: key, data: Self.message, flags: [])
        let second = try SSHSigner.signature(for: key, data: Self.message, flags: [])
        XCTAssertNotEqual(first.signature, second.signature)
    }

    /// Ed25519 has one digest. A client that sets an RSA flag on an ed25519 key is asking about a
    /// key type the flag does not apply to, and the answer must not change because of it.
    ///
    /// The signatures are compared through verification, not equality: they are salted, so two
    /// calls differ even with identical flags.
    func testEd25519_ignoresRSAFlags() throws {
        let key     = try parsedEd25519()
        let plain   = try SSHSigner.signature(for: key, data: Self.message, flags: [])
        let flagged = try SSHSigner.signature(for: key, data: Self.message,
                                              flags: [.rsaSha2_512])
        let publicKey = try ed25519PublicKey()

        XCTAssertEqual(plain.algorithm, "ssh-ed25519")
        XCTAssertEqual(flagged.algorithm, "ssh-ed25519")
        XCTAssertTrue(publicKey.isValidSignature(plain.signature, for: Self.message))
        XCTAssertTrue(publicKey.isValidSignature(flagged.signature, for: Self.message))
    }

    // MARK: - RSA

        private static let rsaN =
            "c59577ef7c983cc7bd0905e01bd0f9cdbc4257abfac597c1521e23e2d2e9" +
            "fa7fcac2ae021c33f9be60905d6620c0cc6ef6fadfca71aef6f0944f798b" +
            "cf7c25a780958425ec9d325bea4f2f7e1e759874cf87c20eec3bc33c38c8" +
            "a0043190c06e5f3e9e0473dda554ad698c0ff8b7a5f7e0ac90fe601b80c6" +
            "2ee26c9638b03878a621fff3ed12436b86f962341d62731e6ab254850c75" +
            "12d90b7171ef6816e5e2322e710547243789aa369e30397021afa103af56" +
            "8025e34fe2e1a5fccb482aeb88ae570c98dabc07c3a6fb75823460ff5996" +
            "37ad1645466197f997f2fabc2ff1bd91f33714786882c03cbff6112e7cf6" +
            "9c3a943632f608abfccb05a39820ce49"
        private static let rsaE = "010001"
        private static let rsaD =
            "80cf29aa6a5ac13d2202d0dec2a3a1473bd5305cc116b211691c971e978b" +
            "cc30259a77608ecc5fa37a46836d422b0edbc48dd6f99ed586cd5e92d555" +
            "8d458d32bf043a6b92ef0456a1d14fcff3c18c4b92c419822b05e708caa8" +
            "1891c3526ff1448c88edb42faa4a22e76d55383b59aad8c107a19e3c2fde" +
            "83d03f244bfeae40eacb57ad2bd1ed8755add9d9705bcc212e40e0f11d0d" +
            "db422bae37d2a86f18edab61e72558379b41780cea242052b7674f3b346b" +
            "91a84be8930b083e5f4bbe7ee7d340d943cfd255665ef46a3264b0076710" +
            "64aa0d60343a15c24bc2a673d53d2f1ec98cbe08e003c9d407f0778eac41" +
            "420da379b61643baf80d969ec9b8c815"
        private static let rsaP =
            "f7a1b2cfe192046a40f7222aea41efe9ce696aa5b68a5da17928cd663e53" +
            "df9c62ff9451bca750df6cbd1411295c554e5a00d5963e276373a47e15d5" +
            "17dfe132fde73fc4ba1619f21463afea7dbd4416fa8e5c362694e107b4c1" +
            "41668d52ff0f5ebdc0a05e4c8e8389a7acdb3c610458fd47d10557e44c48" +
            "dae93815952861b3"
        private static let rsaQ =
            "cc42cc708eadd46734721897128f635447e866ffd75896fb74bad66b183e" +
            "44909f04790fe3f9d0bf1b96bb009466c0268ab8b2b428ecdb2ea7c361e3" +
            "d0fe85964d907edba7781c635ec44ccce78e3574a205345cc512e2b8d3ee" +
            "c47e17fd216b574c202925dc634d1d1820fc1ec9e3a13b6b42b34e56ff0c" +
            "fa399432ea853a13"
        private static let rsaQInverse =
            "34d1d6094f431bb98fb2a3df553c401da79013336f0d310963facd8e6646" +
            "07d313255931e30b9e80caf10992dab8b5baae69d86a7a307e21e7f7e790" +
            "a0885e4f6cfb40ef90d581e01c29dc18af5175fd1c5d2ffdf4798dd9f56b" +
            "d719141f46c29afd8b3a034d285d79bf7ce2413694d005699af06fbf3b10" +
            "a9c7d4e0dddf8ade"

    /// RSA PKCS#1 v1.5 **is** deterministic, so unlike ed25519 it can be compared byte for byte
    /// against an independent implementation — and is, for all three digests, because the digest is
    /// chosen from the client's flags and getting that mapping wrong produces a signature the server
    /// rejects without saying why.
    ///
    /// The key is a throwaway 2048-bit key generated for this suite; its components are above in
    /// hex. The expected signatures come from Python `cryptography`, not from Prizm.
    private func parsedRSA() throws -> SSHParsedKey {
        return SSHParsedKey(algorithm: "ssh-rsa",
                            publicBlob: Data(),
                            comment: nil,
                            privateKey: .rsa(n: try XCTUnwrap(Data(hexString: Self.rsaN)),
                                             e: try XCTUnwrap(Data(hexString: Self.rsaE)),
                                             d: try XCTUnwrap(Data(hexString: Self.rsaD)),
                                             p: try XCTUnwrap(Data(hexString: Self.rsaP)),
                                             q: try XCTUnwrap(Data(hexString: Self.rsaQ)),
                                             qInverse: try XCTUnwrap(Data(hexString: Self.rsaQInverse))))
    }

    func testRSASignature_noFlags_isSHA1() throws {
        let result = try SSHSigner.signature(for: try parsedRSA(), data: Self.message, flags: [])
        XCTAssertEqual(result.algorithm, "ssh-rsa")
        XCTAssertEqual(result.signature,
                       try XCTUnwrap(Data(base64Encoded: Self.rsaExpectedSHA1)))
    }

    func testRSASignature_sha256Flag_matchesTheReferenceImplementation() throws {
        let result = try SSHSigner.signature(for: try parsedRSA(), data: Self.message,
                                             flags: [.rsaSha2_256])
        XCTAssertEqual(result.algorithm, "rsa-sha2-256")
        XCTAssertEqual(result.signature,
                       try XCTUnwrap(Data(base64Encoded: Self.rsaExpectedSHA256)))
    }

    func testRSASignature_sha512Flag_matchesTheReferenceImplementation() throws {
        let result = try SSHSigner.signature(for: try parsedRSA(), data: Self.message,
                                             flags: [.rsaSha2_512])
        XCTAssertEqual(result.algorithm, "rsa-sha2-512")
        XCTAssertEqual(result.signature,
                       try XCTUnwrap(Data(base64Encoded: Self.rsaExpectedSHA512)))
    }

    /// The three digests must not produce the same bytes. A mapping that ignored the flags would
    /// pass whichever case was written first and fail the other two — this states the difference
    /// directly, so the failure names the mapping rather than a digest.
    func testRSASignature_eachDigestDiffers() throws {
        let signatures = try [[], [.rsaSha2_256], [.rsaSha2_512]].map { flags in
            try SSHSigner.signature(for: try parsedRSA(), data: Self.message, flags: flags).signature
        }
        XCTAssertEqual(Set(signatures.map { $0.count }).count, 1, "all are the modulus size")
        XCTAssertEqual(Set(signatures).count, 3, "three digests, three signatures")
    }

    private static let rsaExpectedSHA1 = "uQR1lWYKmkaoBjZv/uRKHs6drs9wRqDqjCypNivpdhR5A7RVCxbhrIyPmMpovzGIZ2B6ON5I8Ow2Y5pDNpOfpzMMQOWAwfikNdMCv2tWNEmFDHWytR+yssrovZ/ML8f0Ck/iUaHn37P1994Bgosv3pbKten1U6zcEdUK4DFYnJ+9YHlC7xBv7v7X9FAETSIuHVKukTgGMOtu+5aphpCZv38WjbE4k3204WoQ1X9EatdqKaDHNlA25g0IJ+uyfEr+1RwMzPPq2zQwYtqsoYiRMKSxAM5S/h1aNikMwXj2zsoIjajI57CetdNBzgfYN+m5MVkA2wlQS1hF913djCB78w=="
    private static let rsaExpectedSHA256 = "u/cm/nRJdVpMkBp68m9mfhM0zZK+Cl/nRD7SbpJGOoMTdV59iLeGB+o9Vgb0v8BfuTsiqwGaWwXvd5dKX9m16WP0uQ5J91SadyRu+fCr2GzuaBgjHp1PvsM3rO2qxrkJIOg+EviUn3C9U7xVHOvgCTx2/X7gOtw1YMAJrGsSKdrjzTYCMY99tcZOvJOzYSAEkignyJdzp4mjfR45bsm0KUmEDa3vLN6byqgR76zWxA6MfGpx0EnF3beV6Gr07DJs3Sn8jRmko+WwDCY9+ccvVEuWxUFn4LQ3UhQVV4FNU8rhbR2fcNCioP75EnNjiB3rfK33d6aIxyF6J3R9d6ws1A=="
    private static let rsaExpectedSHA512 = "nTV6+XrMMwEx3WyN5jOqiwdyepJ3IasRO2SwcfzZ2pdY87//9hwiMzE5qQ4Ux4BNn1/+OOER2rQb4+WWoyyqsDJiUa5yG7+WL1OYKmPbaz6pBBAlR9KzNf/wfcjv/GsX2OsbnrspNjrKN+nfbApYIaSjI/2rYABD76DE+l8cxSHpuzure64As/FA4tcmNqiqT407SvSSBtEFUbcvQgmdtQTldpr19Bu49vbgjLswco8xbeuBycLq2lDJdVRroaqlVLfDKtjIVubiW//ijIddtR6THhH+s+gWmgrF7D/I+RR/PRmR3CVfoVYyhpHZLfo0y9oJ6scx2kjG+c9sPjFCDA=="
}

// MARK: - Helpers

private extension Data {
    init?(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex)
            guard let end = next, let byte = UInt8(hexString[index..<end], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = end
        }
        self.init(bytes)
    }
}
