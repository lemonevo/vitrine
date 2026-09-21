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

    /// Builds the item's one-time-code view model. Nil means the row is not offered.
    ///
    /// Takes the stored key as well as the item id, because the caller already holds the decrypted
    /// login — looking it up again by id would decrypt the item a second time to learn something
    /// that is already in hand.
    var makeTOTPCodeViewModel: ((String, String?) -> TOTPCodeViewModel)? = nil

    /// The master-password gate for this item's password, its hidden custom fields and its previous
    /// passwords.
    ///
    /// The username, the URIs and the notes are deliberately not given it: gating the username
    /// would remove the reason the copy-username command exists (design D7).
    var gate: RevealGateBinding = .none

    /// Held so the section keeps its state across renders, and re-created when the item changes.
    @State private var passwordHistoryVM: PasswordHistoryViewModel?
    @State private var passkeysVM: PasskeysViewModel?
    @State private var totpVM: TOTPCodeViewModel?

    // A Credentials card is only meaningful when at least one credential field is present.
    private var hasCredentials: Bool {
        login.username != nil || login.password != nil || canShowTOTPCode
    }

    /// Whether the code row can be offered: a stored key *and* a way to build its view model.
    ///
    /// The factory is part of the condition rather than assumed, so an item that carries only a key
    /// does not render an empty Credentials card when no factory was injected (previews, and the
    /// tests that render this view directly).
    private var canShowTOTPCode: Bool {
        login.totp != nil && makeTOTPCodeViewModel != nil
    }

    /// What the code row is derived from — and therefore what has to change for it to be rebuilt.
    ///
    /// **The key is part of it, not only the item id.** An edit can replace the stored key for the
    /// same item, and a task keyed on the id alone would not re-run: the row would go on deriving
    /// codes from the key the user just replaced, and the codes would simply be wrong.
    private struct TOTPIdentity: Equatable {
        let itemId: String
        let secret: String?
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
                        // After the password, because the code is the thing the user reaches for
                        // second: it is what the password is a step towards.
                        if let totpVM {
                            if login.username != nil || login.password != nil {
                                Divider()
                            }
                            TOTPCodeView(
                                viewModel: totpVM,
                                gate:      gate,
                                onCopy:    onCopy
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
        // A task of its own rather than a third assignment in the one above: this one has to re-run
        // when the stored key changes, which the item id cannot express.
        .task(id: TOTPIdentity(itemId: item.id, secret: login.totp)) {
            // Built only for an item that stores a key. The row derives the code from it; the key
            // itself never leaves the view model.
            totpVM = canShowTOTPCode
                ? makeTOTPCodeViewModel?(item.id, login.totp)
                : nil
        }
    }
}
