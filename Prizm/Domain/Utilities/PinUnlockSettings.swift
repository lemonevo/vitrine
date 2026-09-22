import Foundation

// MARK: - PinUnlockSettings

/// The settings that qualify PIN unlock, as opposed to the PIN itself.
///
/// One setting, and it is the one that decides whether this feature is a convenience or a hole:
/// whether a PIN may open a **freshly launched** app, or only one that has already been opened once
/// with the master password.
nonisolated enum PinUnlockSettings {

    static let requireMasterPasswordOnRestartKey = "pinUnlockRequiresMasterPasswordOnRestart"

    /// The shortest PIN accepted. The official client's documented minimum.
    ///
    /// Policy, not mechanism — which is why it lives here beside the other setting rather than on the
    /// service's protocol: a `static` protocol requirement cannot be read from an `any` metatype, and
    /// the presentation layer should not have to name a concrete Data-layer type to find out how many
    /// characters are required.
    static let minimumPINLength = 4

    /// How many consecutive wrong PINs are accepted before the stored material is destroyed.
    ///
    /// The official client signs the user out after five.
    static let maximumAttempts = 5

    /// Whether the master password (or biometrics) is required before a PIN will be accepted, on a
    /// launch that has not seen one.
    ///
    /// **Defaults to `true`, matching the official client**, and the default matters more than the
    /// setting: with it off, a PIN — four digits, ten thousand possibilities — would be the only thing
    /// between someone who has the laptop and the vault, from the moment it is switched on. With it on,
    /// the weaker path is something the user chooses rather than something they have to discover and
    /// turn off.
    static func requiresMasterPasswordOnRestart(from defaults: UserDefaults = .standard) -> Bool {
        // `object(forKey:)` rather than `bool(forKey:)`: the latter reports `false` for a key that has
        // never been written, which would silently ship the *unsafe* default.
        guard defaults.object(forKey: requireMasterPasswordOnRestartKey) != nil else { return true }
        return defaults.bool(forKey: requireMasterPasswordOnRestartKey)
    }

    static func setRequiresMasterPasswordOnRestart(_ required: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(required, forKey: requireMasterPasswordOnRestartKey)
    }
}
