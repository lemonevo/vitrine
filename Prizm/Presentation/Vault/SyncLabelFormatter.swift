import Foundation

// MARK: - Offline label

/// The sidebar footer label for a vault populated from the offline cache.
///
/// Deliberately a different sentence from `syncStatusLabel`, not a variation on it. "Synced 5
/// minutes ago" describes a successful conversation with the server; this describes the absence of
/// one, and a label that reads like the former is the failure this whole capability exists to
/// avoid — a vault that looks current and is not.
///
/// The age is rendered as an absolute local time rather than "2 hours ago": in the offline case the
/// user is deciding whether what they see is too old to trust, and a wall-clock time is the form
/// they can compare against the clock in the corner without arithmetic.
enum OfflineSyncLabel {

    /// - Parameter payloadTimestamp: When the cached payload was written by the server. `nil` when
    ///   the read produced no timestamp, which drops the age rather than the whole label.
    static func make(
        payloadTimestamp: Date?,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let payloadTimestamp else {
            return L("Offline — showing a saved copy of your vault")
        }
        return L("Offline — showing data from %@", formatted(payloadTimestamp, relativeTo: now, calendar: calendar))
    }

    private static func formatted(_ date: Date, relativeTo now: Date, calendar: Calendar) -> String {
        // Same rule as `Date.syncStatusLabel`: follow the interface language, not the system locale.
        var style = formatStyle(includingYear: false, calendar: calendar)
        // A copy from a previous year is ambiguous without one — "Mar 26, 14:03" could be this year
        // or five years ago, and which one it is is the entire question the label answers.
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = formatStyle(includingYear: true, calendar: calendar)
        }
        return date.formatted(style)
    }

    private static func formatStyle(includingYear: Bool, calendar: Calendar) -> Date.FormatStyle {
        // Property assignment rather than chaining: `FormatStyle` exposes `calendar` as a stored
        // var, so `.calendar(x)` parses as calling the Calendar value as a function.
        var s = includingYear
            ? Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute()
            : Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        s.calendar = calendar
        s.locale   = ActiveLocalization.locale
        return s
    }
}

// MARK: - Unreadable items

/// The sidebar footer's report of items the last sync could not read.
///
/// A third sentence beside "Synced …" and "Offline …", and the only one that describes a *problem
/// with the vault's contents* rather than the freshness of the fetch. It stays up for as long as the
/// condition holds: it is not dismissable, because dismissing it would remove the only signal that
/// the list is incomplete while the incompleteness remained.
///
/// The singular case gets its own string because `L` is `String(format:)` over a looked-up key with
/// no plural machinery — one key cannot be grammatical for both counts in English.
enum UnreadableItemsLabel {

    /// The footer line, or `nil` when there is nothing wrong to report.
    static func make(count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? L("1 item could not be read") : L("%d items could not be read", count)
    }

    /// The tooltip. Says where the items are, as well as that they could not be read — a count on
    /// its own invites the conclusion that they were deleted, which is the one thing that is not
    /// true and the one the user cannot check from inside the app.
    static func explanation(count: Int) -> String {
        count == 1
            ? L("1 item could not be read. It is still on the server; Prizm could not decrypt it.")
            : L("%d items could not be read. They are still on the server; Prizm could not decrypt them.", count)
    }
}

// MARK: - Sync label formatter

extension Optional where Wrapped == Date {
    /// Returns a human-friendly relative sync status label for display in the sidebar footer.
    ///
    /// Returns `"Never synced"` when the date is `nil`.
    /// See `Date.syncStatusLabel(relativeTo:calendar:)` for label tier documentation.
    func syncStatusLabel(
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        switch self {
        case .none:       return L("Never synced")
        case .some(let d): return d.syncStatusLabel(relativeTo: now, calendar: calendar)
        }
    }
}

extension Date {
    /// Returns a human-friendly relative label for this date relative to `now`.
    ///
    /// Tiers are evaluated in this order (calendar day first, then elapsed time):
    ///
    /// **Calendar day checks (evaluated first):**
    /// 1. Future timestamp → "Synced just now" (clock skew guard)
    /// 2. Previous calendar year or earlier → "Synced Month Day, Year" (e.g. "Synced Mar 26, 2025")
    /// 3. Two or more calendar days ago, same year → "Synced Month Day" (e.g. "Synced Mar 26")
    /// 4. Previous calendar day → "Synced yesterday"
    ///
    /// **Elapsed time checks (same calendar day only):**
    /// 5. 0–59 seconds → "Synced just now"
    /// 6. 60–3599 seconds → "Synced 1 minute ago" / "Synced X minutes ago"
    /// 7. 3600+ seconds → "Synced 1 hour ago" / "Synced X hours ago"
    ///
    /// Calendar day comparisons use the provided `calendar` (defaulting to `.current`)
    /// so the "yesterday" boundary respects the user's local timezone.
    func syncStatusLabel(
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        // Tier 1: future timestamp — clamp to "just now" (clock skew guard)
        guard self <= now else { return L("Synced just now") }

        // Compare start-of-day values so daysDiff counts calendar days (midnight-to-midnight),
        // not elapsed 24-hour periods. Without this, 23:58 yesterday → 14:00 today = 0 days,
        // causing the hours tier to fire instead of "yesterday".
        let selfDay = calendar.startOfDay(for: self)
        let nowDay  = calendar.startOfDay(for: now)
        let daysDiff = calendar.dateComponents([.day], from: selfDay, to: nowDay).day ?? 0
        let selfYear = calendar.component(.year, from: self)
        let nowYear  = calendar.component(.year, from: now)

        // Tier 2: previous calendar year
        if selfYear < nowYear {
            return L("Synced %@", formatted(style: .dateTime.month(.abbreviated).day().year(), calendar: calendar))
        }

        // Tier 3: 2+ calendar days ago, same year
        if daysDiff >= 2 {
            return L("Synced %@", formatted(style: .dateTime.month(.abbreviated).day(), calendar: calendar))
        }

        // Tier 4: previous calendar day ("yesterday")
        // Uses calendar day comparison rather than a fixed 24-hour window, so the boundary
        // always falls at midnight in the user's local timezone.
        if daysDiff == 1 {
            return L("Synced yesterday")
        }

        // Same calendar day — use elapsed seconds for tiers 5–7.
        let elapsed = Int(now.timeIntervalSince(self))

        // Tier 5: 0–59 seconds
        if elapsed < 60 { return L("Synced just now") }

        // Tier 6: 60–3599 seconds (minutes)
        if elapsed < 3600 {
            let minutes = elapsed / 60
            return minutes == 1 ? L("Synced 1 minute ago") : L("Synced %lld minutes ago", minutes)
        }

        // Tier 7: 3600+ seconds (hours)
        let hours = elapsed / 3600
        return hours == 1 ? L("Synced 1 hour ago") : L("Synced %lld hours ago", hours)
    }

    // MARK: - Private formatting helpers

    private func formatted(style: Date.FormatStyle, calendar: Calendar) -> String {
        // Date.FormatStyle is zero-allocation — no DateFormatter constructed per call.
        // Available macOS 12+; the project targets macOS 26.
        // Property assignment is required: FormatStyle exposes `calendar` as a stored var,
        // so chaining `.calendar(x)` is parsed as calling the Calendar value as a function.
        var s = style
        s.calendar = calendar
        // Follow the interface language, not the system locale: an English UI on a
        // Chinese Mac should still read "Synced Mar 26".
        s.locale   = ActiveLocalization.locale
        return self.formatted(s)
    }
}
