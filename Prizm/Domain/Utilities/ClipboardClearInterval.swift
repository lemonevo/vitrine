import Foundation

// MARK: - ClipboardClearInterval

/// How long a value copied from Prizm stays on the clipboard before Prizm clears it.
///
/// **Why this is configurable.** A copied password is a plaintext secret in a buffer that every
/// process on the machine can read. 30 seconds is a defensible default and a poor only-option: too
/// long for someone pasting into a terminal on a shared screen, too short for someone who has to
/// switch windows and authenticate first. `.never` exists for the same reason — a user who has
/// disabled it has made a decision, and silently overriding it would be worse than the risk.
nonisolated enum ClipboardClearInterval: String, CaseIterable, Identifiable, Sendable {

    case tenSeconds
    case twentySeconds
    case thirtySeconds
    case oneMinute
    case twoMinutes
    case never

    var id: String { rawValue }

    /// Seconds until the clipboard is cleared, or `nil` when it is never cleared.
    ///
    /// `nil` rather than a sentinel: a large number would eventually be scheduled as a real timer,
    /// and "never" must not depend on the process outliving it.
    var seconds: TimeInterval? {
        switch self {
        case .tenSeconds:    return 10
        case .twentySeconds: return 20
        case .thirtySeconds: return 30
        case .oneMinute:     return 60
        case .twoMinutes:    return 120
        case .never:         return nil
        }
    }

    /// Matches the behaviour that was hardcoded before this setting existed.
    static let `default` = ClipboardClearInterval.thirtySeconds

    var displayName: String {
        switch self {
        case .tenSeconds:    return L("10 seconds")
        case .twentySeconds: return L("20 seconds")
        case .thirtySeconds: return L("30 seconds")
        case .oneMinute:     return L("1 minute")
        case .twoMinutes:    return L("2 minutes")
        case .never:         return L("Never")
        }
    }

    // MARK: Persistence

    static let key = "clipboardClearInterval"

    static func load(from defaults: UserDefaults = .standard) -> ClipboardClearInterval {
        defaults.string(forKey: key)
            .flatMap(ClipboardClearInterval.init(rawValue:)) ?? .default
    }

    static func save(_ interval: ClipboardClearInterval, to defaults: UserDefaults = .standard) {
        defaults.set(interval.rawValue, forKey: key)
    }
}
