import SwiftUI

// MARK: - LoginDetailView

/// Detail view for Login items (FR-025, FR-029).
///
/// Fields are grouped into labelled card sections to reduce cognitive load
/// when scanning items with multiple URIs, notes, and custom fields.
/// Sections are hidden entirely when their content is nil/empty.
struct LoginDetailView: View {

    let item:  VaultItem
    let login: LoginContent
    let onCopy: (String) -> Void
    /// Builds the item's password-history view model. Nil means the section is not offered.
    ///
    /// A factory rather than a view model because the detail view is reconstructed on every render:
    /// the view model has to be created per item and held in `@State`, and it must be *re*-created
    /// when the selection changes.
    var makePasswordHistoryViewModel: ((String) -> PasswordHistoryViewModel)? = nil

    /// Builds the item's passkeys view model. Nil means the section is not offered.
    ///
    /// The same factory shape as the history one, and for a stronger reason here: `fido2Credentials`
    /// is only non-empty for items that actually carry passkeys, so an item without them never
    /// builds a view model and never decrypts anything.
    var makePasskeysViewModel: ((String) -> PasskeysViewModel)? = nil

    /// The master-password gate for this item's password, its hidden custom fields and its previous
    /// passwords.
    ///
    /// The username, the URIs and the notes are deliberately not given it: gating the username
    /// would remove the reason the copy-username command exists (design D7).
    var gate: RevealGateBinding = .none

    /// Held so the section keeps its state across renders, and re-created when the item changes.
    @State private var passwordHistoryVM: PasswordHistoryViewModel?
    @State private var passkeysVM: PasskeysViewModel?

    // A Credentials card is only meaningful when at least one credential field is present.
    private var hasCredentials: Bool {
        login.username != nil || login.password != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

                if hasCredentials {
                    DetailSectionCard(L("Credentials")) {
                        if let username = login.username {
                            FieldRowView(
                                label:  L("Username"),
                                value:  username,
                                itemId: item.id,
                                onCopy: onCopy
                            )
                        }
                        if login.username != nil && login.password != nil {
                            Divider()
                        }
                        if let password = login.password {
                            FieldRowView(
                                label:    L("Password"),
                                value:    password,
                                itemId:   item.id,
                                isMasked: true,
                                onCopy:   onCopy,
                                gate:     gate
                            )
                        }
                    }
                }

                if !login.uris.isEmpty {
                    DetailSectionCard(L("Websites")) {
                        ForEach(login.uris.indices, id: \.self) { index in
                            let uri = login.uris[index]
                            if index > 0 { Divider() }
                            FieldRowView(
                                label:  L("Website"),
                                value:  uri.uri,
                                itemId: item.id,
                                url:    URL(string: uri.uri),
                                onCopy: onCopy
                            )
                        }
                    }
                }

                if let notes = login.notes, !notes.isEmpty {
                    DetailSectionCard(L("Notes")) {
                        FieldRowView(label: "", value: notes, itemId: item.id, isMultiLine: true, onCopy: onCopy)
                    }
                }

                if !login.customFields.isEmpty {
                    DetailSectionCard(L("Custom Fields")) {
                        CustomFieldsSection(
                            fields: login.customFields,
                            itemId: item.id,
                            onCopy: onCopy,
                            gate:   gate
                        )
                    }
                }

                if let passwordHistoryVM {
                    PasswordHistorySection(
                        viewModel: passwordHistoryVM,
                        onCopy:    onCopy,
                        gate:      gate
                    )
                }

                if let passkeysVM {
                    PasskeysSection(viewModel: passkeysVM)
                }
            }
        .task(id: item.id) {
            // Only for an item that actually has history, and only then does anything get
            // decrypted — the section's own collapse/expand is what triggers the read (design D10).
            passwordHistoryVM = item.preserved.passwordHistory.isEmpty
                ? nil
                : makePasswordHistoryViewModel?(item.id)
            // The same gate as the history: offered only when the encrypted wire form is non-empty,
            // so an item with no passkeys triggers no decryption at all.
            passkeysVM = item.preserved.fido2Credentials.isEmpty
                ? nil
                : makePasskeysViewModel?(item.id)
        }
    }
}
