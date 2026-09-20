import SwiftUI

// MARK: - CustomFieldsEditSection

/// Editable rows for a vault item's custom fields.
///
/// Supports the full lifecycle: add, rename, change type, reorder and delete. Field order in this
/// list is the order sent to the server, so reordering is persisted.
///
/// Rows are identified by `DraftCustomField.id` rather than by index. Index identity is safe for a
/// read-only list but not for one that can be reordered or have rows removed: SwiftUI would hand
/// the removed row's `@State` — such as whether a hidden value is revealed — to whichever field
/// moved into that position.
struct CustomFieldsEditSection: View {

    /// Binding into the parent draft's `customFields` array.
    @Binding var fields: [DraftCustomField]

    /// The item type these fields belong to. Determines which native fields a linked custom field
    /// may point at, and whether "linked" is offered at all.
    let itemType: ItemType

    var body: some View {
        if fields.isEmpty {
            // No header when there is nothing to head — but the add affordance stays available,
            // otherwise a field could never be added to an item that has none.
            addButton
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.cardTop)
        } else {
            DetailSectionCard(L("Custom Fields")) {
                ForEach($fields) { $field in
                    CustomFieldEditRow(
                        field: $field,
                        itemType: itemType,
                        canMoveUp: fields.first?.id != field.id,
                        canMoveDown: fields.last?.id != field.id,
                        onMoveUp: { move(field.id, by: -1) },
                        onMoveDown: { move(field.id, by: 1) },
                        onDelete: { delete(field.id) }
                    )

                    Divider()
                }

                addButton
            }
        }
    }

    // MARK: - Actions

    private var addButton: some View {
        Button {
            fields.append(DraftCustomField())
        } label: {
            Label("Add Field", systemImage: "plus")
                .font(Typography.fieldValue)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .padding(.vertical, Spacing.rowVertical)
        .padding(.horizontal, Spacing.rowHorizontal)
        .accessibilityIdentifier(AccessibilityID.Edit.addCustomFieldButton)
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard fields.indices.contains(target) else { return }
        fields.swapAt(index, target)
    }

    private func delete(_ id: UUID) {
        fields.removeAll { $0.id == id }
    }
}

// MARK: - CustomFieldEditRow

/// A single editable row: the field's name, its type, its value, and its row controls.
private struct CustomFieldEditRow: View {

    @Binding var field: DraftCustomField
    let itemType: ItemType
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    /// Controls reveal state for Hidden fields (masked by default — spec §4.9).
    @State private var isRevealed = false

    private var rowId: String { field.id.uuidString }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            valueEditor
        }
        .padding(.vertical, Spacing.rowVertical)
        .padding(.horizontal, Spacing.rowHorizontal)
        .accessibilityIdentifier(AccessibilityID.Edit.customFieldRow(rowId))
    }

    // MARK: - Name / type / controls

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Field Name", text: $field.name)
                .font(Typography.fieldLabel)
                .textFieldStyle(.plain)
                .frame(maxWidth: 200, alignment: .leading)

            Picker("", selection: typeBinding) {
                ForEach(LinkedFieldId.availableFieldTypes(for: itemType), id: \.rawValue) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Spacer()

            // Reorder and delete. Icon-only with labels so the row does not become a wall of text.
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up").imageScale(.small)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)
            .help(L("Move up"))
            .accessibilityLabel(L("Move up"))
            .accessibilityIdentifier(AccessibilityID.Edit.customFieldMoveUp(rowId))

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
            .help(L("Move down"))
            .accessibilityLabel(L("Move down"))
            .accessibilityIdentifier(AccessibilityID.Edit.customFieldMoveDown(rowId))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(L("Delete Field"))
            .accessibilityLabel(L("Delete Field"))
            .accessibilityIdentifier(AccessibilityID.Edit.customFieldDelete(rowId))
        }
    }

    /// Writes through a handler rather than binding `field.type` directly, so the type change and
    /// its consequences (clearing a stale value, seeding or clearing `linkedId`) happen together.
    private var typeBinding: Binding<CustomFieldType> {
        Binding(
            get: { field.type },
            set: { applyType($0) }
        )
    }

    private func applyType(_ newType: CustomFieldType) {
        guard newType != field.type else { return }
        field.type = newType

        switch newType {
        case .linked:
            // A linked field's value is derived from the field it points at. A value left over from
            // the previous type would be sent to the server while the UI shows something else.
            field.value = nil
            if field.linkedId == nil {
                field.linkedId = LinkedFieldId.options(for: itemType).first
            }
        default:
            field.linkedId = nil
        }
    }

    // MARK: - Value

    @ViewBuilder
    private var valueEditor: some View {
        switch field.type {
        case .hidden:
            hiddenValueEditor

        case .boolean:
            // Boolean fields use a Toggle; the value is the string "true" or "false".
            Toggle(
                isOn: Binding(
                    get: { field.value == "true" },
                    set: { field.value = $0 ? "true" : "false" }
                )
            ) {
                EmptyView()
            }
            .labelsHidden()

        case .linked:
            linkedEditor

        case .text:
            TextField(
                L("Value"),
                text: Binding(
                    get: { field.value ?? "" },
                    set: { field.value = $0.isEmpty ? nil : $0 }
                )
            )
            .font(Typography.fieldValue)
            .textFieldStyle(.plain)
        }
    }

    private var hiddenValueEditor: some View {
        HStack(spacing: 8) {
            if isRevealed {
                TextField(
                    L("Value"),
                    text: Binding(
                        get: { field.value ?? "" },
                        set: { field.value = $0.isEmpty ? nil : $0 }
                    )
                )
                .font(Typography.fieldValue.monospaced())
                .textFieldStyle(.plain)
            } else {
                Text(MaskedFieldState.maskedPlaceholder)
                    .font(Typography.fieldValue.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(isRevealed ? L("Hide") : L("Reveal"))
            .accessibilityLabel(isRevealed ? L("Hide %@", field.name) : L("Reveal %@", field.name))
        }
    }

    /// A linked field's value is derived from the field it points at, so it is chosen rather than
    /// typed, and never edited here.
    private var linkedEditor: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { field.linkedId },
                set: { field.linkedId = $0 }
            )) {
                Text(L("Select a field")).tag(LinkedFieldId?.none)
                ForEach(LinkedFieldId.options(for: itemType), id: \.rawValue) { option in
                    Text(option.displayName).tag(LinkedFieldId?.some(option))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Spacer()
        }
    }
}
