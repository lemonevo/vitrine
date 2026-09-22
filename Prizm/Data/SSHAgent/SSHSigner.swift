import CryptoKit
import Foundation
import Security

// MARK: - SSHSigner

/// Produces the signature blob a client asked for.
///
/// The result is the value that goes inside a `string` in the agent's sign response, not the whole
/// response: the nesting is `string (string algorithm || string signature)`, and building it here
/// would put encoding in the wrong place.
nonisolated enum SSHSigner {

    /// - Returns: the algorithm name and the raw signature. The algorithm name is part of the
    ///   answer because it is chosen here — for RSA it depends on what the client asked for.
    static func signature(for key: SSHParsedKey,
                          data: Data,
                          flags: SSHAgentSignFlags) throws -> (algorithm: String, signature: Data) {
        switch key.privateKey {
        case .ed25519(let seed, _):
            return try ed25519Signature(seed: seed, data: data)
        case .rsa(let n, let e, let d, let p, let q, let qInverse):
            return try rsaSignature(n: n, e: e, d: d, p: p, q: q, qInverse: qInverse,
                                    data: data, flags: flags)
        }
    }

    // MARK: - Ed25519

    /// Ed25519 has one digest, so the flags are not consulted — a client that sets RSA flags on an
    /// Ed25519 key is asking about a key type they do not apply to.
    private static func ed25519Signature(seed: Data, data: Data) throws -> (String, Data) {
        var seedBytes = seed
        defer { seedBytes.zeroize() }

        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seedBytes)
        } catch {
            throw SSHSignerError.unusableKey("ed25519 seed")
        }
        var signature = try privateKey.signature(for: data)
        defer { signature.zeroize() }
        return ("ssh-ed25519", signature)
    }

    // MARK: - RSA

    private static func rsaSignature(n: Data, e: Data, d: Data, p: Data, q: Data, qInverse: Data,
                                     data: Data,
                                     flags: SSHAgentSignFlags) throws -> (String, Data) {
        let algorithm = rsaAlgorithm(for: flags)

        // The Chinese-remainder exponents OpenSSH's format leaves out.
        let dP = SSHBigUInt.data(SSHBigUInt.modulo(SSHBigUInt.magnitude(of: d),
                                                   SSHBigUInt.decrement(SSHBigUInt.magnitude(of: p))))
        let dQ = SSHBigUInt.data(SSHBigUInt.modulo(SSHBigUInt.magnitude(of: d),
                                                   SSHBigUInt.decrement(SSHBigUInt.magnitude(of: q))))
        defer { var a = dP; a.zeroize(); var b = dQ; b.zeroize() }

        var pkcs1 = Self.pkcs1(n: n, e: e, d: d, p: p, q: q, dP: dP, dQ: dQ, qInverse: qInverse)
        defer { pkcs1.zeroize() }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType:  kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            throw SSHSignerError.unusableKey(error?.takeRetainedValue().localizedDescription ?? "RSA")
        }

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secKey, algorithm.secKeyAlgorithm,
                                                    data as CFData, &signError) as Data? else {
            throw SSHSignerError.signingFailed(signError?.takeRetainedValue().localizedDescription ?? "")
        }
        return (algorithm.name, signature)
    }

    /// Which RSA variant the client asked for.
    ///
    /// `ssh-rsa` is SHA-1 and is the fallback for servers that predate `rsa-sha2-*`. Refusing it
    /// would make those servers unreachable with an error that names the agent rather than the
    /// server, so it is answered — and it is the only SHA-1 signature Prizm produces.
    private static func rsaAlgorithm(for flags: SSHAgentSignFlags) -> (name: String, secKeyAlgorithm: SecKeyAlgorithm) {
        if flags.contains(.rsaSha2_512) {
            return ("rsa-sha2-512", .rsaSignatureMessagePKCS1v15SHA512)
        }
        if flags.contains(.rsaSha2_256) {
            return ("rsa-sha2-256", .rsaSignatureMessagePKCS1v15SHA256)
        }
        return ("ssh-rsa", .rsaSignatureMessagePKCS1v15SHA1)
    }

    // MARK: - PKCS#1 assembly

    /// The `RSAPrivateKey` structure from RFC 8017 appendix A.1.2.
    ///
    /// `version` is 0 for a two-prime key. `dP` and `dQ` are the only fields not present in the
    /// OpenSSH container, and `qInverse` is stored there as `iqmp`.
    private static func pkcs1(n: Data, e: Data, d: Data, p: Data, q: Data,
                              dP: Data, dQ: Data, qInverse: Data) -> Data {
        var body = Data()
        body.append(derInteger(Data([0])))          // version
        body.append(derInteger(n))
        body.append(derInteger(e))
        body.append(derInteger(d))
        body.append(derInteger(p))
        body.append(derInteger(q))
        body.append(derInteger(dP))
        body.append(derInteger(dQ))
        body.append(derInteger(qInverse))

        var out = Data([0x30])
        out.append(derLength(body.count))
        out.append(body)
        return out
    }

    /// A DER INTEGER: minimal two's complement, so a leading zero is added when the high bit is set
    /// and removed when it is not. RSA moduli always need the added byte; the exponent 65537 does
    /// not, and getting either wrong produces a key the Security framework silently refuses.
    private static func derInteger(_ magnitude: Data) -> Data {
        var value = SSHBigUInt.magnitude(of: magnitude)
        if value.isEmpty { value = [0] }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }

        var out = Data([0x02])
        out.append(derLength(value.count))
        out.append(contentsOf: value)
        return out
    }

    private static func derLength(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([UInt8(0x80 | bytes.count)]) + Data(bytes)
    }
}

// MARK: - SSHSignerError

nonisolated enum SSHSignerError: Error, LocalizedError {
    /// The key parsed but could not be turned into something that signs.
    case unusableKey(String)
    /// The key was fine and the signature failed.
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unusableKey:
            return L("Vitrine could not use this SSH key.")
        case .signingFailed:
            return L("Vitrine could not sign with this SSH key.")
        }
    }
}
