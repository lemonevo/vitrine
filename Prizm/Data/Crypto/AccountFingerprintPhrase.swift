import CryptoKit
import Foundation

// MARK: - AccountFingerprintPhrase

/// The five-word phrase Bitwarden clients show so a user can confirm two clients are on the same
/// account.
///
/// **This type exists to be identical to another program's output.** A phrase that is merely
/// plausible is worse than none, because the only thing it is for is being compared against what
/// another client displays. Everything here was read out of the reference implementation
/// (`bitwarden/sdk-internal`, `crates/bitwarden-crypto/src/fingerprint.rs`) rather than derived
/// from what seemed reasonable, and the tests are known-answer vectors from that implementation
/// rather than values this code produced.
///
/// The algorithm, in the order it runs:
///
/// 1. `okm = HKDF-Expand-SHA256(prk: SHA256(publicKey), info: userId, length: 32)`
/// 2. the 32 bytes are read as one big-endian integer
/// 3. five words are taken from the **least significant** end: `word = n % 7776; n /= 7776`
/// 4. joined with `-`
///
/// Three details are load-bearing and each one is easy to get wrong:
///
/// - **The material is the user id, not the email.** The reference's own unit test uses a
///   plausible-looking email, which is a mock value; the call site in the web vault sets
///   `fingerprintMaterial` to the user id.
/// - **The public key is hashed as the SPKI DER encoding**, not as PKCS#1. On Apple platforms
///   `SecKeyCopyExternalRepresentation` returns PKCS#1 for RSA, so the caller has to wrap it
///   (`SPKIEncoder`) — passing that unwrapped produces a phrase that looks right and is not.
/// - **The prk is the hash of the key, and that is the same thing as the key.** The Rust
///   implementation passes the 294-byte key straight to HKDF and the TypeScript one passes
///   `SHA256(key)`. They agree because HMAC hashes a key longer than its 64-byte block before
///   use, so both end up keying the HMAC with `SHA256(key)`. Replicated explicitly below rather
///   than relying on that, so the behaviour does not depend on a library's internals.
nonisolated enum AccountFingerprintPhrase {

    /// The output is five words at the reference's 64-bit minimum entropy and 7776-word list.
    private static let minimumEntropy = 64

    // MARK: - Errors

    enum PhraseError: Error, LocalizedError {
        /// The hash carries less entropy than the phrase claims. Reachable only with a word list
        /// longer than the reference's or a shorter hash.
        case entropyTooSmall

        var errorDescription: String? {
            switch self {
            case .entropyTooSmall:
                return L("The account fingerprint could not be derived.")
            }
        }
    }

    // MARK: - Entry point

    /// The phrase for one account.
    ///
    /// - Parameters:
    ///   - material: The account's user id. Not the email.
    ///   - publicKey: The account's RSA public key, **SPKI DER**.
    ///   - wordList: The 7776-word EFF long word list, in the reference's order.
    static func phrase(
        material: String,
        publicKey: Data,
        wordList: [String]
    ) throws -> String {
        let hash = hkdfExpand(
            prk: Self.prk(for: publicKey),
            info: Data(material.utf8),
            outputByteCount: 32
        )
        return try words(from: hash, wordList: wordList).joined(separator: "-")
    }

    /// The phrase for a hash that has already been through HKDF-Expand.
    ///
    /// Visible rather than private so the reference's single-step expectation can be asserted on
    /// its own. The TypeScript spec pins `hashPhrase` for a known 32-byte input, and being able to
    /// cover that step separately is what makes a wrong byte order attributable to the byte order
    /// instead of to HKDF — with only the end-to-end vector, either fault looks like "wrong phrase".
    static func phrase(forHash hash: Data, wordList: [String]) throws -> String {
        try words(from: hash, wordList: wordList).joined(separator: "-")
    }

    /// The number of words the reference asks for, given this word list.
    ///
    /// Five for the 7776-word EFF list: `ceil(64 / log2(7776))`.
    private static func wordCount(for wordList: [String]) -> Int {
        guard wordList.count > 1 else { return 0 }
        let entropyPerWord = log2(Double(wordList.count))
        return Int(ceil(Double(minimumEntropy) / entropyPerWord))
    }

    // MARK: - HKDF-Expand (RFC 5869 §2.3)

    /// The pseudorandom key.
    ///
    /// HMAC hashes a key longer than its block size before use, so passing the key directly (as
    /// the Rust reference does) and passing its hash (as the TypeScript reference does) are the
    /// same computation. Hashing here makes that explicit instead of implicit.
    private static func prk(for publicKey: Data) -> Data {
        guard publicKey.count > 64 else { return publicKey }
        return Data(SHA256.hash(data: publicKey))
    }

    /// One round of HKDF-Expand — the reference asks for 32 bytes from SHA-256, which is a single
    /// round and needs no loop.
    private static func hkdfExpand(prk: Data, info: Data, outputByteCount: Int) -> Data {
        var message = info
        message.append(0x01)
        let tag = HMAC<SHA256>.authenticationCode(
            for: message,
            using: SymmetricKey(data: prk)
        )
        return Data(tag).prefix(outputByteCount)
    }

    // MARK: - Words

    /// Maps a 32-byte hash onto words, least-significant digits first.
    private static func words(from hash: Data, wordList: [String]) throws -> [String] {
        let count = wordList.count
        guard count > 1 else { throw PhraseError.entropyTooSmall }

        let numWords = wordCount(for: wordList)
        let entropyAvailable = hash.count * 4
        if Double(numWords) * log2(Double(count)) > Double(entropyAvailable) {
            throw PhraseError.entropyTooSmall
        }

        // Big-endian bytes, divided in place. `remainder * 256 + byte` stays far below Int's range
        // for any word list this could be handed (7775 * 256 + 255 ≈ 2.0M).
        var digits = [UInt8](hash)
        var phrase: [String] = []
        phrase.reserveCapacity(numWords)

        for _ in 0..<numWords {
            var remainder = 0
            var quotient: [UInt8] = []
            quotient.reserveCapacity(digits.count)

            for byte in digits {
                let current = remainder * 256 + Int(byte)
                quotient.append(UInt8(current / count))
                remainder = current % count
            }

            phrase.append(wordList[remainder])
            digits = Array(quotient.drop(while: { $0 == 0 }))
        }

        return phrase
    }
}

// MARK: - SPKIEncoder

/// Wraps a PKCS#1 `RSAPublicKey` DER blob in the `SubjectPublicKeyInfo` structure the reference
/// hashes.
///
/// Necessary because `SecKeyCopyExternalRepresentation` hands back PKCS#1 on Apple platforms, and
/// the two encodings differ by a 24-byte header. The fingerprint is a hash, so a difference there
/// is invisible: the phrase still looks like a phrase, and simply never matches another client.
nonisolated enum SPKIEncoder {

    /// `SEQUENCE { OID 1.2.840.113549.1.1.1 (rsaEncryption), NULL }`, the fixed 15 bytes that
    /// precede every RSA SPKI.
    private static let rsaAlgorithmIdentifier: [UInt8] = [
        0x30, 0x0D,
        0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
        0x05, 0x00
    ]

    /// Wraps `pkcs1PublicKey` as `SEQUENCE { algorithmIdentifier, BIT STRING { 0x00 || key } }`.
    static func encode(pkcs1PublicKey: Data) -> Data {
        var bitStringContent: [UInt8] = [0x00]          // unused-bits octet
        bitStringContent.append(contentsOf: pkcs1PublicKey)

        var body = Self.rsaAlgorithmIdentifier
        body.append(0x03)                                // BIT STRING
        body.append(contentsOf: derLength(bitStringContent.count))
        body.append(contentsOf: bitStringContent)

        var out: [UInt8] = [0x30]                        // SEQUENCE
        out.append(contentsOf: derLength(body.count))
        out.append(contentsOf: body)
        return Data(out)
    }

    /// DER definite-length encoding: short form below 128, long form otherwise.
    private static func derLength(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        var bytes: [UInt8] = []
        var value = length
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
