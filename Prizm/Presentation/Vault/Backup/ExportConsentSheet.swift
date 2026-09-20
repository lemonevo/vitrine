import SwiftUI

// MARK: - ExportConsentSheet

/// The mandatory consent shown before any vault export (design D2).
///
/// Constitution, Bitwarden normative standards: *"Export consent: User consent is mandatory before
/// any vault export operation."* The sheet therefore states the one fact that matters — the file is
/// plaintext — before the user is even asked where to put it, so that choosing a location cannot be
/// mistaken for the decision to export.
///
/// It also names what is **not** in the file. An export that silently omits attachments and
/// passkeys would be discovered only at restore time, which is the worst possible moment.
struct ExportConsentSheet: View {

    /// How many items will be written. Shown so the number is concrete rather than "your vault".
    let itemCount: Int

    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("Export Vault")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            Text(L("%d items will be written to a file on this Mac.", itemCount))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                bullet(L("The file is not encrypted. It contains every password, note, one-time-code seed and previous password in plain text."))
                bullet(L("Anyone who can read the file can read your vault."))
                bullet(L("Attachments and passkeys are not included. Items in Trash are not included."))
                bullet(L("Store it somewhere safe and delete it when you are done."))
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Export…", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        // The warning is the content, not decoration. Announcing the sheet makes a VoiceOver user
        // hear the risk before the confirm button, which is the same order a sighted user gets.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Export Vault"))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
