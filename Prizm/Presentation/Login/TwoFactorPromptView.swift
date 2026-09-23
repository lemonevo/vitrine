import SwiftUI

// MARK: - TwoFactorPromptView

/// Two-factor prompt shown when the server requires a second step (FR-016, FR-050).
///
/// One screen for all three methods Prizm can complete, because the difference between them is
/// text and input rules, not a different flow: the code goes to the same endpoint either way, and
/// three near-identical views would have three chances to disagree about what the code means.
///
/// Uses the same `LoginViewModel` as `LoginView`; the VM transitions to `.vault` on success.
struct TwoFactorPromptView: View {

    @ObservedObject var viewModel: LoginViewModel

    /// The method the server asked for. Passed in rather than read from the view model's state so
    /// this view cannot be constructed for a method it has no text for.
    let provider: TwoFactorProvider

    @State private var code:           String = ""
    @State private var rememberDevice: Bool   = false
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            // MARK: Header
            VStack(spacing: 4) {
                Image(systemName: "key.2.on.ring.fill")
                    .font(Typography.screenIcon)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Two-step login")
                    .font(Typography.screenHeading)
                    .accessibilityIdentifier(AccessibilityID.TwoFactor.headerTitle)
                Text(provider.displayName)
                    .font(Typography.fieldLabelProminent)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.TwoFactor.methodName)
                if let instruction = provider.promptText {
                    Text(instruction)
                        .font(Typography.fieldLabel)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
            .padding(.top, 24)

            // MARK: Code field
            VStack(alignment: .leading, spacing: 4) {
                Text("Code")
                    .font(Typography.fieldLabelProminent)
                    .foregroundStyle(.secondary)
                TextField(text: $code, prompt: Text(field.placeholder)) {
                    Text("")
                }
                .textFieldStyle(.roundedBorder)
                .focused($codeFieldFocused)
                .frame(width: 260)
                .accessibilityIdentifier(AccessibilityID.TwoFactor.codeField)
                .onChange(of: code) { _, new in
                    code = sanitised(new)
                }
                .onSubmit { submitIfReady() }
            }

            // MARK: Resend — email only
            if provider.offersResend {
                Button {
                    viewModel.resendEmailCode()
                } label: {
                    if viewModel.isResendingCode {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 200)
                    } else {
                        Text("Resend code")
                            .frame(width: 200)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isResendingCode)
                .accessibilityIdentifier(AccessibilityID.TwoFactor.resendButton)
            }

            // MARK: Remember device — FR-050
            Toggle("Remember this device", isOn: $rememberDevice)
                .frame(width: 200, alignment: .leading)
                .accessibilityIdentifier(AccessibilityID.TwoFactor.rememberToggle)

            // MARK: Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(Typography.screenBody)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .accessibilityIdentifier(AccessibilityID.TwoFactor.errorMessage)
            }

            // MARK: Submit button
            Button(action: submitIfReady) {
                if case .loading = viewModel.flowState {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 200)
                } else {
                    Text("Continue")
                        .frame(width: 200)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitDisabled)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityIdentifier(AccessibilityID.TwoFactor.continueButton)

            // MARK: Cancel button
            // Cancelling clears in-memory key material (stretched keys + password hash)
            // that was retained from the initial password-login step.
            Button("Cancel") {
                viewModel.cancelTwoFactor()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(AccessibilityID.TwoFactor.cancelButton)

            Spacer()
        }
        .padding(.horizontal, Spacing.screenHorizontal)
        .padding(.bottom, 32)
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { codeFieldFocused = true }
    }

    // MARK: - Private helpers

    /// The rules for this method's code field.
    ///
    /// Forced rather than defaulted: this view is only ever built for a method Prizm can complete,
    /// and a silent fallback here would produce a field that accepts anything — a gate left open
    /// rather than a crash.
    private var field: TwoFactorProvider.CodeField {
        guard let field = provider.codeField else {
            preconditionFailure("TwoFactorPromptView built for \(provider), which has no code field")
        }
        return field
    }

    private var isSubmitDisabled: Bool {
        if case .loading = viewModel.flowState { return true }
        // No fixed length: an emailed code is as long as the server is configured to make it, and
        // a YubiKey code is a fixed 44 that the user does not type by hand.
        return code.isEmpty
    }

    private func sanitised(_ input: String) -> String {
        let allowed = field.allowed
        let kept = input.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(kept)).prefix(field.maximumLength).lowercased()
    }

    private func submitIfReady() {
        guard !isSubmitDisabled else { return }
        viewModel.submitTwoFactorCode(code, rememberDevice: rememberDevice)
    }
}
