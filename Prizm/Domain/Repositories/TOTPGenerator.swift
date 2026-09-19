import Foundation

// MARK: - TOTPGenerator

/// Derives the current one-time password from a stored TOTP secret.
///
/// The secret is the long-lived shared key Bitwarden stores on a login item. Anyone who reads it
/// can generate valid codes forever, so nothing in the app may put it on the clipboard or into a
/// log — only the code this protocol returns. Before this existed, `Item ▸ Copy Code` copied the
/// secret itself (see `FEATURE-GAP-ANALYSIS.md` §2.1).
///
/// Reference: RFC 6238 (TOTP), RFC 4226 (HOTP), and the Key URI Format
/// (github.com/google/google-authenticator/wiki/Key-Uri-Format).
nonisolated protocol TOTPGenerator: Sendable {

    /// Returns the one-time code valid at `date`, or `nil` when no code can be derived.
    ///
    /// - Parameters:
    ///   - secret: The stored TOTP value — either a full `otpauth://totp/…` key URI or a bare
    ///     Base32 secret. Case, `=` padding and embedded whitespace are ignored.
    ///   - date:   The instant to generate for. Passing an explicit date keeps the generator
    ///     deterministic and therefore testable against the RFC vectors.
    /// - Returns: A zero-padded code of the configured length, or `nil` when `secret` is absent,
    ///   empty, not decodable as Base32, or names an algorithm/parameter set that is not supported.
    func code(for secret: String?, at date: Date) -> String?
}

extension TOTPGenerator {

    /// Convenience overload for the only call site that matters — "give me the code right now".
    func code(for secret: String?) -> String? {
        code(for: secret, at: Date())
    }
}
