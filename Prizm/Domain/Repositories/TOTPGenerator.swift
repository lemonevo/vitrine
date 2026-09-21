import Foundation

// MARK: - TOTPWindow

/// A derived one-time code together with the time step it belongs to.
///
/// The step is part of the answer, not a detail the caller looks up separately. A caller that had to
/// parse the secret again to learn the period could disagree with the parse that produced the code —
/// and the disagreement would surface as a countdown that does not match the code, which reads as a
/// broken clock rather than as two parsers drifting apart.
nonisolated struct TOTPWindow: Equatable, Sendable {

    /// The zero-padded code, as it should be sent to a server. Not grouped for reading.
    let value: String

    /// The instant `value` stops being valid: the start of the next step.
    let expiresAt: Date

    /// The length of the whole step, so a caller can show progress and not only a countdown.
    let period: TimeInterval
}

// MARK: - TOTPGenerator

/// Derives the current one-time password from a stored TOTP secret.
///
/// The secret is the long-lived shared key Bitwarden stores on a login item. Anyone who reads it
/// can generate valid codes forever, so nothing in the app may put it on the clipboard or into a
/// log — only the code this protocol returns. Before this existed, `Item ▸ Copy Code` copied the
/// secret itself (see `FEATURE-GAP-ANALYSIS.md` §2.1).
///
/// Reference: RFC 6238 (TOTP), RFC 4226 (HOTP), and the Key URI Format
/// (github.com/google/google-authenticator/wiki/Key-URI-Format).
nonisolated protocol TOTPGenerator: Sendable {

    /// Returns the code valid at `date` and the step it belongs to, or `nil` when no code can be
    /// derived.
    ///
    /// - Parameters:
    ///   - secret: The stored TOTP value — either a full `otpauth://totp/…` key URI or a bare
    ///     Base32 secret. Case, `=` padding and embedded whitespace are ignored.
    ///   - date:   The instant to generate for. Passing an explicit date keeps the generator
    ///     deterministic and therefore testable against the RFC vectors.
    /// - Returns: The code and its window, or `nil` when `secret` is absent, empty, not decodable as
    ///   Base32, or names an algorithm/parameter set that is not supported.
    func window(for secret: String?, at date: Date) -> TOTPWindow?
}

extension TOTPGenerator {

    /// The code alone, for callers with no use for the step — copying, and validating a seed.
    func code(for secret: String?, at date: Date) -> String? {
        window(for: secret, at: date)?.value
    }

    /// Convenience overload for the call site that matters most — "give me the code right now".
    ///
    /// Correct for copying, where the code must be generated at the moment it is used. **Not**
    /// correct for displaying: a view that generated here and rendered a moment later would show a
    /// code whose countdown had already moved on.
    func code(for secret: String?) -> String? {
        code(for: secret, at: Date())
    }
}
