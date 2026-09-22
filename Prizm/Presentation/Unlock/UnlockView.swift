import AppKit
import LocalAuthentication
import SwiftUI

// MARK: - UnlockView

/// The vault unlock screen shown to returning users (User Story 2, FR-003, FR-039).
///
/// Modelled after the macOS Passwords lock screen: the app icon, title "Vitrine Is Locked", email inline
/// in the subtitle, and the password field. A biometric unlock raises the **system** prompt — once
/// automatically when this screen appears, and afterwards whenever the user asks with the button.
///
/// **Built inside the same card as `LoginView`.** The two screens used to disagree about what they
/// looked like — login drew a stock `lock.shield.fill`, unlock drew the real application icon — for an
/// app that shows one of them on every single launch.
///
/// **One credential at a time.** The screen used to show a master-password box and a PIN box stacked at
/// the same weight, with nothing saying which to use and the PIN's remaining-attempts line sitting
/// under both. It now asks for one thing — whichever opened the vault last time on this launch — and
/// offers the other as a named switch. See `UnlockCredentialPreference` for why the default is not
/// saved to disk.
struct UnlockView: View {

    @ObservedObject var viewModel: UnlockViewModel

    @FocusState private var passwordFocused: Bool

    var body: some View {
        AuthCard {
            AuthHeader(title: L("Vitrine Is Locked"),
                       subtitle: viewModel.unlockInstructionText(
                           biometricName: viewModel.biometricUnlockAvailable ? biometricMethodName : nil
                       ))

            // MARK: Password field / loading
            switch viewModel.flowState {
            case .loading:
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: Spacing.authFieldWidth, height: Spacing.authProgressHeight)
            case .syncing(let message):
                VStack(spacing: Spacing.authProgressLabelGap) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(Typography.screenBody)
                        .foregroundStyle(Foreground.muted)
                }
                .frame(width: Spacing.authFieldWidth)
            default:
                VStack(spacing: Spacing.authFieldGap) {
                    credentialField

                    // **This button was not here.** Return was the only way to submit, and
                    // `isUnlockDisabled` was computed and then never shown to anyone — so the screen
                    // gave no indication that anything could be pressed, or that it was waiting for
                    // something. A form with a disabled-looking field and no visible commit control is
                    // a dead end until someone guesses the keyboard.
                    //
                    // It is also never greyed out for an empty field any more. A control that looks
                    // inert for the whole time the form is being filled teaches the user that the
                    // screen's one action is not for them; an empty submission is answered instead, in
                    // the banner, with the thing that is missing.
                    AuthPrimaryButton(title: L("Unlock"), isBusy: false, action: viewModel.submit)
                        .accessibilityIdentifier(AccessibilityID.Unlock.unlockButton)

                    // The alternative credential, named rather than drawn as a second field. Always
                    // visible when it exists, so which secret is being asked for is never hidden state.
                    if viewModel.pinUnlockAvailable {
                        Button(action: viewModel.toggleCredentialMethod) {
                            Label(viewModel.switchCredentialTitle,
                                  systemImage: "arrow.triangle.2.circlepath")
                                .font(Typography.utility)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Foreground.action)
                        .accessibilityIdentifier(AccessibilityID.Unlock.switchCredential)
                    }
                }

                // MARK: Biometric unlock
                //
                // A button, not a live sensor. The prompt is the system's own dialog now, so the
                // card needs only a way to raise it — and a button is honest about that, where the
                // fingerprint glyph invited a finger that would have done nothing.
                if viewModel.biometricUnlockAvailable {
                    Button {
                        viewModel.requestBiometricUnlock()
                    } label: {
                        Label(L("Unlock with %@", biometricMethodName),
                              systemImage: biometricSystemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier(AccessibilityID.Unlock.biometricButton)
                    .padding(.top, Spacing.authFieldGap)
                }
            }

            // MARK: Error message
            if let error = viewModel.errorMessage {
                AuthErrorBanner(message: error, identifier: AccessibilityID.Unlock.errorMessage)
                    .padding(.top, Spacing.authActionTopGap)
            }

            Divider()
                .padding(.vertical, Spacing.authDividerVertical)

            // MARK: Sign in with a different account — FR-039
            //
            // Inside the card rather than pinned to the bottom edge of the window, where it used to
            // sit as far from the form as the layout could manage.
            Button {
                viewModel.signInWithDifferentAccount()
            } label: {
                Text(L("Sign in with a different account"))
                    .font(Typography.utility)
                    .foregroundStyle(Foreground.muted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Unlock.switchAccount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        // Tall enough for the card with the PIN field, the Touch ID button and an error banner all
        // showing at once — the state a locked out user actually lands in.
        // `.windowResizability(.contentSize)` turns this into the window's minimum size.
        .frame(minWidth: 480, minHeight: 560)
        .onAppear { passwordFocused = true }
        // The field is the only thing on the screen that can take the typing, so after a switch it
        // still has it.
        .onChange(of: viewModel.credentialMethod) { passwordFocused = true }
        // Ask once, when the screen appears, so a returning user's fingerprint still opens the vault
        // without a click. `.task` rather than `.onAppear` so the prompt is raised after the view is
        // on screen, and once only — it has no `id:` to re-fire it, because re-arming a *modal* on
        // every dismissal is a loop. The button below is the retry.
        .task {
            viewModel.requestBiometricUnlock()
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

    // MARK: - Credential field

    /// The one credential being asked for, with the PIN's attempt count directly under it.
    ///
    /// The label comes from the view model rather than being written out per case, so the heading, the
    /// field and the submission cannot end up naming three different things.
    @ViewBuilder
    private var credentialField: some View {
        switch viewModel.credentialMethod {
        case .masterPassword:
            AuthField(label: viewModel.credentialFieldLabel) {
                SecureField(L("Enter password"), text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
                    .focused($passwordFocused)
                    .onSubmit(viewModel.submit)
                    .accessibilityIdentifier(AccessibilityID.Unlock.passwordField)
            }
        case .pin:
            pinField
        }
    }

    /// The PIN entry, with its remaining-attempt count.
    ///
    /// The count is shown **only after a wrong try**, not pre-emptively: a bare "5 attempts left" on
    /// arrival reads as a threat. It is shown at all because a limit the user cannot see is a trap —
    /// someone on their fourth try of a code they half-remember deserves to know that.
    @ViewBuilder
    private var pinField: some View {
        AuthField(label: viewModel.credentialFieldLabel) {
            SecureField(L("PIN"), text: $viewModel.pin)
                .textFieldStyle(.roundedBorder)
                .focused($passwordFocused)
                .onSubmit(viewModel.submit)
                .accessibilityIdentifier(AccessibilityID.Unlock.pinField)
        }

        if viewModel.shouldShowRemainingAttempts {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.fieldLabelGap) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Foreground.warning)
                    .accessibilityHidden(true)
                Text(L("%d attempts left before the PIN is removed.", viewModel.pinRemainingAttempts))
                    .font(Typography.listSubtitle)
                    .foregroundStyle(Foreground.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier(AccessibilityID.Unlock.pinAttemptsRemaining)
            .accessibilityLabel(L("%d attempts left before the PIN is removed.", viewModel.pinRemainingAttempts))
        }
    }

    // MARK: - Private

    /// The sensor this device reports, read once per render so the subtitle and the button cannot end
    /// up naming different things.
    private var biometryType: LABiometryType { LAContext().biometryType }

    /// Sensor names are Apple product names and stay untranslated.
    private var biometricMethodName: String {
        switch biometryType {
        case .touchID: return "Touch ID"
        case .faceID:  return "Face ID"
        default:       return L("Biometrics")
        }
    }

    private var biometricSystemImage: String {
        switch biometryType {
        case .touchID: return "touchid"
        case .faceID:  return "faceid"
        default:       return "person.badge.key"
        }
    }
}
