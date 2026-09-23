import SwiftUI

// MARK: - LoginView

/// The initial authentication screen (User Story 1, FR-001–FR-010).
///
/// Collects server URL, email, and master password, then initiates the login flow
/// via `LoginViewModel`. The view itself is stateless — all logic lives in the VM.
///
/// **Field order is deliberate.** The server address is set once and then never touched again, while
/// email and password are typed every single time. It used to sit at the top with the same weight as
/// the password, so the least-used field was the first thing a returning user had to look past. It is
/// now below a rule, at a smaller label — still a real field, still FR-001, no longer competing.
struct LoginView: View {

    @ObservedObject var viewModel: LoginViewModel

    /// Focus state used to advance through fields on Return, and to move to the field a rejected
    /// submission named. `LoginField` rather than a local enum: the view model reports what is
    /// missing in the same vocabulary the form is built from, so the two cannot drift apart.
    @FocusState private var focusedField: LoginField?

    var body: some View {
        VStack(spacing: Spacing.authFootnoteGap) {
            AuthCard {
                AuthHeader(title: L("Vitrine"),
                           subtitle: L("Sign in to your self-hosted vault"))

                VStack(spacing: Spacing.authFieldGap) {
                    AuthField(label: L("Email")) {
                        TextField("", text: $viewModel.email)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .accessibilityIdentifier(AccessibilityID.Login.emailField)
                    }

                    AuthField(label: L("Master password")) {
                        SecureField(L("Enter master password"), text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .password)
                            .onSubmit { viewModel.signIn() }
                            .accessibilityIdentifier(AccessibilityID.Login.passwordField)
                    }
                }

                if let error = viewModel.errorMessage {
                    AuthErrorBanner(message: error,
                                    identifier: AccessibilityID.Login.errorMessage)
                        .padding(.top, Spacing.authActionTopGap)
                }

                // Live from the start. The button used to disable itself until all three fields were
                // filled, so the screen's one action looked inert for the entire time a user was
                // filling the form — and a first-time visitor could not tell it was waiting for the
                // server address at the bottom. An incomplete submission is answered instead: the
                // banner names what is missing and the insertion point moves there.
                AuthPrimaryButton(title: L("Sign In"), isBusy: isBusy, action: viewModel.signIn)
                    .disabled(isBusy)
                    .accessibilityIdentifier(AccessibilityID.Login.signInButton)
                    .padding(.top, Spacing.authActionTopGap)

                Divider()
                    .padding(.vertical, Spacing.authDividerVertical)

                AuthField(label: L("Server"), hint: serverHint) {
                    HStack(spacing: Spacing.fieldLabelGap) {
                        Image(systemName: "server.rack")
                            .font(.caption)
                            .foregroundStyle(Foreground.muted)
                            .accessibilityHidden(true)
                        TextField("", text: $viewModel.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                            .focused($focusedField, equals: .serverURL)
                            .onSubmit { viewModel.signIn() }
                            .accessibilityIdentifier(AccessibilityID.Login.serverURLField)
                    }
                }
            }

            // Verified against the code before it was written here: `AuthRepositoryImpl` derives a
            // PBKDF2 server hash locally and `PrizmAPIClient.identityToken` sends *that* in the field
            // named `password`. The master password itself never goes on the wire. A claim this
            // pointed on a login screen should not be a guess.
            //
            // `Foreground.muted`, not `.secondary`: this is the sentence that tells a user their
            // password is safe, and at 10pt in `secondaryLabelColor` it measured 3.95:1 — under the
            // AA floor this project holds itself to.
            Text(L("Your master password is never sent to the server — only a hash derived from it."))
                .font(Typography.utility)
                .foregroundStyle(Foreground.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Spacing.authCardWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        // The card's own height plus the caption under it. `.windowResizability(.contentSize)` makes
        // this the smallest window the app can be shrunk to, so the number is the difference between
        // a form that fits and one that gets cut off at both ends — it is not a stylistic floor.
        .frame(minWidth: 480, minHeight: 520)
        .onAppear { focusedField = .email }
        .onChange(of: viewModel.fieldRequiringAttention) { _, field in
            focusedField = field
        }
    }

    // MARK: - Private helpers

    /// The example lives here rather than in the field's placeholder on purpose: a placeholder that
    /// reads as a URL is rendered by AppKit as a detected link — blue and underlined — which makes an
    /// empty field look pre-filled with something clickable.
    private var serverHint: String {
        viewModel.serverURL.isEmpty
            ? L("Required. For example https://vault.example.com")
            : L("The address of your Vaultwarden or Bitwarden server")
    }

    private var isBusy: Bool {
        if case .loading = viewModel.flowState { return true }
        return false
    }
}
