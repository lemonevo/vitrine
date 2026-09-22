import Foundation

// MARK: - SSHParsedKey

/// A usable SSH key parsed out of its stored form.
///
/// `publicBlob` is the SSH wire encoding of the public key — the value the agent protocol uses to
/// identify a key, and the only part of this that is ever sent anywhere.
nonisolated struct SSHParsedKey {
    /// The SSH algorithm name, e.g. `ssh-ed25519`.
    let algorithm:  String
    let publicBlob: Data
    /// The comment stored inside the key file. Used only as a fallback; the agent reports the
    /// vault item's name instead, for the reason given in the spec.
    let comment:    String?
    let privateKey: SSHPrivateKeyMaterial
}

// MARK: - SSHPrivateKeyMaterial

/// The private half, in the shape each algorithm needs.
///
/// Held as raw big-endian bytes rather than as a `SecKey`, because the lifetime that matters is the
/// signature's: the material is parsed per request and discarded after it, and a `SecKey` would
/// outlive that and be harder to reason about.
nonisolated enum SSHPrivateKeyMaterial {
    /// The 32-byte seed. Ed25519's stored "private key" is 64 bytes — the seed followed by a copy
    /// of the public key — and only the first half is the secret.
    case ed25519(seed: Data, publicKey: Data)
    case rsa(n: Data, e: Data, d: Data, p: Data, q: Data, qInverse: Data)
}

// MARK: - OpenSSHPrivateKey

/// Parses the `openssh-key-v1` container `ssh-keygen` writes.
///
/// The layout was confirmed by decoding real keys rather than from a description of them: the
/// private section for ed25519 is `public(32) || private(64) || comment`, where the second half of
/// the 64-byte private field is the public key again; for RSA it is
/// `n, e, d, qInv, p, q, comment`, in that order — note `qInv` comes **before** `p` and `q`, which
/// is the order `sshkey_private_serialize` uses and not the order a reader might assume.
nonisolated enum OpenSSHPrivateKey {

    private static let beginMarker = "-----BEGIN OPENSSH PRIVATE KEY-----"
    private static let endMarker   = "-----END OPENSSH PRIVATE KEY-----"
    private static let magic       = "openssh-key-v1\u{0}"

    /// - Throws: `OpenSSHKeyError`. Every failure names what it found, because the caller's job is
    ///   to tell the user why a key is not offered — "unsupported" alone leaves them to guess.
    static func parse(_ text: String) throws -> SSHParsedKey {
        guard let begin = text.range(of: beginMarker),
              let end   = text.range(of: endMarker),
              begin.lowerBound < end.lowerBound else {
            // Anything else is a key in a format this parser does not read. Naming the marker that
            // *was* found turns "unsupported" into something the user can act on.
            throw OpenSSHKeyError.notOpenSSHFormat(markerFound: Self.otherMarker(in: text))
        }

        let body = String(text[begin.upperBound..<end.lowerBound])
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard var decoded = Data(base64Encoded: body) else {
            throw OpenSSHKeyError.malformed("base64")
        }
        defer { decoded.zeroize() }

        var reader = SSHWireReader(decoded)

        guard let header = try? reader.readString(),
              String(decoding: header, as: UTF8.self) == magic else {
            throw OpenSSHKeyError.malformed("magic")
        }

        let cipherName = try reader.readString()
        let cipher     = String(decoding: cipherName, as: UTF8.self)
        guard cipher == "none" else {
            throw OpenSSHKeyError.encrypted(cipher: cipher)
        }
        // kdfname and kdfoptions are read and ignored: they are "none"/empty whenever the cipher is,
        // but the offsets have to be consumed to reach the keys.
        _ = try reader.readString()
        _ = try reader.readString()

        let keyCount = try reader.readUInt32()
        guard keyCount >= 1 else { throw OpenSSHKeyError.malformed("no keys") }

        let storedPublicBlob = try reader.readString()
        var privateSection   = try reader.readString()
        defer { privateSection.zeroize() }

        var section = SSHWireReader(privateSection)
        // Two copies of the same random integer, which OpenSSH compares to detect a wrong
        // passphrase. With no cipher it is instead a cheap integrity check on the container.
        let check1 = try section.readUInt32()
        let check2 = try section.readUInt32()
        guard check1 == check2 else { throw OpenSSHKeyError.malformed("checkint") }

        let algorithmName = try section.readString()
        let algorithm     = String(decoding: algorithmName, as: UTF8.self)

        switch algorithm {
        case "ssh-ed25519":
            return try parseEd25519(algorithm:  algorithm,
                                    section:    &section,
                                    publicBlob: storedPublicBlob)
        case "ssh-rsa":
            return try parseRSA(algorithm:  algorithm,
                                section:    &section,
                                publicBlob: storedPublicBlob)
        default:
            throw OpenSSHKeyError.unsupportedAlgorithm(algorithm)
        }
    }

    // MARK: - Per-algorithm

    private static func parseEd25519(algorithm:  String,
                                     section:    inout SSHWireReader,
                                     publicBlob: Data) throws -> SSHParsedKey {
        var publicKey  = try section.readString()
        var privateKey = try section.readString()
        let comment    = try? section.readString()

        defer { privateKey.zeroize() }

        guard publicKey.count == 32 else { throw OpenSSHKeyError.malformed("ed25519 public") }
        // The stored private value is seed || public. Both halves have to agree with the public key,
        // otherwise this is not the key the container claims to hold.
        guard privateKey.count == 64,
              privateKey.suffix(32) == publicKey else {
            throw OpenSSHKeyError.malformed("ed25519 private")
        }

        let expected = Self.ed25519Blob(publicKey: publicKey)
        guard expected == publicBlob else { throw OpenSSHKeyError.malformed("ed25519 blob") }

        let seed = privateKey.prefix(32)
        return SSHParsedKey(algorithm:  algorithm,
                            publicBlob: expected,
                            comment:    comment.flatMap { String(decoding: $0, as: UTF8.self) },
                            privateKey: .ed25519(seed: Data(seed), publicKey: publicKey))
    }

    private static func parseRSA(algorithm:  String,
                                 section:    inout SSHWireReader,
                                 publicBlob: Data) throws -> SSHParsedKey {
        var n     = try section.readMPInt()
        var e     = try section.readMPInt()
        var d     = try section.readMPInt()
        let qInv  = try section.readMPInt()
        var p     = try section.readMPInt()
        var q     = try section.readMPInt()
        let comment = try? section.readString()

        defer { d.zeroize(); p.zeroize(); q.zeroize() }

        let expected = Self.rsaBlob(e: e, n: n)
        guard expected == publicBlob else { throw OpenSSHKeyError.malformed("rsa blob") }

        return SSHParsedKey(algorithm:  algorithm,
                            publicBlob: expected,
                            comment:    comment.flatMap { String(decoding: $0, as: UTF8.self) },
                            privateKey: .rsa(n: n, e: e, d: d, p: p, q: q, qInverse: qInv))
    }

    // MARK: - Public blobs

    /// `string "ssh-ed25519"` + `string public key`.
    private static func ed25519Blob(publicKey: Data) -> Data {
        var writer = SSHWireWriter()
        writer.writeString("ssh-ed25519")
        writer.writeString(publicKey)
        return Data(writer.bytes)
    }

    /// `string "ssh-rsa"` + `mpint e` + `mpint n`, in that order — e first, which is the order the
    /// protocol uses and the reverse of the order the numbers appear in a key file.
    private static func rsaBlob(e: Data, n: Data) -> Data {
        var writer = SSHWireWriter()
        writer.writeString("ssh-rsa")
        writer.writeMPInt(e)
        writer.writeMPInt(n)
        return Data(writer.bytes)
    }

    // MARK: - Diagnostics

    /// The PEM marker a non-OpenSSH key does have, so the error can name it.
    private static func otherMarker(in text: String) -> String? {
        guard let begin = text.range(of: "-----BEGIN "),
              let end   = text.range(of: "-----",
                                     range: begin.upperBound..<text.endIndex) else { return nil }
        return String(text[begin.upperBound..<end.lowerBound])
    }
}

// MARK: - OpenSSHKeyError

nonisolated enum OpenSSHKeyError: Error, LocalizedError {
    /// A key Prizm has no passphrase for. Prizm stores none, so there is no way to use it.
    case encrypted(cipher: String)
    /// A key whose algorithm Prizm does not implement.
    case unsupportedAlgorithm(String)
    /// Not an `openssh-key-v1` container at all.
    case notOpenSSHFormat(markerFound: String?)
    /// Something inside the container did not add up.
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .encrypted:
            return L("This key is protected with a passphrase. Vitrine does not store one for an SSH key, so it cannot use this key.")
        case .unsupportedAlgorithm(let algorithm):
            return L("Vitrine cannot use %@ keys.", algorithm)
        case .notOpenSSHFormat:
            return L("This is not an OpenSSH private key. Vitrine reads the OpenSSH format ssh-keygen writes.")
        case .malformed:
            return L("This SSH key could not be read.")
        }
    }

    /// Why the key is not offered, for Settings. Distinct from `errorDescription` because that one
    /// is written for someone holding the key file, and this is written for someone looking at a
    /// vault item and wondering why it is not in the agent.
    var reason: String { errorDescription ?? "" }
}
