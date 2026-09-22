import SwiftUI

// MARK: - SecureNoteEditForm

/// Edit form for Secure Note vault items.
///
/// Shows the subtype picker, an editable Note text field and the existing custom fields section.
struct SecureNoteEditForm: View {

    @Binding var draft: DraftSecureNoteContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                DetailSectionCard(L("Note")) {
                    SubtypePicker(subtype: $draft.subtype)
                    Divider()
                    OptionalEditFieldRow(label: L("Note"), value: $draft.notes)
                }

                CustomFieldsEditSection(fields: $draft.customFields, itemType: .secureNote)
            }
        }
    }
}

// MARK: - SubtypePicker

/// Picks the note's subtype.
///
/// The selection is driven by `SecureNoteSubtype.selectable`, and a stored value that is not in that
/// list — one set by a build that knows more subtypes than this one — is added to the options rather
/// than being coerced to Generic. Opening the form must not rewrite what it does not recognise.
private struct SubtypePicker: View {

    @Binding var subtype: SecureNoteSubtype

    private var options: [SecureNoteSubtype] {
        SecureNoteSubtype.selectable.contains(subtype)
            ? SecureNoteSubtype.selectable
            : SecureNoteSubtype.selectable + [subtype]
    }

    var body: some View {
        HStack {
            Text(L("Type"))
                .font(Typography.fieldLabel)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Picker("", selection: $subtype) {
                ForEach(options, id: \.rawValue) { option in
                    Text(SecureNoteSubtypeLabel.name(for: option)).tag(option)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier(AccessibilityID.Vault.itemEditNoteSubtype)
            Spacer()
        }
        .padding(.vertical, Spacing.rowVertical)
        .padding(.horizontal, Spacing.rowHorizontal)
    }
}
