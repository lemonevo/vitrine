import Combine
import Foundation
import os.log

// MARK: - LoginFlowState

/// State machine driving the root view transition.
enum LoginFlowState: Equatable {
    case login
    case loading
    /// The method is carried in the state rather than held alongside it: a prompt for an emailed
    /// code and a prompt for a YubiKey tap are different screens, and the two cannot disagree
    /// about which one is being shown if there is only one value.
    case twoFactorPrompt(TwoFactorProvider)
    case syncing(message: String)
    case vault
}

// MARK: - LoginField

/// The three values the login form collects, in the order the user meets them.
enum LoginField: String, CaseIterable {
    case serverURL, email, password
}

// MARK: - LoginViewModel

/// ViewModel for the login + 2FA + sync flow (User Story 1).
///
/// The Presentation layer uses the Domain protocols directly (`AuthRepository`, `SyncUseCase`)
/// so it can report per-step progress to the UI.  No Data-layer types are imported here.
@MainActor
final class LoginViewModel: ObservableObject {

    // MARK: - Published state

    @Published var serverURL:    String = ""
    @Published var email:        String = ""
    @Published var password:     String = ""
    @Published var errorMessage: String?
    /// Set while a resend is in flight, so the button can say so. Only an email challenge has one.
    @Published private(set) var isResendingCode: Bool = false
    @Published private(set) var flowState: LoginFlowState = .login

    /// The field a submission was missing, so the view can put the insertion point where the message
    /// points.
    ///
    /// The form used to answer an incomplete submission by greying out its own submit button, which
    /// told the user nothing about what was missing and made the screen's one action look inert for
    /// the whole time they were filling it in.
    @Published private(set) var fieldRequiringAttention: LoginField?

    /// What the vault sync that follows a successful login produced, or `nil` when it failed.
    ///
    /// Read at the `.vault` transition, which has to report where the vault on screen came from.
    /// `nil` is meaningful rather than a gap to be filled in with a fresh date: it means the server
    /// could not be reached after the credentials were accepted, and the timestamp shown to the user
    /// must not claim otherwise.
    private(set) var lastSyncResult: SyncResult?

    // MARK: - Dependencies

    private let loginUseCase: any LoginUseCase
    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "LoginViewModel")

    // MARK: - Init

    init(loginUseCase: any LoginUseCase) {
        self.loginUseCase = loginUseCase
    }

    // MARK: - Actions

    /// Validates the form and initiates the login sequence.
    func signIn() {
        guard flowState != .loading else { return }
        errorMessage = nil

        // Answered here rather than by a disabled button: the first thing missing, named, with the
        // insertion point moved to it.
        if let missing = firstMissingField {
            fieldRequiringAttention = missing
            errorMessage = switch missing {
            case .serverURL: L("Enter the address of your server.")
            case .email:     L("Enter your email address.")
            case .password:  L("Enter your master password.")
            }
            logger.error("Sign-in refused: \(missing.rawValue, privacy: .public) is empty")
            return
        }
        fieldRequiringAttention = nil

        logger.info("Sign-in flow started")
        flowState    = .loading

        // Convert the password String to Data at this boundary — the only place the
        // String-to-bytes conversion happens. `Data` can be zeroed after the KDF call;
        // `String` cannot (Constitution §III).
        guard var passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
            errorMessage = L("Invalid password encoding.")
            flowState    = .login
            return
        }

        Task {
            // The view model owns these bytes and no one else can release them: `Data` is
            // copy-on-write, so zeroizing inside the repository would only touch a private copy.
            defer { passwordData.zeroize() }
            do {
                let result = try await loginUseCase.execute(
                    serverURL:      serverURL,
                    email:          email,
                    masterPassword: passwordData
                )

                switch result {
                case .signedIn(_, let syncResult):
                    // Clear the password field so the plaintext does not linger in
                    // the published property (and therefore the SwiftUI state graph).
                    password  = ""
                    lastSyncResult = syncResult
                    flowState = .vault

                case .requiresTwoFactor(let method):
                    guard let provider = method.provider else {
                        if case .unsupported(let names) = method {
                            // Every name the server offered, so the message says what the account
                            // actually asks for instead of naming one method at random.
                            throw AuthError.unsupported2FAMethod(names.joined(separator: ", "))
                        }
                        throw AuthError.invalidCredentials
                    }
                    password  = ""
                    flowState = .twoFactorPrompt(provider)
                }

            } catch let err as AuthError {
                logger.error("Sign-in failed: \(err.localizedDescription, privacy: .public)")
                errorMessage = err.errorDescription
                flowState    = .login
            } catch {
                logger.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
                flowState    = .login
            }
        }
    }

    /// Cancels the pending challenge and returns to the login screen.
    func cancelTwoFactor() {
        loginUseCase.cancelTwoFactor()
        flowState = .login
    }

    /// Completes the pending challenge with the code the user entered.
    ///
    /// The provider comes from the current state, so a retry after a rejected code is always for
    /// the method the user was shown — even if the server has, in the meantime, been asked for
    /// something else.
    func submitTwoFactorCode(_ code: String, rememberDevice: Bool) {
        guard case .twoFactorPrompt(let provider) = flowState else { return }
        logger.info("Submitting \(provider.displayName, privacy: .public) code")
        errorMessage = nil
        flowState    = .loading

        Task {
            do {
                let outcome = try await loginUseCase.completeTwoFactor(code: code, rememberDevice: rememberDevice)
                lastSyncResult = outcome.sync
                flowState = .vault
            } catch let err as AuthError {
                logger.error("2FA submission failed: \(err.localizedDescription, privacy: .public)")
                errorMessage = err.errorDescription
                flowState    = .twoFactorPrompt(provider)
            } catch {
                logger.error("2FA submission failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
                flowState    = .twoFactorPrompt(provider)
            }
        }
    }

    /// Asks the server for another emailed code.
    ///
    /// A failure here is shown on the same screen rather than ending the challenge: the user is
    /// mid-login with a valid pending challenge, and dropping them back to the password screen to
    /// read "could not send" would cost them the code they already have.
    func resendEmailCode() {
        guard case .twoFactorPrompt(let provider) = flowState, provider.offersResend else { return }
        isResendingCode = true
        errorMessage    = nil

        Task {
            defer { isResendingCode = false }
            do {
                try await loginUseCase.sendEmailTwoFactorCode()
                logger.info("Email code resent")
            } catch {
                logger.error("Resend failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
                flowState    = .twoFactorPrompt(provider)
            }
        }
    }

    // MARK: - Validation

    /// The first required value that has not been given, in the order the form presents them.
    ///
    /// Whitespace alone does not count as an answer, and only the emptiness test trims — what the
    /// user typed reaches the server unchanged.
    private var firstMissingField: LoginField? {
        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if blank(serverURL) { return .serverURL }
        if blank(email)     { return .email }
        if password.isEmpty { return .password }
        return nil
    }
}
