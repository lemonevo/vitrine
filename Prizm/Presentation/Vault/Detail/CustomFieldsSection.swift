import SwiftUI

// MARK: - CustomFieldsSection

/// Renders a list of custom fields for any item type (FR-029).
///
/// - `text` fields: visible, copyable.
/// - `hidden` fields: masked, revealable.
/// - `boolean` fields: checkbox icon (read-only in v1).
/// - `linked` fields: shown as read-only label with linked field name.
struct CustomFieldsSection: View {

    let fields: [CustomField]
    let itemId: String
    let onCopy: (String) -> Void

    /// The gate for hidden custom fields. Revealing one is among the disclosures the spec gates,
    /// so this applies to every item type that carries such a field — not only to logins.
    var gate: RevealGateBinding = .none

    var body: some View {
        if fields.isEmpty { EmptyView() } else {
            ForEach(fields.indices, id: \.self) { index in
                let field = fields[index]
                customFieldRow(field)
                if index < fields.indices.last! {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func customFieldRow(_ field: CustomField) -> some View {
        switch field.type {
        case .text:
            FieldRowView(
                label:  field.name,
                value:  field.value,
                itemId: itemId,
                onCopy: onCopy
            )

        case .hidden:
            FieldRowView(
                label:            field.name,
                value:            field.value,
                itemId:           itemId,
                isMasked:         true,
                onCopy:           onCopy,
                gate:             gate
            )

        case .boolean:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.name)
                        .font(Typography.fieldLabel)
                        .foregroundStyle(Foreground.muted)
                    Image(systemName: field.value == "true" ? "checkmark.square" : "square")
                        .imageScale(.medium)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.rowVertical)
            .padding(.horizontal, Spacing.rowHorizontal)

        case .linked:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.name)
                        .font(Typography.fieldLabel)
                        .foregroundStyle(Foreground.muted)
                    Text("→ \(field.linkedId?.displayName ?? "Unknown Field")")
                        .font(Typography.fieldValue)
                        .foregroundStyle(Foreground.muted)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.rowVertical)
            .padding(.horizontal, Spacing.rowHorizontal)
        }
    }
}
