import SwiftUI

// MARK: - CardEditForm

/// Edit form for Card vault items.
///
/// Brand, expiry month and expiry year are pickers over `CardFieldOptions`. Each one keeps a value it
/// does not offer — a regional brand, a year outside the range, a value written by another client —
/// behind a "Custom" row rather than coercing it, because a picker that rewrites an unfamiliar value
/// on open would be a data loss the user never asked for.
struct CardEditForm: View {

    @Binding var draft: DraftCardContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                DetailSectionCard(L("Card Details")) {
                    OptionalEditFieldRow(label: L("Cardholder Name"), value: $draft.cardholderName)
                    Divider()
                    PickerRow(
                        label: L("Brand"),
                        selection: $draft.brand,
                        options: CardFieldOptions.brands,
                        isRecognised: CardFieldOptions.isRecognised(brand:),
                        customLabel: L("Custom…"),
                        identifier: AccessibilityID.Vault.itemEditCardBrand
                    )
                    Divider()
                    OptionalEditFieldRow(label: L("Number"), value: $draft.number)
                    Divider()
                    PickerRow(
                        label: L("Expiry Month"),
                        selection: $draft.expMonth,
                        options: CardFieldOptions.months,
                        isRecognised: CardFieldOptions.isRecognised(month:),
                        customLabel: L("Custom…"),
                        identifier: AccessibilityID.Vault.itemEditCardExpMonth
                    )
                    Divider()
                    PickerRow(
                        label: L("Expiry Year"),
                        selection: $draft.expYear,
                        options: CardFieldOptions.years,
                        isRecognised: CardFieldOptions.isRecognised(year:),
                        customLabel: L("Custom…"),
                        identifier: AccessibilityID.Vault.itemEditCardExpYear
                    )
                    Divider()
                    OptionalEditFieldRow(label: L("Security Code"), value: $draft.code)
                }

                DetailSectionCard(L("Notes")) {
                    OptionalEditFieldRow(label: L("Notes"), value: $draft.notes)
                }

                CustomFieldsEditSection(fields: $draft.customFields, itemType: .card)
            }
        }
    }
}

// MARK: - PickerRow

/// A labelled picker that can hold a value it does not offer.
///
/// The selection is always a `String?` matching the wire format, so the picker never has to convert.
/// When the stored value is not in `options`, a "Custom" row appears holding it; choosing any other
/// row replaces it, and choosing "Custom" leaves it editable.
private struct PickerRow: View {

    let label:      String
    @Binding var selection: String?
    let options:    [String]
    let isRecognised: (String?) -> Bool
    let customLabel: String
    let identifier: String

    /// Whether the user is editing a value outside the list. Local to the form: it is a view state,
    /// not item data — and leaving it false is what keeps an unrecognised value untouched.
    @State private var isEditingCustom = false

    private var showsCustomField: Bool { isEditingCustom || !isRecognised(selection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(Typography.fieldLabel)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)

                Picker("", selection: pickerSelection) {
                    Text(L("None")).tag(String?.none)
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(String?.some(option))
                    }
                    Text(customLabel).tag(String?.some(Self.customSentinel))
                }
                .labelsHidden()
                .accessibilityIdentifier(identifier)
                Spacer()
            }

            if showsCustomField {
                TextField("", text: Binding(
                    get: { selection ?? "" },
                    set: { selection = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(Typography.fieldValue.monospaced())
                .padding(.leading, 130)
                .accessibilityIdentifier(identifier + ".custom")
            }
        }
        .padding(.vertical, Spacing.rowVertical)
        .padding(.horizontal, Spacing.rowHorizontal)
    }

    /// A tag distinct from every real value, so "Custom…" is selectable without colliding with an
    /// option that happens to be spelled the same.
    private static let customSentinel = "\u{0}custom"

    private var pickerSelection: Binding<String?> {
        Binding(
            get: {
                if showsCustomField { return Self.customSentinel }
                return selection
            },
            set: { newValue in
                if newValue == Self.customSentinel {
                    isEditingCustom = true
                    // Left as it was: switching to Custom is a decision to keep the current text,
                    // not to clear it.
                    return
                }
                isEditingCustom = false
                selection = newValue
            }
        )
    }
}
