import Foundation
import os.log

// MARK: - LoginUseCaseImpl

/// Orchestrates the full account login flow:
///   1. Validate + set server URL.
///   2. Call `AuthRepository.loginWithPassword`.
///   3. If `.success`: call `SyncRepository.sync` to populate the vault.
///   4. If `.requiresTwoFactor`: return immediately — sync is deferred to after the challenge.
///
/// `SyncRepository.sync` is called here (not inside `AuthRepository`) to keep the
/// Domain layer orchestration visible and testable at the use-case level.
final class LoginUseCaseImpl: LoginUseCase {

    private let auth: any AuthRepository
    private let sync: any SyncRepository

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "LoginUseCase")

    init(auth: any AuthRepository, sync: any SyncRepository) {
        self.auth = auth
        self.sync = sync
    }

    func execute(serverURL: String, email: String, masterPassword: Data) async throws -> LoginOutcome {
        // Step 1: Validate URL (throws AuthError.invalidURL on failure).
        try auth.validateServerURL(serverURL)

        // Step 2: Configure server environment.
        let trimmed = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        guard let url = URL(string: trimmed) else { throw AuthError.invalidURL }
        let environment = ServerEnvironment(base: url, overrides: nil)
        try await auth.setServerEnvironment(environment)

        // Step 3: Attempt password login.
        logger.info("Attempting login for \(email, privacy: .private)")
        let result = try await auth.loginWithPassword(email: email, masterPassword: masterPassword)

        switch result {
        case .success(let account):
            // Step 4: Sync vault immediately after successful login.
            // Sync is best-effort: if the server is temporarily unreachable the user
            // still lands in the vault browser showing items from the last sync.
            // Failing the entire login on a sync error would lock users out even when
            // the server is degraded — unacceptable for a password manager.
            logger.info("Login succeeded — starting vault sync")
            var syncResult: SyncResult?
            do {
                syncResult = try await sync.sync(progress: { _ in })
            } catch {
                logger.error("Post-login sync failed (non-fatal): \(error.localizedDescription, privacy: .public)")
            }
            return .signedIn(account: account, sync: syncResult)

        case .requiresTwoFactor(let method):
            // Sync is deferred until the challenge is answered. At this point we have derived the
            // master key but do not yet have an access token, so a sync request would be
            // rejected with 401. The vault populates after completeTwoFactor succeeds below.
            logger.info("Login requires 2FA")
            return .requiresTwoFactor(method)
        }
    }

    func completeTwoFactor(
        code: String,
        rememberDevice: Bool
    ) async throws -> (account: Account, sync: SyncResult?) {
        logger.info("Completing two-factor")
        let account = try await auth.loginWithTwoFactorCode(code, rememberDevice: rememberDevice)
        // Sync failure is non-fatal — the challenge was answered correctly, and failing here would
        // send the user back to a code that is now spent. The caller is told the vault was not
        // fetched so it does not report a sync that did not happen (FR-049).
        var syncResult: SyncResult?
        do {
            syncResult = try await sync.sync(progress: { _ in })
        } catch {
            logger.error("Post-2FA sync failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }
        return (account, syncResult)
    }

    func sendEmailTwoFactorCode() async throws {
        logger.info("Requesting another email code")
        try await auth.sendEmailTwoFactorCode()
    }

    func cancelTwoFactor() {
        auth.cancelTwoFactor()
    }
}
