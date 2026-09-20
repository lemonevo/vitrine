import Foundation

/// Orchestrates the full account login flow:
/// validateServerURL → setServerEnvironment → loginWithPassword → (optional) two-factor → sync.
protocol LoginUseCase {
    func execute(
        serverURL: String,
        email: String,
        masterPassword: Data
    ) async throws -> LoginResult

    /// Completes whatever challenge the server asked for — an authenticator code, an emailed code,
    /// or a YubiKey tap. Named for the step, not for one of the three methods.
    func completeTwoFactor(code: String, rememberDevice: Bool) async throws -> Account

    /// Asks the server to send another email code. Only meaningful for an email challenge.
    func sendEmailTwoFactorCode() async throws

    /// Cancels a pending challenge and clears in-memory key material held from
    /// the initial password-login step (see `AuthRepository.cancelTwoFactor`).
    func cancelTwoFactor()
}
