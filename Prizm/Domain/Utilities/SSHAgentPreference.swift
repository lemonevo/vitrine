import Foundation

// MARK: - SSHAgentPreference

/// The "SSH agent" switch.
///
/// **Off by default, and the asymmetry with `WebsiteIconsPreference` is deliberate.** That one
/// defaults to on and therefore has to distinguish "never written" from a stored `false` via
/// `object(forKey:)`. This one defaults to off, which is exactly what `bool(forKey:)` returns for a
/// missing key — so the plain read *is* the default, and adding the `object(forKey:)` dance here
/// would only invite someone to copy it back into the other file.
///
/// Why off: the agent turns "the vault is unlocked" into "every process running as this user can
/// borrow these keys to sign". That is a real widening of what an unlocked vault means, and it is
/// the user's call to make, not a default.
nonisolated enum SSHAgentPreference {

    /// `UserDefaults` key. Read by `SSHAgentCoordinator`, written by the Settings toggle.
    static let key = "sshAgentEnabled"

    /// Whether the user has switched the agent on. `false` when the key has never been written.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Writes the preference.
    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }
}
