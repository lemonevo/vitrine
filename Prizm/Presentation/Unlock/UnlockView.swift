import AppKit
import LocalAuthentication
import SwiftUI

// MARK: - UnlockView

/// The vault unlock screen shown to returning users (User Story 2, FR-003, FR-039).
///
/// Modelled after the macOS Passwords lock screen: app icon with the biometric sensor beneath it,
/// title "Prizm Is Locked", email inline in the subtitle, and the password field. Biometric unlock
/// auto-triggers on appearance.
///
/// **Built inside the same card as `LoginView`.** The two screens used to disagree about what they
/// looked like — login drew a stock `lock.shield.fill`, unlock drew the real application icon — for an
/// app that shows one of them on every single launch.
struct UnlockView: View {

    @ObservedObject var viewModel: UnlockViewModel

    @FocusState private var passwordFocused: Bool

    var body: some View {
        AuthCard {
            AuthHeader(title: L("Prizm Is Locked"), subtitle: subtitleText)

            // MARK: Password field / loading
            switch viewModel.flowState {
            case .loading:
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: Spacing.authFieldWidth, height: 34)
            case .syncing(let message):
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(Typography.screenBody)
                        .foregroundStyle(.secondary)
                }
                .frame(width: Spacing.authFieldWidth)
            default:
                VStack(spacing: 12) {
                    AuthField(label: L("Master password")) {
                        SecureField(L("Enter password"), text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                            .focused($passwordFocused)
                            .onSubmit { unlockIfReady() }
                            .accessibilityIdentifier(AccessibilityID.Unlock.passwordField)
                    }

                    // Offered only when the repository says so — which is also how the "require master
                    // password after a restart" setting is expressed, without this view knowing about it.
                    if viewModel.pinUnlockAvailable {
                        pinField
                    }

                    // **This button was not here.** Return was the only way to submit, and
                    // `isUnlockDisabled` was computed and then never shown to anyone — so the screen
                    // gave no indication that anything could be pressed, or that it was waiting for
                    // something. `biometric-unlock` forbids a *Touch ID* button, because the sensor is
                    // always armed and a button would imply a press; a submit control for the password
                    // path is a different thing, and its absence was simply a gap.
                    AuthPrimaryButton(title: L("Unlock"), isBusy: false, action: unlockIfReady)
                        .disabled(isUnlockDisabled)
                        .accessibilityIdentifier(AccessibilityID.Unlock.unlockButton)
                }
            }

            // MARK: Biometric sensor
            //
            // Its own row, not a badge over the icon: `LAAuthenticationView` has an intrinsic size the
            // SwiftUI `.frame` does not constrain, so overlaying it produced a fingerprint sticking out
            // past the shield. Not a button either — see the note above about the always-armed sensor.
            if viewModel.biometricUnlockAvailable {
                EmbeddedTouchIDView(context: viewModel.biometricContext)
                    .id(viewModel.biometricContextVersion)
                    .padding(.top, 14)
                    .accessibilityIdentifier(AccessibilityID.Unlock.biometricBadge)
            }

            // MARK: Error message
            if let error = viewModel.errorMessage {
                AuthErrorBanner(message: error, identifier: AccessibilityID.Unlock.errorMessage)
                    .padding(.top, 12)
            }

            Divider()
                .padding(.vertical, 16)

            // MARK: Sign in with a different account — FR-039
            //
            // Inside the card rather than pinned to the bottom edge of the window, where it used to
            // sit as far from the form as the layout could manage.
            Button {
                viewModel.signInWithDifferentAccount()
            } label: {
                Text(L("Sign in with a different account"))
                    .font(Typography.utility)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Unlock.switchAccount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        // Tall enough for the card with the PIN field, the sensor row and an error banner all showing
        // at once — the state a locked out user actually lands in. `.windowResizability(.contentSize)`
        // turns this into the window's minimum size.
        .frame(minWidth: 480, minHeight: 560)
        .onAppear { passwordFocused = true }
        // .task(id:) re-fires whenever biometricContextVersion changes (re-arm).
        // By the time the task runs, SwiftUI has re-rendered EmbeddedTouchIDView
        // with the new LAContext — so evaluatePolicy routes inline, not to a modal.
        .task(id: viewModel.biometricContextVersion) {
            viewModel.triggerEmbeddedBiometricIfAvailable()
        }
        .sheet(isPresented: $viewModel.showEnrollmentPrompt) {
            BiometricEnrollmentPromptView(
                reason: viewModel.enrollmentReason,
                onEnable: { viewModel.confirmEnrollBiometric() },
                onDismiss: { viewModel.dismissEnrollmentPrompt() }
            )
            .accessibilityIdentifier(AccessibilityID.Unlock.enrollmentPrompt)
        }
    }

    // MARK: - PIN

    /// The PIN entry, with its remaining-attempt count.
    ///
    /// The count is shown **only after a wrong try**, not pre-emptively: a bare "5 attempts left" on
    /// arrival reads as a threat. It is shown at all because a limit the user cannot see is a trap —
    /// someone on their fourth try of a code they half-remember deserves to know that.
    @ViewBuilder
    private var pinField: some View {
        AuthField(label: L("PIN")) {
            SecureField(L("PIN"), text: $viewModel.pin)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.unlockWithPIN() }
                .accessibilityIdentifier(AccessibilityID.Unlock.pinField)
        }

        if viewModel.shouldShowRemainingAttempts {
            Text(L("%d attempts left before the PIN is removed.", viewModel.pinRemainingAttempts))
                .font(Typography.listSubtitle)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(AccessibilityID.Unlock.pinAttemptsRemaining)
                .accessibilityLabel(L("%d attempts left before the PIN is removed.", viewModel.pinRemainingAttempts))
        }
    }

    // MARK: - Private

    private var isUnlockDisabled: Bool {
        if case .loading = viewModel.flowState { return true }
        return viewModel.password.isEmpty
    }

    private func unlockIfReady() {
        guard !isUnlockDisabled else { return }
        viewModel.unlock()
    }

    /// Subtitle varies by whether biometric unlock is available.
    private var subtitleText: String {
        if viewModel.biometricUnlockAvailable {
            return L("%@ or enter the password for %@ to unlock.", biometricMethodName, viewModel.email)
        } else {
            return L("Enter the password for %@ to unlock.", viewModel.email)
        }
    }

    // Sensor names are Apple product names and stay untranslated.
    private var biometricMethodName: String {
        switch LAContext().biometryType {
        case .touchID: return "Touch ID"
        case .faceID:  return "Face ID"
        default:       return L("Biometrics")
        }
    }
}
