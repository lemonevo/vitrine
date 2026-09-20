import Foundation

// MARK: - VaultTimeoutInterval

/// How long an unlocked vault may sit idle before the timeout action fires.
///
/// `.never` is represented by a `nil` second count rather than a sentinel number. `Int.max`
/// minutes would overflow when converted to seconds and would silently become "lock almost
/// immediately" — a fail-open setting that fails closed.
nonisolated enum VaultTimeoutInterval: String, CaseIterable, Identifiable, Sendable {

    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case never

    var id: String { rawValue }

    /// The interval in minutes, or `nil` for `.never`.
    var minutes: Int? {
        switch self {
        case .oneMinute:      return 1
        case .fiveMinutes:    return 5
        case .fifteenMinutes: return 15
        case .thirtyMinutes:  return 30
        case .oneHour:        return 60
        case .never:          return nil
        }
    }

    /// The interval in seconds, or `nil` when the timeout is disabled.
    var seconds: TimeInterval? {
        minutes.map { TimeInterval($0 * 60) }
    }

    var displayName: String {
        switch self {
        case .oneMinute:      return L("1 minute")
        case .fiveMinutes:    return L("5 minutes")
        case .fifteenMinutes: return L("15 minutes")
        case .thirtyMinutes:  return L("30 minutes")
        case .oneHour:        return L("1 hour")
        case .never:          return L("Never")
        }
    }
}

// MARK: - VaultTimeoutAction

/// What happens when the idle timeout elapses.
///
/// Both cases map onto teardown paths that already existed for the sleep / screensaver / screen-lock
/// locks, so the timeout introduces no new way to destroy or retain key material:
/// `.lock` → `RootViewModel.lockVault()`, `.signOut` → `RootViewModel.signOut()`.
nonisolated enum VaultTimeoutAction: String, CaseIterable, Identifiable, Sendable {

    /// Clears the vault and all key material, keeping the stored session. Returns to Unlock.
    case lock

    /// Additionally discards the stored session. Returns to Sign In.
    case signOut

    var id: String { rawValue }

    var displayName: String {
        switch self {
        // Reuses the existing keys rather than introducing case-variant duplicates: "Lock Vault" is
        // already the menu command, and "Sign Out" is already the alert button.
        case .lock:    return L("Lock Vault")
        case .signOut: return L("Sign Out")
        }
    }
}

// MARK: - VaultTimeoutSettings

/// The idle-timeout configuration: how long, and what happens.
nonisolated struct VaultTimeoutSettings: Equatable, Sendable {

    var interval: VaultTimeoutInterval
    var action: VaultTimeoutAction

    /// 15 minutes / lock — long enough not to interrupt work, short enough to matter.
    static let `default` = VaultTimeoutSettings(interval: .fifteenMinutes, action: .lock)

    /// The interval in seconds, or `nil` when the timeout is disabled.
    var seconds: TimeInterval? { interval.seconds }

    /// Whether the timeout is disabled.
    var isDisabled: Bool { seconds == nil }

    // MARK: Persistence

    static let intervalKey = "vaultTimeoutInterval"
    static let actionKey   = "vaultTimeoutAction"

    /// Reads the stored configuration, falling back to `.default` for any key that has never been
    /// written or holds an unrecognised value.
    static func load(from defaults: UserDefaults = .standard) -> VaultTimeoutSettings {
        let fallback = VaultTimeoutSettings.default
        // `.default.interval` would resolve against `VaultTimeoutInterval` (the type on the left of
        // `??`), which has no `default` — hence the explicit base.
        let interval = defaults.string(forKey: intervalKey)
            .flatMap(VaultTimeoutInterval.init(rawValue:)) ?? fallback.interval
        let action   = defaults.string(forKey: actionKey)
            .flatMap(VaultTimeoutAction.init(rawValue:)) ?? fallback.action
        return VaultTimeoutSettings(interval: interval, action: action)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(interval.rawValue, forKey: Self.intervalKey)
        defaults.set(action.rawValue,   forKey: Self.actionKey)
    }
}
