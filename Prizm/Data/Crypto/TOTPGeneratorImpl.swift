import CryptoKit
import Foundation
import os.log

// MARK: - TOTPGeneratorImpl

/// RFC 6238 time-based one-time password generator.
///
/// **Security goal.** Turn the long-lived shared secret stored on a login item into a code that
/// expires within a time step, so that copying a code out of Prizm cannot hand an attacker a
/// permanent second factor. The secret itself is never returned, logged or placed on the clipboard.
///
/// **Algorithm.** HMAC over the big-endian 8-byte time step counter, then RFC 4226 §5.3 dynamic
/// truncation:
///
///     offset = mac[19] & 0x0F
///     binary = (mac[offset] & 0x7F) << 24 | mac[offset+1] << 16 | mac[offset+2] << 8 | mac[offset+3]
///     code   = binary mod 10^digits, zero-padded
///
/// Reference: RFC 4226 §5.3, RFC 6238 §4.1.
///
/// **Deviations from the reference:** none. The HMAC is computed with CryptoKit
/// (`HMAC<Insecure.SHA1>` / `HMAC<SHA256>` / `HMAC<SHA512>`); the project's constitution forbids
/// hand-rolled cryptography. SHA-1 is the RFC 6238 default and remains the only algorithm most
/// authenticator back-ends accept, so it is supported despite being weak for collision resistance —
/// HMAC-SHA1's security as a MAC is not affected by collision attacks (RFC 6151 §2).
///
/// **What is deliberately NOT done.** No attempt is made to reject a secret whose length is below
/// the RFC 4226 §4.1 recommended 128 bits. Rejecting it would lock users out of items whose secret
/// was issued by a service that does not follow the recommendation, and the generator cannot
/// improve a weak secret — only the issuing service can.
nonisolated struct TOTPGeneratorImpl: TOTPGenerator {

    private static let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "TOTP")

    /// Hash algorithms permitted by the Key URI Format. Anything else yields no code rather than
    /// a guess.
    private enum Algorithm: String {
        case sha1   = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    /// Effective parameters for one secret, after applying the Key URI Format defaults.
    private struct Parameters {
        var secret:    Data
        var algorithm: Algorithm = .sha1
        var digits:    Int       = 6
        var period:    Int       = 30
    }

    // MARK: - TOTPGenerator

    func window(for secret: String?, at date: Date) -> TOTPWindow? {
        guard let parameters = parameters(from: secret) else {
            // Usually not a fault: most login items simply have no TOTP secret. Logged at debug so
            // a genuinely malformed value is still traceable without spamming the log. The secret
            // is never included — not even a prefix of it.
            Self.logger.debug("No TOTP code: stored value is absent, empty or not a usable Base32 secret")
            return nil
        }

        let step    = Double(parameters.period)
        let counter = UInt64(floor(date.timeIntervalSince1970 / step))
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let key     = SymmetricKey(data: parameters.secret)

        let mac: Data
        switch parameters.algorithm {
        case .sha1:   mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: mac = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }

        guard let code = truncate(mac, digits: parameters.digits) else { return nil }

        // The start of the next step, derived from the counter that produced the code rather than
        // from a second division of `date` — so the window cannot describe a different step from the
        // one the code belongs to. `floor` above makes this strictly after `date`.
        return TOTPWindow(value:     code,
                          expiresAt: Date(timeIntervalSince1970: (Double(counter) + 1) * step),
                          period:    step)
    }

    // MARK: - Parsing

    /// Reads the two shapes Bitwarden stores: a full `otpauth://` key URI, or a bare Base32 secret.
    private func parameters(from stored: String?) -> Parameters? {
        guard let stored else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("otpauth://") {
            return parameters(fromKeyURI: trimmed)
        }
        guard let secret = base32Decode(trimmed) else { return nil }
        return Parameters(secret: secret)
    }

    private func parameters(fromKeyURI uri: String) -> Parameters? {
        guard
            let components = URLComponents(string: uri),
            let items      = components.queryItems,
            let secretRaw  = items.first(where: { $0.name.lowercased() == "secret" })?.value,
            let secret     = base32Decode(secretRaw)
        else { return nil }

        var parameters = Parameters(secret: secret)

        if let raw = items.first(where: { $0.name.lowercased() == "algorithm" })?.value {
            // An unrecognised algorithm is refused rather than silently downgraded to SHA-1:
            // generating codes from the wrong hash produces codes that never validate, and the
            // user would have no way to tell why.
            guard let algorithm = Algorithm(rawValue: raw.uppercased()) else { return nil }
            parameters.algorithm = algorithm
        }

        if let raw = items.first(where: { $0.name.lowercased() == "digits" })?.value {
            // RFC 4226 §4.1 defines 6, 7 and 8 digits. A larger value would be silently truncated
            // by the modulo below, producing codes that never match.
            guard let digits = Int(raw), (6...8).contains(digits) else { return nil }
            parameters.digits = digits
        }

        if let raw = items.first(where: { $0.name.lowercased() == "period" })?.value {
            guard let period = Int(raw), period > 0 else { return nil }
            parameters.period = period
        }

        return parameters
    }

    /// Decodes RFC 4648 Base32, the alphabet authenticator apps use.
    ///
    /// Case-insensitive, and ignores `=` padding and embedded whitespace — secrets are routinely
    /// pasted in lower case, with padding, or grouped in fours.
    private func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var lookup: [Character: UInt8] = [:]
        lookup.reserveCapacity(alphabet.count)
        for (index, character) in alphabet.enumerated() {
            lookup[character] = UInt8(index)
        }

        var buffer:       UInt32 = 0
        var bitsInBuffer: Int    = 0
        var output                = Data()

        for character in input.uppercased() {
            if character == "=" || character.isWhitespace { continue }
            guard let value = lookup[character] else { return nil }

            buffer = (buffer << 5) | UInt32(value)
            bitsInBuffer += 5

            if bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                output.append(UInt8((buffer >> UInt32(bitsInBuffer)) & 0xFF))
            }
        }

        // Trailing bits that do not complete a byte are Base32 padding; discard them.
        return output.isEmpty ? nil : output
    }

    // MARK: - Generation

    /// RFC 4226 §5.3 dynamic truncation followed by zero-padding to `digits`.
    private func truncate(_ mac: Data, digits: Int) -> String? {
        guard let last = mac.last else { return nil }

        let offset = Int(last & 0x0F)
        let window = mac.dropFirst(offset).prefix(4)
        guard window.count == 4 else { return nil }

        // The high bit is masked off so the result is always positive — RFC 4226 §5.3.
        let binary = window.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & 0x7FFF_FFFF
        let modulus = UInt32(pow(10.0, Double(digits)))

        return String(format: "%0\(digits)d", binary % modulus)
    }
}
