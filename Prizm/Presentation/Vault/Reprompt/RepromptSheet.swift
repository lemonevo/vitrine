import SwiftUI

// MARK: - RepromptSheet

/// Asks for the master password before one protected secret is shown or copied.
///
/// Four things here are deliberate, and each is the answer to a way this could quietly fail:
///
/// - **It cannot be dismissed by accident.** No close button, and interactive dismissal is
///   disabled. A sheet that vanishes without an answer grants nothing but leaves the user
///   believing they gave one.
/// - **A wrong password keeps it open**, unnamed as a failure of the sheet rather than of the
///   vault. The alternative — closing and leaving the secret hidden — is indistinguishable from
///   a cancel, and the spec asks for an error.
/// - **It names the item.** The grant is per item; a bare password prompt would read exactly like
///   an unlock and the user would not know what they were agreeing to.
/// - **The field is cleared after every submission,** so a retry starts from nothing rather than
///   from a near-miss the user has to edit.
struct RepromptSheet: View {

    @ObservedObject var viewModel: VaultBrowserViewModel

    @State private var password: String = ""
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Master password re-prompt"))
                .font(.headline)

            if let pending = viewModel.pendingReprompt {
                Text(L("“%@” is protected. Enter your master password to continue.", pending.itemName))
                    .font(Typography.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.Reprompt.itemName)
            }

            SecureField(L("Master password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($isPasswordFocused)
                .disabled(viewModel.isVerifyingReprompt)
                .accessibilityIdentifier(AccessibilityID.Reprompt.passwordField)
                .onSubmit { submit() }

            if let error = viewModel.repromptError {
                Text(error)
                    .font(Typography.utility)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.Reprompt.error)
            }

            HStack {
                Spacer()
                Button(L("Cancel")) { viewModel.cancelReprompt() }
                    .accessibilityIdentifier(AccessibilityID.Reprompt.cancelButton)
                if viewModel.isVerifyingReprompt {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 4)
                }
                Button(L("Confirm")) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || viewModel.isVerifyingReprompt)
                    .accessibilityIdentifier(AccessibilityID.Reprompt.confirmButton)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { isPasswordFocused = true }
        // Esc is an explicit cancel, never a silent one.
        .onExitCommand { viewModel.cancelReprompt() }
        .interactiveDismissDisabled()
    }

    private func submit() {
        // `Data` so the bytes can be zeroed rather than left in a String literal the ARC release
        // schedule decides (Constitution §III).
        var buffer = Data(password.utf8)
        viewModel.submitReprompt(buffer)
        buffer.resetBytes(in: 0..<buffer.count)
        password = ""
    }
}
