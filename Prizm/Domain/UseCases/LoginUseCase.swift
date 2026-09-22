import Foundation

/// The outcome of the whole login flow, as opposed to `LoginResult`, which is only what the
/// authentication step answered.
///
/// The sync result travels with the account because the caller cannot otherwise tell "signed in and
/// the vault is current" from "signed in and the vault could not be fetched". Those two land on the
/// same screen, and the only thing that distinguishes them for the user is the timestamp and the
/// source on it — which the caller has to be given rather than left to invent.
nonisolated enum LoginOutcome {
    /// Authenticated, with whatever the vault sync that follows produced. `nil` when the sync failed
    /// — which is not a failed login (the credentials were right) but is not a populated vault either.
    case signedIn(account: Account, sync: SyncResult?)
    case requiresTwoFactor(TwoFactorMethod)
}

/// Orchestrates the full account login flow:
/// validateServerURL → setServerEnvironment → loginWithPassword → (optional) two-factor → sync.
protocol LoginUseCase {
    func execute(
        serverURL: String,
        email: String,
        masterPassword: Data
    ) async throws -> LoginOutcome

    /// Completes whatever challenge the server asked for — an authenticator code, an emailed code,
    /// or a YubiKey tap. Named for the step, not for one of the three methods.
    ///
    /// Returns the sync outcome alongside the account for the same reason `execute` does: this is
    /// the other path that reaches the vault screen, and it must be able to say where that vault
    /// came from.
    func completeTwoFactor(
        code: String,
        rememberDevice: Bool
    ) async throws -> (account: Account, sync: SyncResult?)

    /// Asks the server to send another email code. Only meaningful for an email challenge.
    func sendEmailTwoFactorCode() async throws

    /// Cancels a pending challenge and clears in-memory key material held from
    /// the initial password-login step (see `AuthRepository.cancelTwoFactor`).
    func cancelTwoFactor()
}
