import Foundation

// MARK: - ISO8601WireDate

/// The two ISO-8601 shapes this project's wire formats meet, and the rule for reading either.
///
/// **Why one copy.** This pair of formatters and the "try the fractional-seconds form, then the plain
/// one" fallback were written out identically in two places: `VaultExportDocument`, which has to match
/// what a JavaScript client writes — `JSON.stringify(new Date())` is `Date.prototype.toISOString()`,
/// always UTC with milliseconds — and `VaultRepositoryImpl`, which has to accept whatever Vaultwarden
/// sent. Two copies of a *parsing rule* is not the same as two copies of a constant: a date format one
/// of them learns to reject degrades to `nil` rather than to an error, so the drift between the copies
/// would surface as items quietly missing a revision date, not as a failure anyone would notice.
///
/// **What deliberately stays separate.** `CipherMapper` and `SyncTimestampRepositoryImpl` each own a
/// single formatter of their own. That is a recorded decision, not an oversight — see the comment at
/// `SyncTimestampRepositoryImpl`'s formatter — and it is not undone here: those two hold one value
/// each, with no fallback rule to keep in agreement. Do not "finish the consolidation" without reading
/// that reasoning first.
nonisolated enum ISO8601WireDate {

    /// UTC with a fractional-seconds part, e.g. `2026-09-24T02:11:07.481Z`.
    ///
    /// `ISO8601DateFormatter` is safe for concurrent use once constructed, and neither formatter is
    /// mutated after initialisation, which is what makes `nonisolated(unsafe)` the right annotation
    /// rather than an unchecked one.
    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// UTC without one, e.g. `2026-09-24T02:11:07Z` — what a server writes when the instant has no
    /// sub-second part. `.withFractionalSeconds` *rejects* this form rather than tolerating it, which
    /// is the entire reason there are two.
    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses either shape. Fractional-seconds first: it is the more specific of the two, and the one
    /// both writers emit whenever they can.
    static func parse(_ raw: String) -> Date? {
        withFractionalSeconds.date(from: raw) ?? plain.date(from: raw)
    }

    /// Formats the way the reference client does: always UTC, always milliseconds.
    static func format(_ date: Date) -> String {
        withFractionalSeconds.string(from: date)
    }
}
