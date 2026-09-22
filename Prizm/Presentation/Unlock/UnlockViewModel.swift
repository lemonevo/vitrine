import Combine
import Foundation
import os.log

// MARK: - UnlockFlowState

enum UnlockFlowState: Equatable {
    case unlock
    case loading
    case syncing(message: String)
    case vault
    /// Returned to login (triggered by "Sign in with a different account").
    case login
}

// MARK: - UnlockViewModel

/// ViewModel for the vault unlock screen (User Story 2).
///
/// The user has a stored session; this screen re-derives the vault key from the
/// master password locally (no network call) then re-syncs the vault.
@MainActor
final class UnlockViewModel: ObservableObject {

    // MARK: - Published state

    @Published var password:        String = ""
    /// The PIN entry. Separate from `password` so the two fields cannot be confused by a stray
    /// keystroke, and so clearing one on success cannot silently clear the other's meaning.
    @Published var pin:             String = ""
    @Published var errorMessage:    String?
    @Published private(set) var flowState: UnlockFlowState = .unlock
    @Published var showEnrollmentPrompt: Bool = false
    @Published private(set) var enrollmentReason: EnrollmentReason = .firstTime

    // MARK: - Dependencies

    private let auth:             any AuthRepository
    private let sync:             any SyncUseCase
    private let account:          Account
    private let logger = Logger(subsystem: "com.prizm", category: "UnlockViewModel")

    /// Tracks whether the last biometric attempt failed with invalidation,
    /// so the enrollment prompt can show the re-enroll copy.
    private var lastBiometricInvalidated = false

    /// Whether a system biometric prompt is up right now.
    ///
    /// Not published, because the button that raises it does not change appearance: this exists to
    /// swallow a second request, not to disable a control. Each `evaluatePolicy` raises its own
    /// dialog, so two clicks would mean two dialogs dismissed one at a time.
    private var isBiometricPromptInFlight = false

    // MARK: - Init

    init(
        auth: any AuthRepository,
        sync: any SyncUseCase,
        account: Account
    ) {
        self.auth              = auth
        self.sync              = sync
        self.account           = account
    }

    // MARK: - Derived properties

    /// The stored email, shown read-only in the UI (FR-003).
    var email: String { account.email }

    /// Whether biometric unlock is available for this device and session.
    var biometricUnlockAvailable: Bool { auth.biometricUnlockAvailable }

    /// Whether the PIN should be offered at all.
    ///
    /// Answered by the repository, which knows both whether a PIN exists and whether this launch has
    /// had a full authentication — the setting that keeps a four-digit code from opening a
    /// freshly-restarted app.
    var pinUnlockAvailable: Bool { auth.pinUnlockAvailable }

    /// Attempts left before the stored material is destroyed. Rendered while entering a PIN: a limit
    /// the user cannot see is a trap rather than a protection.
    var pinRemainingAttempts: Int { auth.pinUnlockRemainingAttempts }

    /// Whether the attempt count is worth showing — i.e. the user has already got one wrong.
    var shouldShowRemainingAttempts: Bool { pinRemainingAttempts < PinUnlockSettings.maximumAttempts }

    // MARK: - Actions

    func unlock() {
        logger.info("Unlock flow started")
        errorMessage = nil
        flowState    = .loading

        // Convert the password String to Data at this boundary so the KDF stack
        // receives `Data` that can be zeroed after use (Constitution §III).
        guard let passwordData = password.data(using: .utf8) else {
            errorMessage = "Invalid password encoding."
            flowState    = .unlock
            return
        }

        Task {
            do {
                _ = try await auth.unlockWithPassword(passwordData)
                // Clear the password field after a successful unlock so the plaintext
                // does not linger in the published property.
                password = ""
                await checkEnrollmentOrSync()
            } catch let err as AuthError {
                logger.error("Unlock failed: \(err.localizedDescription, privacy: .public)")
                errorMessage = err.errorDescription
                flowState    = .unlock
            } catch {
                logger.error("Unlock failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
                flowState    = .unlock
            }
        }
    }

    /// Unlocks with the PIN.
    ///
    /// Kept separate from `unlock()` rather than folded into it: the two take different inputs, fail in
    /// different ways, and the PIN's failure carries a count that the password's does not.
    func unlockWithPIN() {
        guard !pin.isEmpty else { return }
        logger.info("PIN unlock flow started")
        errorMessage = nil
        flowState    = .loading
        let enteredPIN = pin

        Task {
            do {
                _ = try await auth.unlockWithPIN(enteredPIN)
                pin = ""
                await checkEnrollmentOrSync()
            } catch let err as PinUnlockError {
                logger.error("PIN unlock failed: \(err.localizedDescription, privacy: .public)")
                errorMessage = err.errorDescription
                pin = ""
                flowState = .unlock
                if err == .attemptsExhausted {
                    // The session is gone, so this screen has nothing left to unlock. The repository
                    // has already signed out; the app's flow observer moves us to sign-in.
                    return
                }
            } catch {
                logger.error("PIN unlock failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
                pin = ""
                flowState = .unlock
            }
        }
    }

    /// Raises the system biometric prompt once.
    ///
    /// Deliberately not repeated on cancellation. The sensor used to be kept "always armed" — every
    /// cancel immediately triggered another evaluation — which was tolerable while the prompt was an
    /// icon inside this window, and is not now that it is a modal: a modal that reappears the moment
    /// the user dismisses it is a loop they cannot leave. The button is the retry, so retrying is the
    /// user's call.
    ///
    /// A missing Keychain item degrades silently — the repository has already cleared the flag, so
    /// `biometricUnlockAvailable` answers false and the button goes with it.
    func requestBiometricUnlock() {
        guard biometricUnlockAvailable, !isBiometricPromptInFlight else { return }
        logger.info("Biometric unlock requested")
        isBiometricPromptInFlight = true

        Task {
            defer { isBiometricPromptInFlight = false }
            do {
                _ = try await auth.unlockWithBiometrics()
                lastBiometricInvalidated = false
                await checkEnrollmentOrSync()
            } catch let err as AuthError where err == .biometricInvalidated {
                lastBiometricInvalidated = true
                errorMessage = err.errorDescription
                flowState    = .unlock
            } catch let err as AuthError where err == .biometricItemNotFound {
                flowState = .unlock
            } catch let err as NSError
                where err.domain == NSOSStatusErrorDomain && err.code == Int(errSecUserCanceled) {
                // Dismissed. No message — nothing went wrong — and the password field stays
                // usable in parallel, which is the point of a prompt that can be declined.
                flowState = .unlock
            } catch {
                // Lockout or other failure.
                errorMessage = error.localizedDescription
                flowState    = .unlock
            }
        }
    }

    /// Called when the user accepts the enrollment prompt.
    func confirmEnrollBiometric() {
        Task {
            do {
                try await auth.enableBiometricUnlock()
            } catch {
                logger.error("Enable biometric unlock failed: \(error.localizedDescription, privacy: .public)")
            }
            UserDefaults.standard.set(true, forKey: "biometricEnrollmentPromptShown")
            showEnrollmentPrompt = false
            await performSync()
        }
    }

    /// Called when the user dismisses the enrollment prompt without enabling.
    func dismissEnrollmentPrompt() {
        UserDefaults.standard.set(true, forKey: "biometricEnrollmentPromptShown")
        showEnrollmentPrompt = false
        Task { await performSync() }
    }

    /// Clears session and returns to the login screen (FR-039).
    func signInWithDifferentAccount() {
        logger.info("User switching to different account")
        Task {
            do {
                try await auth.signOut()
            } catch {
                logger.error("Sign-out failed: \(error.localizedDescription, privacy: .public)")
            }
            flowState = .login
        }
    }

    // MARK: - Private

    /// After a successful unlock, checks whether to show the enrollment prompt sheet
    /// before proceeding to sync.
    ///
    /// Uses `auth.deviceBiometricCapable` (not `biometricUnlockAvailable`) so the check
    /// is mockable in tests and independent of the UserDefaults enabled flag.
    private func checkEnrollmentOrSync() async {
        let capable        = auth.deviceBiometricCapable
        let alreadyEnabled = UserDefaults.standard.bool(forKey: "biometricUnlockEnabled")
        let promptShown    = UserDefaults.standard.bool(forKey: "biometricEnrollmentPromptShown")

        if capable && !alreadyEnabled && !promptShown {
            enrollmentReason    = lastBiometricInvalidated ? .reEnrollAfterInvalidation : .firstTime
            showEnrollmentPrompt = true
            // performSync() will be called by confirmEnrollBiometric() or dismissEnrollmentPrompt().
            return
        }
        await performSync()
    }

    /// The outcome of the sync that follows a successful unlock.
    ///
    /// Non-nil exactly when `.vault` is reachable: the transition and the result come from the same
    /// statement, so the screen that shows the vault cannot be reached without an answer to "where
    /// did this data come from".
    private(set) var lastSyncResult: SyncResult?

    private func performSync() async {
        flowState = .syncing(message: L("Preparing…"))
        do {
            let result = try await sync.execute(progress: { [weak self] message in
                Task { @MainActor [weak self] in self?.flowState = .syncing(message: message) }
            })
            lastSyncResult = result
            flowState = .vault
        } catch {
            // The vault could not be fetched and there was no cached copy to fall back to. Showing
            // an empty vault here is the worst outcome available: it is indistinguishable from "all
            // my items are gone", and it invites the user to act on that belief. Stay on this screen
            // and say why — the password is already known to be correct, so the error is the only
            // thing left to report.
            logger.error("Post-unlock sync failed with no cache to fall back to: \(error.localizedDescription, privacy: .public)")
            lastSyncResult = nil
            errorMessage = error.localizedDescription
            flowState = .unlock
        }
    }
}
