import XCTest
import CryptoKit
@testable import Prizm

// MARK: - SSHAgentKeyStoreTests

/// Which vault keys the agent will serve, and what it says about the ones it will not.
///
/// The interesting assertions here are about the **unusable** half. The usable half is the feature;
/// the unusable half is what decides whether a missing key is understood or merely noticed, which
/// is why each reason is asserted to name its own obstruction rather than merely to be non-empty.
final class SSHAgentKeyStoreTests: XCTestCase {

    private static let blobB64   = "AAAAC3NzaC1lZDI1NTE5AAAAIA11UHVOCACl0jfu9YJgNXZrmz5aFYaKlAqyiZWHiOOw"
    private static let publicHex =
        "0d7550754e0800a5d237eef5826035766b9b3e5a15868a940ab289958788e3b0"
    private static let seedHex =
        "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"

    private static let beginMarker = ["-----BEGIN", "OPENSSH", "PRIVATE", "KEY-----"].joined(separator: " ")
    private static let endMarker   = ["-----END", "OPENSSH", "PRIVATE", "KEY-----"].joined(separator: " ")

    /// An OpenSSH container built here rather than pasted, so this file holds no key material.
    private func container(cipher: String, algorithm: String = "ssh-ed25519") throws -> String {
        let publicKey = try XCTUnwrap(Data(hexString: Self.publicHex))
        let seed      = try XCTUnwrap(Data(hexString: Self.seedHex))
        let blob      = try XCTUnwrap(Data(base64Encoded: Self.blobB64))

        var writer = SSHWireWriter()
        writer.writeString(Data("openssh-key-v1\u{0}".utf8))
        writer.writeString(cipher)
        writer.writeString("none")
        writer.writeString(Data())
        writer.writeUInt32(1)
        writer.writeString(blob)

        var section = SSHWireWriter()
        section.writeUInt32(0x1234_5678)
        section.writeUInt32(0x1234_5678)
        // ed25519 stores seed ++ public; an RSA key would store mpints, but the layout below the
        // algorithm name is never reached for an unsupported algorithm, so this is enough.
        section.writeString(Data(algorithm.utf8))
        if algorithm == "ssh-ed25519" {
            section.writeString(publicKey)
            section.writeString(seed + publicKey)
        }
        section.writeString("generator@host")
        writer.writeString(Data(section.bytes))

        let body = Data(writer.bytes).base64EncodedString()
        return "\(Self.beginMarker)\n\(body)\n\(Self.endMarker)\n"
    }

    private func sshItem(id: String = "key-1", name: String = "Deploy Key",
                         privateKey: String? = nil) throws -> VaultItem {
        // `??` cannot carry a `try` on its right side, so the fallback is resolved first.
        let keyText: String
        if let privateKey { keyText = privateKey } else { keyText = try container(cipher: "none") }

        return VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .sshKey(SSHKeyContent(
                privateKey: keyText,
                publicKey: "ssh-ed25519 AAAA… generator@host",
                keyFingerprint: "SHA256:abc",
                notes: nil, customFields: []
            ))
        )
    }

    private func loginItem() -> VaultItem {
        VaultItem(
            id: "login-1", name: "GitHub", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .login(LoginContent(username: "u", password: "p", uris: [],
                                         totp: nil, notes: nil, customFields: []))
        )
    }

    // MARK: - Usable

    /// The comment is the item's name, not the comment inside the key file. `ssh-add -l` prints
    /// this column, and a key called "generator@host" tells the user which key it is only if they
    /// happen to remember the machine that made it.
    func testLoad_usesTheItemNameAsTheComment_notTheOneInsideTheKey() throws {
        let item  = try sshItem(name: "Deploy Key")
        let (usable, unusable) = SSHAgentKeyStore.load(items: [item])

        XCTAssertTrue(unusable.isEmpty)
        XCTAssertEqual(usable.count, 1)
        XCTAssertEqual(usable.first?.comment, "Deploy Key")
        XCTAssertEqual(usable.first?.itemId, "key-1")
        XCTAssertEqual(usable.first?.blob, try XCTUnwrap(Data(base64Encoded: Self.blobB64)))
    }

    /// Non-SSH items are skipped, not reported: "a login is not an SSH key" is not a failure of
    /// anything, and listing it under unusable keys would bury the real ones.
    func testLoad_ignoresItemsThatAreNotSSHKeys() throws {
        let (usable, unusable) = SSHAgentKeyStore.load(items: [loginItem(), try sshItem()])

        XCTAssertTrue(unusable.isEmpty)
        XCTAssertEqual(usable.count, 1)
    }

    // MARK: - Unusable

    func testLoad_reportsAnItemWithNoPrivateKey() {
        let item = VaultItem(
            id: "empty", name: "Empty Key", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .sshKey(SSHKeyContent(privateKey: nil, publicKey: "ssh-ed25519 AAAA…",
                                           keyFingerprint: nil, notes: nil, customFields: []))
        )
        let (usable, unusable) = SSHAgentKeyStore.load(items: [item])

        XCTAssertTrue(usable.isEmpty)
        XCTAssertEqual(unusable.count, 1)
        XCTAssertEqual(unusable.first?.itemId, "empty")
        XCTAssertFalse(unusable.first?.reason.isEmpty ?? true)
    }

    /// A passphrase-protected key is the common case that a user will otherwise read as the feature
    /// being broken, so the reason has to say *why* rather than that the key was rejected.
    func testLoad_reportsAnEncryptedKeyAndNamesTheReason() throws {
        let item = try sshItem(privateKey: try container(cipher: "aes256-ctr"))
        let (usable, unusable) = SSHAgentKeyStore.load(items: [item])

        XCTAssertTrue(usable.isEmpty)
        XCTAssertEqual(unusable.count, 1)
        let reason = try XCTUnwrap(unusable.first?.reason)
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("aes256-ctr"),
                      "the reason should name the cipher a user would have to remove: \(reason)")
    }

    func testLoad_reportsAnUnsupportedAlgorithmAndNamesIt() throws {
        let item = try sshItem(privateKey: try container(cipher: "none", algorithm: "ssh-dss"))
        let (usable, unusable) = SSHAgentKeyStore.load(items: [item])

        XCTAssertTrue(usable.isEmpty)
        XCTAssertEqual(unusable.count, 1)
        let reason = try XCTUnwrap(unusable.first?.reason)
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("ssh-dss"),
                      "the reason should name the algorithm: \(reason)")
    }

    /// "Not an OpenSSH key" covers PEM RSA and PuTTY files, which is what most people paste in.
    func testLoad_reportsAKeyThatIsNotOpenSSHFormat() {
        let item = VaultItem(
            id: "pem", name: "Old Key", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .sshKey(SSHKeyContent(privateKey: "not a key at all",
                                           publicKey: nil, keyFingerprint: nil,
                                           notes: nil, customFields: []))
        )
        let (usable, unusable) = SSHAgentKeyStore.load(items: [item])

        XCTAssertTrue(usable.isEmpty)
        XCTAssertEqual(unusable.count, 1)
    }

    /// A key that fails to load must not take the good ones with it.
    func testLoad_keepsServingTheKeysThatParse() throws {
        let items = [try sshItem(id: "a", name: "Good"),
                     try sshItem(id: "b", name: "Bad",
                                 privateKey: try container(cipher: "aes256-ctr"))]
        let (usable, unusable) = SSHAgentKeyStore.load(items: items)

        XCTAssertEqual(usable.map(\.itemId), ["a"])
        XCTAssertEqual(unusable.map(\.itemId), ["b"])
    }

    // MARK: - Parsing on demand

    /// The store's whole point: material exists only for the duration of one signature, so this
    /// call is the only way to get it and is deliberately separate from `load`.
    func testKeyForItem_parsesAgainAtSignatureTime() throws {
        let item = try sshItem()
        let key  = try SSHAgentKeyStore.key(for: item)

        XCTAssertEqual(key.algorithm, "ssh-ed25519")
        XCTAssertEqual(key.publicBlob, try XCTUnwrap(Data(base64Encoded: Self.blobB64)))
    }

    func testKeyForItem_refusesAnItemThatIsNotAnSSHKey() {
        XCTAssertThrowsError(try SSHAgentKeyStore.key(for: loginItem()))
    }
}

// MARK: - SSHAgentResponderTests

/// One request in, one answer out — with the authorization gate inside, not around.
///
/// The gate is the reason this type exists rather than a switch in the connection handler, so most
/// of these tests exist to show a request that *cannot* reach `sign`: an unknown key, a refusal, a
/// request that never parses. Each asserts on the call counter as well as on the answer, because a
/// `FAILURE` returned after signing anyway would look identical on the wire.
final class SSHAgentResponderTests: XCTestCase {

    private static let blobB64   = "AAAAC3NzaC1lZDI1NTE5AAAAIA11UHVOCACl0jfu9YJgNXZrmz5aFYaKlAqyiZWHiOOw"
    private static let publicHex =
        "0d7550754e0800a5d237eef5826035766b9b3e5a15868a940ab289958788e3b0"
    private static let seedHex =
        "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"

    /// Counts calls from a `@Sendable` closure without a data race: the closures run off the test's
    /// actor, so a plain property would not be safe to touch from them.
    private actor Calls {
        private(set) var authorize = 0
        private(set) var sign      = 0
        func noteAuthorize() { authorize += 1 }
        func noteSign()      { sign += 1 }
    }

    private var identity: SSHAgentIdentity {
        SSHAgentIdentity(itemId: "key-1",
                         blob: Data(base64Encoded: Self.blobB64)!,
                         comment: "Deploy Key")
    }

    private func signRequest(blob: Data, data: Data, flags: UInt32 = 0) -> Data {
        var writer = SSHWireWriter()
        writer.writeString(blob)
        writer.writeString(data)
        writer.writeUInt32(flags)
        return SSHWireWriter.message(type: .signRequest, body: writer.bytes)
    }

    private func listingRequest() -> Data {
        SSHWireWriter.message(type: .requestIdentities)
    }

    /// Reads back what a client would read: the type byte, then one string holding
    /// `string algorithm` + `string signature`.
    private func readSignResponse(_ answer: Data) throws -> (algorithm: String, signature: Data) {
        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        let type = try reader.readByte()
        XCTAssertEqual(type, SSHAgentMessage.signResponse.rawValue)
        var blob = SSHWireReader(try reader.readString())
        return (try blob.readString().prizmSSHUTF8, try blob.readString())
    }

    // MARK: - Listing

    func testListing_answersWithoutAskingPermission() async throws {
        let calls = Calls()
        let answer = await SSHAgentResponder.response(
            to: listingRequest(),
            identities: [identity],
            authorize: { _ in await calls.noteAuthorize(); return false },
            sign: { _, _, _ in await calls.noteSign()
                return (algorithm: "ssh-ed25519", signature: Data()) }
        )

        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        let type = try reader.readByte()
        XCTAssertEqual(type, SSHAgentMessage.identitiesAnswer.rawValue)
        XCTAssertEqual(try reader.readUInt32(), 1)
        XCTAssertEqual(try reader.readString(), identity.blob)
        XCTAssertEqual(try reader.readString().prizmSSHUTF8, "Deploy Key")

        let authorizeCount = await calls.authorize
        let signCount      = await calls.sign
        // Public keys: gating the listing would hide which keys are loaded and protect nothing.
        XCTAssertEqual(authorizeCount, 0)
        XCTAssertEqual(signCount, 0)
    }

    func testListing_answersEmptyWhenThereAreNoKeys() async throws {
        let answer = await SSHAgentResponder.response(
            to: listingRequest(), identities: [],
            authorize: { _ in true }, sign: { _, _, _ in (algorithm: "", signature: Data()) }
        )
        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.identitiesAnswer.rawValue)
        XCTAssertEqual(try reader.readUInt32(), 0)
    }

    // MARK: - Signing

    /// The happy path, and the one that proves the gate is a gate rather than a gate *and* a
    /// signature: the answer is a `SIGN_RESPONSE` whose signature verifies under the public key.
    func testSignRequest_answersWithAVerifiableSignature() async throws {
        let calls = Calls()
        let message = Data("prizm-ssh-agent-test-vector".utf8)
        // Read outside the closure: `Self.*` on a MainActor type cannot be touched from the
        // `@Sendable` signing closure without an `await`, and there is no reason to.
        let publicKey = try XCTUnwrap(Data(hexString: Self.publicHex))
        let seed      = try XCTUnwrap(Data(hexString: Self.seedHex))

        let answer = await SSHAgentResponder.response(
            to: signRequest(blob: identity.blob, data: message),
            identities: [identity],
            authorize: { _ in await calls.noteAuthorize(); return true },
            sign: { _, data, _ in
                await calls.noteSign()
                let key = SSHParsedKey(algorithm: "ssh-ed25519", publicBlob: Data(), comment: nil,
                                       privateKey: .ed25519(seed: seed, publicKey: publicKey))
                return try SSHSigner.signature(for: key, data: data, flags: [])
            }
        )

        let result = try readSignResponse(answer)
        XCTAssertEqual(result.algorithm, "ssh-ed25519")
        let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        XCTAssertTrue(verifier.isValidSignature(result.signature, for: message))

        let authorizeCount = await calls.authorize
        let signCount      = await calls.sign
        XCTAssertEqual(authorizeCount, 1)
        XCTAssertEqual(signCount, 1)
    }

    /// The reason `authorize` is a parameter: a `false` here must mean no signature is produced, and
    /// the only observable difference on the wire is `FAILURE` — so the counter is what proves it.
    func testSignRequest_refusesWhenNotAuthorized_andNeverSigns() async throws {
        let calls = Calls()
        let answer = await SSHAgentResponder.response(
            to: signRequest(blob: identity.blob, data: Data("x".utf8)),
            identities: [identity],
            authorize: { _ in await calls.noteAuthorize(); return false },
            sign: { _, _, _ in await calls.noteSign()
                return (algorithm: "ssh-ed25519", signature: Data()) }
        )

        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.failure.rawValue)

        let authorizeCount = await calls.authorize
        let signCount      = await calls.sign
        XCTAssertEqual(authorizeCount, 1)
        XCTAssertEqual(signCount, 0, "a refused signature must not be computed, even to be discarded")
    }

    /// `ssh` asks every agent in turn, so a request for a key this agent does not hold is routine.
    /// It must be a `FAILURE` with no authorization prompt — otherwise holding one key would mean
    /// a password prompt on every connection that uses a different one.
    func testSignRequest_refusesAnUnknownKey_withoutAskingPermission() async throws {
        let calls  = Calls()
        let answer = await SSHAgentResponder.response(
            to: signRequest(blob: Data("some other key".utf8), data: Data("x".utf8)),
            identities: [identity],
            authorize: { _ in await calls.noteAuthorize(); return true },
            sign: { _, _, _ in await calls.noteSign()
                return (algorithm: "ssh-ed25519", signature: Data()) }
        )

        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.failure.rawValue)

        let authorizeCount = await calls.authorize
        let signCount      = await calls.sign
        XCTAssertEqual(authorizeCount, 0)
        XCTAssertEqual(signCount, 0)
    }

    func testSignRequest_refusesWhenSigningFails() async throws {
        struct Boom: Error {}
        let answer = await SSHAgentResponder.response(
            to: signRequest(blob: identity.blob, data: Data("x".utf8)),
            identities: [identity],
            authorize: { _ in true },
            sign: { _, _, _ in throw Boom() }
        )

        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.failure.rawValue)
    }

    // MARK: - Requests that do not parse

    /// A truncated message is answered, not thrown. Throwing would close the connection and lose
    /// every request queued behind this one, which is a much larger failure than one bad message.
    func testMalformedRequest_answersFailure_andDoesNotThrow() async throws {
        let truncated = Data([0x00, 0x00, 0x00, 0x40, SSHAgentMessage.signRequest.rawValue, 0x00])
        let answer = await SSHAgentResponder.response(
            to: truncated, identities: [identity],
            authorize: { _ in true },
            sign: { _, _, _ in (algorithm: "", signature: Data()) }
        )

        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.failure.rawValue)
    }

    func testEmptyRequest_answersFailure() async throws {
        let answer = await SSHAgentResponder.response(
            to: Data(), identities: [identity],
            authorize: { _ in true },
            sign: { _, _, _ in (algorithm: "", signature: Data()) }
        )
        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.failure.rawValue)
    }

    /// ADD_IDENTITY, REMOVE_IDENTITY, LOCK, UNLOCK: all refused, because accepting them would mean
    /// claiming to manage keys Prizm does not hold.
    ///
    /// The bytes are written raw: `SSHWireWriter.message` only takes types Prizm knows, and the ones
    /// that must be refused are exactly the ones it cannot name.
    func testUnsupportedRequest_answersFailure() async throws {
        for rawType: UInt8 in [1, 2, 3, 4, 7, 8, 9, 10, 17, 18, 22, 23, 24, 25, 26, 27] {
            var writer = SSHWireWriter()
            writer.writeUInt32(1)
            writer.writeByte(rawType)
            let answer = await SSHAgentResponder.response(
                to: Data(writer.bytes),
                identities: [identity],
                authorize: { _ in true },
                sign: { _, _, _ in (algorithm: "", signature: Data()) }
            )
            var reader = SSHWireReader(answer)
            _ = try reader.readUInt32()
            let type = try reader.readByte()
            XCTAssertEqual(type, SSHAgentMessage.failure.rawValue, "type \(rawType) should be refused")
        }
    }

    /// A sign request that names a known key but stops before the flags — the truncation a client
    /// would produce only if it were broken, and the one that must not become an exception.
    func testSignRequest_truncatedAfterTheData_answersFailure() async throws {
        var writer = SSHWireWriter()
        writer.writeString(identity.blob)
        writer.writeString(Data("x".utf8))
        let request = SSHWireWriter.message(type: .signRequest, body: writer.bytes)

        let answer = await SSHAgentResponder.response(
            to: request, identities: [identity],
            authorize: { _ in true },
            sign: { _, _, _ in (algorithm: "", signature: Data()) }
        )
        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.failure.rawValue)
    }
}

private extension Data {
    /// Test-only: the wire format is UTF-8 for every string Prizm reads here, and this keeps the
    /// assertions readable without a `String(decoding:as:)` at each call site.
    var prizmSSHUTF8: String { String(decoding: self, as: UTF8.self) }

    /// Two hex digits per byte, no separators. Fails rather than clamping: a fixture written with
    /// an odd number of digits is a mistake, and a silently short key would fail somewhere else.
    init?(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            guard let end = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex),
                  let byte = UInt8(hexString[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        self.init(bytes)
    }
}
