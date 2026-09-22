import SwiftUI

// MARK: - SecureNoteDetailView

/// Detail view for Secure Note items.
///
/// Displays the note body in a "Note" card and any custom fields in a
/// "Custom Fields" card. Both sections are hidden when their content is empty.
struct SecureNoteDetailView: View {

    let item:       VaultItem
    let secureNote: SecureNoteContent
    let onCopy:     (String) -> Void
    /// The gate for hidden custom fields. The note body is not gated (design D7).
    var gate: RevealGateBinding = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

                // Hidden for `.generic`, which is the default and the value the server sends for
                // notes that predate the field. A row reading "Generic" on every note would be noise
                // rather than information.
                if secureNote.subtype != .generic {
                    DetailSectionCard(L("Note")) {
                        FieldRowView(
                            label: L("Type"),
                            value: SecureNoteSubtypeLabel.name(for: secureNote.subtype),
                            itemId: item.id,
                            onCopy: onCopy
                        )
                    }
                }

                if let notes = secureNote.notes, !notes.isEmpty {
                    DetailSectionCard(L("Note")) {
                        FieldRowView(label: "", value: notes, itemId: item.id, isMultiLine: true, onCopy: onCopy)
                    }
                }

                if !secureNote.customFields.isEmpty {
                    DetailSectionCard(L("Custom Fields")) {
                        CustomFieldsSection(
                            fields: secureNote.customFields,
                            itemId: item.id,
                            onCopy: onCopy,
                            gate:   gate
                        )
                    }
                }
            }
    }
}
