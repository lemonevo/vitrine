import Foundation

// MARK: - WebsiteIconsPreference

/// The "Show website icons" preference.
///
/// **Why this is a setting at all.** Prizm used to fetch every login item's favicon from a
/// hardcoded `https://icons.bitwarden.net`, which sends each item's domain to a third party. For a
/// self-hosted Vaultwarden user — whose reason for self-hosting is usually exactly this — that is
/// the wrong default. Icons now come from the account's own server, and this flag turns them off
/// entirely for anyone who would rather not make the request at all.
///
/// Persisted to `UserDefaults` (a display preference, not vault data — no Keychain), following the
/// same shape as `PasswordGeneratorConfig`: a value type with injectable storage so tests can use
/// an isolated suite.
nonisolated enum WebsiteIconsPreference {

    /// `UserDefaults` key. Read by `FaviconLoader`, written by the Settings toggle.
    static let key = "showWebsiteIcons"

    /// Whether website icons are shown. Defaults to `true` when the key has never been written.
    ///
    /// `UserDefaults.bool(forKey:)` returns `false` for a missing key, which would silently flip the
    /// default to off; the explicit `object(forKey:)` check is what makes the default real.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    /// Writes the preference. Takes effect on the next fetch — `FaviconLoader` reads it per request.
    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }
}
