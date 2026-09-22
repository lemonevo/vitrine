import SwiftUI

// MARK: - SSHKeyEditForm

/// Edit form for SSH Key vault items.
///
/// Private key is masked by default (same treatment as Login password and Hidden
/// custom fields — spec §4.9). Key fingerprint is read-only because it is derived from the key,
/// not because it is unsent: it is round-tripped to the server on save.
struct SSHKeyEditForm: View {

    @Binding var draft: DraftSSHKeyContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                DetailSectionCard(L("SSH Key")) {
                    // Private key is sensitive — masked by default with reveal toggle.
                    MaskedEditFieldRow(label: L("Private Key"), value: $draft.privateKey)
                    Divider()
                    OptionalEditFieldRow(label: L("Public Key"), value: $draft.publicKey)
                    Divider()
                    // Key fingerprint is derived from the key; shown for reference only.
                    readOnlyFingerprintRow
                }

                DetailSectionCard(L("Notes")) {
                    OptionalEditFieldRow(label: L("Notes"), value: $draft.notes)
                }

                CustomFieldsEditSection(fields: $draft.customFields, itemType: .sshKey)
            }
        }
    }

    @ViewBuilder
    private var readOnlyFingerprintRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Key Fingerprint")
                    .font(Typography.fieldLabel)
                    .foregroundStyle(.secondary)
                Text(draft.keyFingerprint ?? "—")
                    .font(Typography.fieldValue.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.rowVertical)
        .padding(.horizontal, Spacing.rowHorizontal)
    }
}
