import SwiftUI

// MARK: - PasskeysPane

/// Every item in the vault that carries a passkey, in one list, as a destination in the window.
///
/// **Why this pane is handed its rows instead of fetching them.** The verification-codes destination
/// builds its own rows, because a one-time code is derived state that no item list carries. A
/// passkey's *existence* is not like that: the credential list arrives on the item still encrypted but
/// present, so `.passkeys` is an ordinary indexed selection — `items(for:)`, `itemCounts()`, the
/// toolbar's search field and its sort menu all work on it exactly as they work on a folder. That
/// leaves this pane one job, and it is the job the index cannot do: naming the relying parties, which
/// does need decrypting.
///
/// **So the decryption is per row and per appearance**, which is also what `passkey-viewer`'s
/// "decrypted on demand and never cached" requires of a second surface. Each row owns a
/// `PasskeysViewModel` — the detail section's own type, reused unchanged — loading when the row is
/// drawn and cleared when it goes away. `LazyVStack` means a row below the fold has not been drawn and
/// so has not been decrypted; leaving the destination tears the rows down with it. Nothing here holds
/// a collection of decrypted credentials, because a pane that did would be that requirement unmet in
/// a new place, having satisfied it in the old one.
///
/// **There is nothing to copy, and that is the point.** `PasskeyCredential` has no field for the
/// credential's private key, so no row here can surface one — the same shape that makes it true of the
/// detail section rather than a promise repeated. The footer says what cannot be done with these,
/// because a list of credentials offering no action reads as a feature that failed to load.
struct PasskeysPane: View {

    /// The items to list, already filtered and ordered by the vault search and the toolbar's sort —
    /// see the type comment for why the pane does neither itself.
    let items: [VaultItem]

    /// The toolbar's search field, needed only to tell "this vault has no passkeys" apart from "the
    /// query excludes the ones it has". Those are different sentences and one message for both is a
    /// lie about the user's own vault.
    var searchQuery: String = ""

    /// Opens the item in the detail column, where the full section — dates, and the name a site gave
    /// itself — can be expanded.
    let onSelect: (String) -> Void

    /// Builds a row's loader. The same factory the detail column is given, so the two surfaces reach
    /// the credentials through one path and cannot disagree about what a failed read looks like.
    let makeViewModel: (String) -> PasskeysViewModel

    var body: some View {
        content
            .accessibilityIdentifier(AccessibilityID.Passkeys.destinationPane)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                noMatchesState
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        PasskeyItemRowView(item: item,
                                           makeViewModel: { makeViewModel(item.id) },
                                           onSelect: onSelect)
                        Divider()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
    }

    /// An empty list would look like a load failure, so it says where passkeys come from instead.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.fieldLabelGap) {
            Text(L("No passkeys"))
                .font(Typography.fieldValue)
            Text(L("Passkeys appear here for any login that has one stored on it."))
                .font(Typography.listSubtitle)
                .foregroundStyle(Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Spacing.sidebarHorizontal)
        .accessibilityIdentifier(AccessibilityID.Passkeys.destinationEmptyState)
    }

    private var noMatchesState: some View {
        VStack(alignment: .leading, spacing: Spacing.fieldLabelGap) {
            Text(L("No matching passkeys"))
                .font(Typography.fieldValue)
            Text(L("No item with a passkey matches “%@”.", searchQuery))
                .font(Typography.listSubtitle)
                .foregroundStyle(Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Spacing.sidebarHorizontal)
        .accessibilityIdentifier(AccessibilityID.Passkeys.destinationNoMatches)
    }

    /// The same sentence the detail section carries, under the same identifier namespace: what these
    /// are, and that Vitrine cannot use them.
    private var footer: some View {
        Text(L("Vitrine cannot use these passkeys to sign in. Register, use and remove them from another Bitwarden client."))
            .font(Typography.listSubtitle)
            .foregroundStyle(Foreground.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sidebarHorizontal)
            .padding(.vertical, Spacing.bannerVertical)
            .background(.bar)
            .accessibilityIdentifier(AccessibilityID.Passkeys.destinationLimitationNote)
    }
}

// MARK: - PasskeyItemRowView

/// One item: what it is, how many credentials it carries, and who they are registered with.
private struct PasskeyItemRowView: View {

    /// **Owned here, and observed.** A plain `let` to an `ObservableObject` installs no subscription,
    /// and the row would then draw once — while the read is still outstanding — and never show what it
    /// found. `@StateObject` gives the row one loader that survives the pane's redraws and dies with
    /// the row.
    @StateObject private var viewModel: PasskeysViewModel

    let item: VaultItem

    /// Opens this item in the detail column.
    let onSelect: (String) -> Void

    init(item: VaultItem,
         makeViewModel: @escaping () -> PasskeysViewModel,
         onSelect: @escaping (String) -> Void) {
        // Built here rather than in a `.task`, so there is no frame that has no loader to draw.
        _viewModel = StateObject(wrappedValue: makeViewModel())
        self.item     = item
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.fieldLabelGap) {
            Text(item.name)
                .font(Typography.listTitle)
                .lineLimit(1)

            if let username = loginUsername, !username.isEmpty {
                Text(username)
                    .font(Typography.listSubtitle)
                    .foregroundStyle(Foreground.muted)
                    .lineLimit(1)
            }

            // The number the item carries, not the number that happened to decrypt: an item with one
            // damaged credential still has three, and saying otherwise is the listing understating what
            // is in the user's own vault. Singular at one, the way `SyncLabelFormatter` words its counts.
            Text(item.passkeyCount == 1 ? L("1 passkey") : L("%d passkeys", item.passkeyCount))
                .font(Typography.metaLine)
                .foregroundStyle(Foreground.muted)

            credentials
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.rowVertical)
        .padding(.horizontal, Spacing.sidebarHorizontal)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item.id) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Passkeys.destinationRow(item.id))
        .task { await viewModel.load() }
        // The row is gone: the decrypted names it held go with it. `clear()` is what the detail section
        // calls when it collapses, and a row scrolled out of a lazy stack is the same event elsewhere.
        .onDisappear { viewModel.clear() }
    }

    /// The relying parties this item's credentials are registered with, or the reason they are not on
    /// screen.
    ///
    /// Loading and failure are both drawn rather than left blank. A row that shows nothing under its
    /// count is read as "this item has no readable passkey", which is a different claim from "the read
    /// has not come back" and from "the read failed" — and the last two are the ones the user can act
    /// on.
    @ViewBuilder
    private var credentials: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityIdentifier(AccessibilityID.Passkeys.destinationProgress)

        case .failed(let message):
            Text(message)
                .font(Typography.metaLine)
                .foregroundStyle(Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.Passkeys.destinationErrorMessage)

        case .loaded(let credentials):
            // Each on its own line: a joined string cannot carry the per-credential identifier a
            // screen reader needs to reach one of them.
            ForEach(Array(credentials.enumerated()), id: \.element.id) { _, credential in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.fieldLabelGap) {
                    Image(systemName: "key.horizontal.fill")
                        .font(Typography.controlGlyph)
                        .foregroundStyle(Foreground.muted)
                        .accessibilityHidden(true)
                    Text(credential.rpId)
                        .font(Typography.metaLine)
                        .lineLimit(1)
                        .accessibilityIdentifier(
                            AccessibilityID.Passkeys.destinationCredential(credential.id)
                        )
                }
            }
        }
    }

    /// The username, when this item is a login with one.
    ///
    /// Read off the content here rather than passed in: only a login has a username, so a row that took
    /// one as an argument could be built to claim a username for an item that cannot carry one.
    /// It is the line that tells two items named "GitHub" apart, which is why it is drawn at all.
    private var loginUsername: String? {
        if case .login(let login) = item.content { return login.username }
        return nil
    }
}
