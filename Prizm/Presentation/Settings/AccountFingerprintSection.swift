import AppKit
import SwiftUI

// MARK: - AccountFingerprintSection

/// The five words that identify this account's key pair, for comparing with another client.
///
/// **The phrase is not a secret**, and the copy here says so. That is the whole purpose of a
/// fingerprint: it is read aloud over the phone or pasted into a chat so two people can check they
/// are looking at the same key. A label that made it look sensitive would defeat it — the user
/// would hide the one value that has to be shared to be useful.
///
/// What it does not say is that the words come from the account's public key: true, and useless to
/// anyone reading this. What matters is the one action they enable — if this phrase differs from
/// the one another device shows, something between you and the server is not what you think.
struct AccountFingerprintSection: View {

    /// Asks the use case. Injected rather than called directly so the domain dependency stays out
    /// of the view (Constitution §II).
    let loadPhrase: @MainActor () async -> String?

    @State private var phrase: String?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(phrase ?? L("Not available yet"))
                    .font(Typography.fieldValue.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier(AccessibilityID.Fingerprint.phrase)

                Spacer(minLength: 0)

                Button {
                    copy()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .disabled(phrase == nil)
                .help(L("Copy the fingerprint phrase"))
                .accessibilityLabel(L("Copy the fingerprint phrase"))
                .accessibilityIdentifier(AccessibilityID.Fingerprint.copy)
            }

            Text(L("This is not a secret — read it aloud to compare. If it differs from the phrase another Bitwarden client shows for this account, you may not be talking to the same server."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.Fingerprint.note)
        }
        .task { await reload() }
    }

    // MARK: - Actions

    private func reload() async {
        phrase = await loadPhrase()
    }

    private func copy() {
        guard let phrase else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phrase, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopy = false
        }
    }
}
