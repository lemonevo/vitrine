import SwiftUI

// MARK: - SSHAgentAuthorizationSheet

/// Asks for the master password before an SSH key is used to sign.
///
/// The same four decisions as `RepromptSheet`, for the same reasons — it cannot be dismissed by
/// accident, a wrong password keeps it open, the field is cleared after every submission — plus one
/// this sheet has and that one does not:
///
/// - **It names the requester.** `git` and a script someone was talked into running are
///   indistinguishable on the wire. A prompt that only names the key teaches the user to approve
///   without reading, which is the same as having no prompt.
struct SSHAgentAuthorizationSheet: View {

    @ObservedObject var authorizer: SSHAgentAuthorizer

    @State private var password: String = ""
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("SSH signature request"))
                .font(.headline)

            if let pending = authorizer.pending {
                Text(description(for: pending))
                    .font(Typography.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.SSHAgent.requestDescription)
            }

            SecureField(L("Master password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($isPasswordFocused)
                .disabled(authorizer.isVerifying)
                .accessibilityIdentifier(AccessibilityID.SSHAgent.passwordField)
                .onSubmit { submit() }

            if let error = authorizer.error {
                Text(error)
                    .font(Typography.utility)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.SSHAgent.error)
            }

            HStack {
                Spacer()
                Button(L("Cancel")) { authorizer.cancel() }
                    .accessibilityIdentifier(AccessibilityID.SSHAgent.cancelButton)
                if authorizer.isVerifying {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 4)
                }
                Button(L("Confirm")) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || authorizer.isVerifying)
                    .accessibilityIdentifier(AccessibilityID.SSHAgent.confirmButton)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { isPasswordFocused = true }
        // Esc is an explicit cancel, never a silent one.
        .onExitCommand { authorizer.cancel() }
        .interactiveDismissDisabled()
    }

    /// Names the requester when the kernel named it, and says so plainly when it did not.
    ///
    /// The fallback is a sentence rather than a placeholder like "unknown process": the user is
    /// being asked to approve a signature, and "an application" is the honest answer to "which
    /// one?" when there is not one.
    private func description(for request: SSHAgentAuthorizer.Request) -> String {
        if let process = request.process {
            return L("“%@” asked Prizm to sign with the SSH key “%@”.", process, request.itemName)
        }
        return L("An application asked Prizm to sign with the SSH key “%@”.", request.itemName)
    }

    private func submit() {
        // `Data` so the bytes can be zeroed rather than left in a String literal the ARC release
        // schedule decides (Constitution §III).
        var buffer = Data(password.utf8)
        authorizer.submit(buffer)
        buffer.zeroize()
        password = ""
    }
}
