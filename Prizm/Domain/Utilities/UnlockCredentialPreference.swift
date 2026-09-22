import Foundation

// MARK: - UnlockCredentialMethod

/// Which credential the unlock screen asks for.
enum UnlockCredentialMethod: Equatable, Sendable {
    case masterPassword
    case pin
}

// MARK: - UnlockCredentialPreference

/// The credential that most recently opened the vault **during this launch**, per account.
///
/// The unlock screen offers one field rather than two, and this decides which one it shows first:
/// whatever worked last time. It is deliberately not persisted.
///
/// A stored "this user unlocks with a PIN" would be a hint to anyone holding the machine that a
/// four-digit code — not the master password — is the gate in front of their secrets, which is the
/// opposite of what a short code is for. Keeping it in memory means the default after a restart is
/// always the master password, and the shortcut only ever appears after the user has proven it works
/// on this launch. That also lines up with `AuthRepository.pinUnlockAvailable`, which already refuses
/// a PIN on a freshly restarted app until something has authenticated in full.
///
/// **Keyed by account, not global.** Two accounts on one Mac have nothing to say about each other's
/// unlock habits, and "the shortcut is earned" has to mean earned *by this account*. A single
/// process-wide flag let an account that had just used a PIN hand that default to the next account to
/// sign in — a wrong default on a security screen, even though it is the next account's own PIN that
/// would still have to be entered correctly.
///
/// Held by `AppContainer` rather than the view model: `RootViewModel` builds a new `UnlockViewModel`
/// every time the vault locks (`PrizmApp.swift:803`), so per-launch state cannot live there.
@MainActor
final class UnlockCredentialPreference {

    private var lastUsedByAccount: [String: UnlockCredentialMethod] = [:]

    /// What the unlock screen should ask for first. Absent means never earned: the master password.
    func lastUsedMethod(for accountEmail: String) -> UnlockCredentialMethod {
        lastUsedByAccount[Self.key(accountEmail)] ?? .masterPassword
    }

    /// Records the method that just succeeded, making it the default for this account's next lock.
    func recordSuccess(of method: UnlockCredentialMethod, for accountEmail: String) {
        lastUsedByAccount[Self.key(accountEmail)] = method
    }

    /// Accounts are addressed by email everywhere else in the session layer
    /// (`SyncTimestampRepositoryImpl`), and the comparison is case-insensitive by the same rule.
    private static func key(_ email: String) -> String { email.lowercased() }
}
