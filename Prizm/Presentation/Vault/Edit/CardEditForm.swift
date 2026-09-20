import SwiftUI

// MARK: - CardEditForm

/// Edit form for Card vault items.
///
/// Mirrors the layout of `CardDetailView`. All card fields are editable text fields.
struct CardEditForm: View {

    @Binding var draft: DraftCardContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                DetailSectionCard(L("Card Details")) {
                    OptionalEditFieldRow(label: L("Cardholder Name"), value: $draft.cardholderName)
                    Divider()
                    OptionalEditFieldRow(label: L("Brand"), value: $draft.brand)
                    Divider()
                    OptionalEditFieldRow(label: L("Number"), value: $draft.number)
                    Divider()
                    OptionalEditFieldRow(label: L("Expiry Month"), value: $draft.expMonth)
                    Divider()
                    OptionalEditFieldRow(label: L("Expiry Year"), value: $draft.expYear)
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
