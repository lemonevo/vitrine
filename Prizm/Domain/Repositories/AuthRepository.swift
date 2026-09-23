import Foundation

/// Manages authentication, session storage, and vault key lifecycle.
/// Implemented by `AuthRepositoryImpl` in the Data layer.
protocol AuthRepository: AnyObject {

    // MARK: - Server configuration

    /// The currently configured server environment, or nil if not yet set.
    var serverEnvironment: ServerEnvironment? { get }

    /// Validates that `urlString` is a well-formed http/https URL.
    /// - Throws: `AuthError.invalidURL` if the URL cannot be parsed or has no host.
    func validateServerURL(_ urlString: String) throws

    /// Persists `environment` and configures the API client base URL.
    func setServerEnvironment(_ environment: ServerEnvironment) async throws

    // MARK: - Login

    /// Performs the full login flow:
    /// 1. POST `/accounts/prelogin` → fetch KDF params.
    /// 2. Derive master key locally (PBKDF2 or Argon2id).
    /// 3. POST `/connect/token` → obtain access + refresh tokens.
    /// 4. Persist tokens + encrypted user key in Keychain.
    ///
    /// - Security goal: `masterPassword` is `Data` so the caller can zero the bytes
    ///   after the call returns, reducing heap exposure.
    /// - Returns: `.success(Account)` or `.requiresTwoFactor(method:)`.
    /// - Throws: `AuthError` on network or credential failure.
    func loginWithPassword(email: String, masterPassword: Data) async throws -> LoginResult

    /// Completes the pending two-factor challenge with the code the user supplied.
    ///
    /// The provider is not a parameter: it is the one the server asked for, remembered from
    /// `loginWithPassword`. Passing it in would let the caller answer with a different method
    /// than the one it prompted for, which the server would reject — and which no caller has any
    /// reason to want.
    ///
    /// - Parameters:
    ///   - code: The code, in the form the chosen provider produces it.
    ///   - rememberDevice: When true, the server suppresses future 2FA prompts for this device.
    /// - Returns: The authenticated `Account`.
    /// - Throws: `AuthError.invalidTwoFactorCode` on wrong code.
    func loginWithTwoFactorCode(_ code: String, rememberDevice: Bool) async throws -> Account

    /// Asks the server to send a fresh email code for the pending challenge.
    ///
    /// - Throws: `AuthError.invalidCredentials` when there is no pending challenge to resend for.
    ///   The email code is sent to an address the server already holds; the caller supplies
    ///   nothing, so a caller cannot redirect it.
    func sendEmailTwoFactorCode() async throws

    /// Cancels a pending TOTP challenge and discards the in-memory `PendingTwoFactor`
    /// state (stretched keys + password hash) held from the initial password login step.
    ///
    /// - Security goal: without this call the derived key material lives in memory until
    ///   the next login attempt or app restart. Call this whenever the
    ///   user dismisses the TOTP prompt without submitting a code.
    func cancelTwoFactor()

    // MARK: - Unlock

    /// Re-derives the symmetric key from `masterPassword` using stored KDF params.
    /// No network request is made — purely local crypto.
    ///
    /// - Security goal: `masterPassword` is `Data` so the caller can zero the bytes
    ///   after the call returns.
    /// - Returns: The unlocked `Account`.
    /// - Throws: `AuthError.invalidCredentials` on wrong password.
    func unlockWithPassword(_ masterPassword: Data) async throws -> Account

    /// Reports whether `masterPassword` is the master password of the current account.
    ///
    /// A re-derivation and a comparison, nothing more:
    ///
    /// - **No network request.** Everything needed (KDF parameters, the encrypted user key)
    ///   is already on disk.
    /// - **No session mutation.** The key cache, the account, the tokens and the vault store
    ///   are all left exactly as they were. `unlockWithPassword` would answer the same
    ///   question and would also re-derive into the live cache, refresh the access token and
    ///   leave the caller to undo none of that — a read-only check should not be built out
    ///   of a write (design D7).
    /// - **A wrong password is `false`, not a thrown error.** A wrong password fails the MAC
    ///   check on the encrypted user key, which is the expected answer to a question, not a
    ///   fault. Errors are reserved for "this could not be checked at all".
    ///
    /// - Throws: only when the check cannot be performed — no stored session, unreadable KDF
    ///   parameters, or a vault whose live key is not available to compare against.
    func verifyMasterPassword(_ masterPassword: Data) async throws -> Bool

    // MARK: - Session

    /// Returns the stored `Account` from Keychain, or nil if no session exists.
    func storedAccount() -> Account?

    /// Clears all per-user Keychain keys and resets in-memory state.
    /// Called on explicit sign-out. Triggers transition to blank `LoginView`.
    func signOut() async throws

    // MARK: - Lock

    /// Releases decrypted key material from `PrizmCryptoServiceImpl`.
    /// Does NOT clear Keychain tokens — session survives lock/unlock.
    func lockVault() async

    // MARK: - Biometric unlock

    /// Whether the device hardware supports biometric authentication, regardless of the
    /// user preference. Used by enrollment-offer logic which must check capability
    /// independently of whether the feature is enabled.
    var deviceBiometricCapable: Bool { get }

    /// Whether biometric unlock is available (enabled in preferences AND device supports biometrics).
    /// Fast synchronous check suitable for UI binding — does NOT read the Keychain.
    var biometricUnlockAvailable: Bool { get }

    /// Whether macOS itself enforces the biometric gate on the stored vault key.
    ///
    /// Distinct from `deviceBiometricCapable`, which only says the hardware works.
    /// `false` means the key is held in the legacy login Keychain and Prizm evaluates
    /// the Touch ID policy itself: the prompt is the same, but the protection is only
    /// as strong as this process. That is the case for any build without a real signing
    /// Team ID, because a `.biometryCurrentSet` item needs the `keychain-access-groups`
    /// entitlement. Settings states which of the two is in force.
    var biometricGateIsSystemEnforced: Bool { get }

    /// Stores the current vault symmetric key in a biometric-protected Keychain item.
    /// Requires the vault to be unlocked (keys in memory).
    /// - Throws: `AuthError.biometricUnavailable` if the vault is locked.
    func enableBiometricUnlock() async throws

    /// Deletes the biometric Keychain item and clears the preference.
    func disableBiometricUnlock() async throws

    /// Reads the vault key from the biometric Keychain item and unlocks the vault.
    /// - Returns: The unlocked `Account`.
    /// - Throws: `AuthError.biometricInvalidated` if biometric enrollment changed.
    func unlockWithBiometrics() async throws -> Account

    // MARK: - PIN unlock

    /// Whether the unlock screen should offer a PIN right now.
    ///
    /// False when no PIN is set, and false on a launch that has not seen a full authentication while
    /// `PinUnlockSettings.requiresMasterPasswordOnRestart` is on — which is its default. Locking and
    /// unlocking again within a launch is unaffected; that is the case a PIN exists for.
    var pinUnlockAvailable: Bool { get }

    /// Attempts left before the stored material is destroyed. Shown while entering a PIN: a limit the
    /// user cannot see is a trap rather than a protection.
    var pinUnlockRemainingAttempts: Int { get }

    /// Wraps the vault's current key material under a key derived from `pin`.
    ///
    /// - Throws: `AuthError.vaultLocked` when the vault is not unlocked — there is no key material to
    ///   wrap otherwise — and `PinUnlockError.pinTooShort` for a PIN below the minimum.
    func enablePinUnlock(pin: String) async throws

    /// Removes the stored PIN material.
    func disablePinUnlock() async throws

    /// Unlocks with `pin`.
    ///
    /// - Throws: `PinUnlockError.incorrectPin` for a wrong PIN, and `PinUnlockError.attemptsExhausted`
    ///   when that was the last permitted attempt — in which case the user has been signed out and
    ///   there is nothing left to retry.
    func unlockWithPIN(_ pin: String) async throws -> Account
}

// MARK: - Supporting types

nonisolated enum LoginResult {
    case success(Account)
    case requiresTwoFactor(TwoFactorMethod)
}

/// What the server asked for, once it has asked.
///
/// `challenge` carries a method Prizm can complete — always one of
/// `TwoFactorProvider.supportedOrder`, because that is the only way this case gets built.
/// `unsupported` carries the names of everything the server offered, so the error can say which
/// method it was instead of "unsupported method".
nonisolated enum TwoFactorMethod {
    case challenge(TwoFactorProvider)
    case unsupported(names: [String])

    /// The method to prompt for, when there is one.
    var provider: TwoFactorProvider? {
        if case .challenge(let provider) = self { return provider }
        return nil
    }
}

nonisolated enum AuthError: Error, LocalizedError, Equatable {
    case invalidCredentials
    case invalidTwoFactorCode
    /// A check that needed the stored session could not be performed because the session is
    /// missing or unreadable.
    ///
    /// Distinct from `invalidCredentials` on purpose: that case's message tells the user their
    /// password was wrong, which would be a lie here — nothing was compared.
    case noStoredSession
    case invalidURL
    case serverUnreachable
    case unrecognizedServer
    case networkUnavailable
    case unsupported2FAMethod(String)
    /// Biometric Keychain item was invalidated due to fingerprint enrollment change.
    case biometricInvalidated
    /// The sensor is locked by the system after repeated failures, so it will not evaluate at all
    /// until the user authenticates some other way.
    ///
    /// Distinct from a rejected finger: retrying is pointless until the master password has been
    /// entered, which is the one thing the message has to say. The wording is the one
    /// `openspec/specs/biometric-unlock/spec.md` mandates — until this case existed, that sentence
    /// lived only in the spec and in a UI test that could not fail.
    case biometricLockout
    /// Biometric Keychain item was deleted externally (Keychain Access, reinstall, etc.).
    /// Distinct from `biometricInvalidated` — no error is shown; the app silently falls back.
    case biometricItemNotFound
    /// Biometric unlock cannot be enabled — vault is locked (keys not in memory).
    /// The vault is locked, so an operation that needs live key material (setting a PIN) cannot run.
    case vaultLocked
    case biometricUnavailable
    /// Biometric unlock cannot be enabled on this build at all.
    ///
    /// The Keychain rejected the write with `errSecMissingEntitlement`: biometric storage
    /// needs the `keychain-access-groups` entitlement, which only a Team ID-signed build
    /// can carry. An ad-hoc signed build is permanently unable to use the feature.
    case biometricUnsupportedInBuild
    /// A stored secret could not be deleted when its feature was turned off.
    ///
    /// Said rather than logged-and-forgotten: for a PIN the leftover item is a wrapped vault key that a
    /// four-digit code unlocks, so "disabled" would be a claim the app cannot make. The setting is left
    /// on in that case — the key is still there, so the feature still works — which is what gives the
    /// user a switch to try again with.
    case secretRetirementFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return L("Invalid email or master password. Check your email and master password.")
        case .invalidTwoFactorCode:
            return L("Invalid two-factor code. Please try again.")
        case .noStoredSession:
            return L("No stored session was found. Sign in again to continue.")
        case .invalidURL:
            return L("Invalid server URL. Make sure to include https://.")
        case .serverUnreachable:
            return L("Cannot reach the server. Verify the URL and check your connection.")
        case .unrecognizedServer:
            return L("This server doesn't appear to be a Bitwarden instance.")
        case .networkUnavailable:
            return L("No internet connection. Check your network connection.")
        case .unsupported2FAMethod(let name):
            // No advice to "use an authenticator app" any more: a user whose account asks for
            // Duo cannot switch methods from here, so that sentence is not actionable — and it
            // reads as if the app had tried and failed rather than declined.
            return L("Vitrine cannot complete the two-factor method “%@”. Sign in from another Bitwarden client, or use one to change the method this account asks for.", name)
        case .biometricInvalidated:
            return L("Your Touch ID settings have changed. Please enter your master password to continue.")
        case .biometricLockout:
            return L("Too many failed Touch ID attempts — enter your master password")
        case .biometricItemNotFound:
            // Intentionally nil — this error is handled silently in UnlockViewModel.
            return nil
        case .vaultLocked:
            return L("Unlock the vault first.")
        case .biometricUnavailable:
            return L("Biometric unlock is not available. Please unlock with your master password.")
        case .biometricUnsupportedInBuild:
            return L("This build of Vitrine is not signed with an Apple Developer certificate, so macOS does not allow it to store the key Touch ID unlock needs.")
        case .secretRetirementFailed:
            return L("Vitrine could not delete the stored key, so this is still enabled. Try turning it off again.")
        }
    }
}
