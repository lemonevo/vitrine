import SwiftUI

// MARK: - IdentityEditForm

/// Edit form for Identity vault items.
///
/// Groups the 17+ identity fields into the same six card sections as `IdentityDetailView`
/// so the edit layout is consistent with the read-only view: Personal Info, ID Numbers,
/// Contact, Address, Notes, Custom Fields.
struct IdentityEditForm: View {

    @Binding var draft: DraftIdentityContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                DetailSectionCard(L("Personal Info")) {
                    OptionalEditFieldRow(label: L("Title"),       value: $draft.title)
                    Divider()
                    OptionalEditFieldRow(label: L("First Name"),  value: $draft.firstName)
                    Divider()
                    OptionalEditFieldRow(label: L("Middle Name"), value: $draft.middleName)
                    Divider()
                    OptionalEditFieldRow(label: L("Last Name"),   value: $draft.lastName)
                    Divider()
                    OptionalEditFieldRow(label: L("Company"),     value: $draft.company)
                }

                DetailSectionCard(L("ID Numbers")) {
                    OptionalEditFieldRow(label: L("SSN"),             value: $draft.ssn)
                    Divider()
                    OptionalEditFieldRow(label: L("Passport Number"), value: $draft.passportNumber)
                    Divider()
                    OptionalEditFieldRow(label: L("License Number"),  value: $draft.licenseNumber)
                }

                DetailSectionCard(L("Contact")) {
                    OptionalEditFieldRow(label: L("Email"),    value: $draft.email)
                    Divider()
                    OptionalEditFieldRow(label: L("Phone"),    value: $draft.phone)
                    Divider()
                    OptionalEditFieldRow(label: L("Username"), value: $draft.username)
                }

                DetailSectionCard(L("Address")) {
                    OptionalEditFieldRow(label: L("Address Line 1"), value: $draft.address1)
                    Divider()
                    OptionalEditFieldRow(label: L("Address Line 2"), value: $draft.address2)
                    Divider()
                    OptionalEditFieldRow(label: L("Address Line 3"), value: $draft.address3)
                    Divider()
                    OptionalEditFieldRow(label: L("City"),         value: $draft.city)
                    Divider()
                    OptionalEditFieldRow(label: L("State"),        value: $draft.state)
                    Divider()
                    OptionalEditFieldRow(label: L("Postal Code"),  value: $draft.postalCode)
                    Divider()
                    OptionalEditFieldRow(label: L("Country"),      value: $draft.country)
                }

                DetailSectionCard(L("Notes")) {
                    OptionalEditFieldRow(label: L("Notes"), value: $draft.notes)
                }

                CustomFieldsEditSection(fields: $draft.customFields, itemType: .identity)
            }
        }
    }
}
