import SwiftUI

// MARK: - VerificationCodesPane

/// Every verification code in the vault, in one list, as a destination in the window.
///
/// **It was a sheet, and the reason was security.** "Codes on screen are codes an onlooker can read",
/// and a sheet is present while the user is using it and gone afterwards, where a persistent screen
/// leaves the vault's second factors visible for the rest of the session —
/// `openspec/changes/verification-codes/design.md`, Decision 5, which this replaces. The reviewer
/// wanted it to behave like every other list in the window, and the cost is stated rather than hidden:
/// **while this destination is selected, every second factor is on screen.** Leaving the destination,
/// or locking the vault, takes them off it. Nothing here is cached: the rows are built when the
/// destination is entered and released when it is left.
///
/// Unlike the sheet, this has no header and no dismiss button — the sidebar row is the selection, and
/// leaving it is the dismissal — and the rows are laid out for a 262pt column rather than a 420pt
/// sheet, so the code sits under the name instead of beside it.
struct VerificationCodesPane: View {

    /// Selects the item a row belongs to, so the detail column behaves as it does for every other list.
    let onSelect: (String) -> Void

    /// The toolbar's search field, while this destination is the one the list column is showing.
    ///
    /// Passed in rather than owned: the rows are built by the view model below, but the control that
    /// filters them lives in the window's toolbar, outside this pane. Filtering and ordering are
    /// presentation, so they are applied here over `viewModel.rows` and the view model stays unaware.
    var query: String = ""

    /// The toolbar's sort menu. Only the two name orders are offered while this destination is
    /// selected — a code row has a name and nothing else that can be ordered.
    var sortOrder: ItemSortOrder = .nameAscending

    /// **Owned, not merely held.** `@StateObject` subscribes to the view model, so rows arriving after
    /// the first render redraw the pane. `@State` does not subscribe to anything, and with it the pane
    /// drew once — empty, because the vault read has not returned yet — and never drew again. The sheet
    /// this replaces split its content into a separate observing type for exactly this reason; owning
    /// the object here is the same fix with one fewer type.
    @StateObject private var viewModel: VerificationCodesViewModel

    /// The row the user last clicked. Held here because the point of it is that the click *copied* —
    /// the highlight is the only feedback that the copy happened, and it has to survive the click's own
    /// redraw.
    @State private var copiedId: String?

    init(makeViewModel: @escaping () -> VerificationCodesViewModel,
         onSelect: @escaping (String) -> Void,
         query: String = "",
         sortOrder: ItemSortOrder = .nameAscending) {
        // Built here rather than in a `.task`: the object exists for the first render, so there is no
        // frame that draws nothing and no state to assign later.
        _viewModel = StateObject(wrappedValue: makeViewModel())
        self.onSelect = onSelect
        self.query = query
        self.sortOrder = sortOrder
    }

    var body: some View {
        content
            .accessibilityIdentifier(AccessibilityID.VerificationCodes.pane)
    }

    @ViewBuilder
    private var content: some View {
        let rows = displayedRows(viewModel.rows)

        // **A `ZStack`, not a `Group`.** `Group` creates no container, so a modifier attached to it is
        // applied to each child — and `.onDisappear` on a child fires when that child is swapped out.
        // With the three-way switch below, every transition between "empty" and "rows" tore the rows
        // down: `stop()` emptied them and the pane fell back to its empty state. A real container gives
        // the modifiers one stable identity for as long as the destination is up.
        ZStack {
            if viewModel.rows.isEmpty {
                emptyState
            } else if rows.isEmpty {
                // Distinct from `emptyState`: the vault *has* codes and the query excludes them all.
                // One message for both would tell the user their vault is empty when it is not.
                noMatchesState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            VerificationCodeRowView(
                                row: row,
                                isMarked: copiedId == row.id,
                                onCopy: { viewModel.copy(row) },
                                // Clicking a row copies, which is what a list of codes is for: the
                                // moment the user is here is the moment something else is asking them
                                // for a code. It also marks the row and opens the item in the detail
                                // column, so the click is visible in two places.
                                onSelect: {
                                    copiedId = row.id
                                    onSelect(row.id)
                                    viewModel.copy(row)
                                }
                            )
                            Divider()
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            }
        }
        // Loading the rows is what makes them non-empty, so this cannot live in the non-empty branch —
        // the pane would sit on its own empty state with the state that replaces it never asked for.
        .task { await viewModel.start() }
        // The rows own one timer each, so they are released when the destination is left. A destination
        // the user has left must not leave a vault's worth of timers deriving codes behind another
        // screen.
        .onDisappear { viewModel.stop() }
    }

    /// The rows the query and the sort leave behind.
    ///
    /// `localizedStandardCompare` rather than `<`: names in a vault are full of digits and mixed case,
    /// and the plain comparison puts "item10" before "item9".
    private func displayedRows(_ rows: [VerificationCodeRow]) -> [VerificationCodeRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty ? rows : rows.filter { row in
            row.name.localizedCaseInsensitiveContains(needle)
                || (row.username ?? "").localizedCaseInsensitiveContains(needle)
        }
        let ascending = sortOrder != .nameDescending
        return matched.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private var noMatchesState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("No matching codes"))
                .font(Typography.fieldValue)
            Text(L("No item with a one-time-code key matches “%@”.", query))
                .font(Typography.listSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.sidebarHorizontal)
        .accessibilityIdentifier(AccessibilityID.VerificationCodes.noMatchesState)
    }

    /// An empty vault of codes says so, and says where codes come from. An empty list would look like
    /// a loading failure.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("No verification codes"))
                .font(Typography.fieldValue)
            Text(L("Codes appear here for any login that has a one-time-code key stored on it."))
                .font(Typography.listSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.sidebarHorizontal)
        .accessibilityIdentifier(AccessibilityID.VerificationCodes.emptyState)
    }

    /// The line that says the key is not what is being shown. It stays on the pane rather than moving to
    /// a tooltip: it is the answer to "is this safe to leave open", and that question is asked while
    /// looking at the screen.
    private var footer: some View {
        Text(L("Codes are derived from each item's stored key. The key itself is never shown or copied."))
            .font(Typography.listSubtitle)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sidebarHorizontal)
            .padding(.vertical, 8)
            .background(.bar)
    }
}

// MARK: - VerificationCodeRowView

/// One row: what the item is, its code, and how long the code has left.
private struct VerificationCodeRowView: View {

    let row: VerificationCodeRow
    /// Whether this is the row the user last clicked. Drawn with the item list's own selection fill,
    /// not a second treatment for the same idea.
    let isMarked: Bool
    let onCopy: () -> Void
    let onSelect: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    /// Whether the code is on screen.
    ///
    /// **This deliberately differs from the detail pane.** There, a code is masked until the user
    /// reveals it, because they are looking at one item and a shoulder-surfer is one click from it.
    /// Here the opposite is true: the screen exists to show codes, and masking all of them would make
    /// it a list of names with extra steps.
    ///
    /// What is *not* relaxed is the re-prompt gate. An item the user marked as requiring the master
    /// password stays masked until it has been given — that is the user's explicit instruction about
    /// that item, and a convenience screen does not get to overrule it.
    private var isVisible: Bool { !row.gate.isGated || row.gate.isRevealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.name)
                .font(Typography.fieldValue)
                .lineLimit(1)

            if let username = row.username, !username.isEmpty {
                Text(username)
                    .font(Typography.listSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if isVisible {
                VerificationCodeCell(code: row.code, name: row.name, id: row.id, onCopy: onCopy)
            } else {
                Button {
                    // Only ever reached for a gated row — see `isVisible`. So this asks the gate, which
                    // raises the master-password prompt.
                    row.gate.request()
                } label: {
                    Label(L("Reveal"), systemImage: "eye")
                        .labelStyle(.titleAndIcon)
                        .font(Typography.listSubtitle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier(AccessibilityID.VerificationCodes.revealButton(row.id))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, Spacing.sidebarHorizontal)
        // The same fill the item list marks its selected row with, so a marked code row and a selected
        // item read as the same thing.
        .background(
            RoundedRectangle(cornerRadius: Spacing.selectionCornerRadius)
                .fill(isMarked
                      ? Color.accentColor.opacity(Opacity.selectionFill(contrast))
                      : Color.clear)
                .padding(.horizontal, Spacing.listRowEdgeInset)
        )
        .contentShape(Rectangle())
        // Selection rather than a tap gesture on the row body: the copy button inside the cell has to
        // keep its own click, and a gesture on the container would swallow it.
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.VerificationCodes.row(row.id))
    }
}

// MARK: - VerificationCodeCell

/// The code, its countdown, and the copy control.
///
/// **Its own type because it has to observe the code's view model.** `VerificationCodeRowView` holds a
/// `VerificationCodeRow`, which is a value struct carrying a `let` to `TOTPCodeViewModel` — and a plain
/// `let` to an `ObservableObject` installs no subscription. The list therefore drew every row once and
/// never redrew it: the seconds sat still, and worse, `displayCode` never changed either, so a code
/// that expired thirty seconds later stayed on screen as the current code.
private struct VerificationCodeCell: View {

    @ObservedObject var code: TOTPCodeViewModel
    let name: String
    let id: String
    let onCopy: () -> Void

    var body: some View {
        Group {
            if let value = code.displayCode {
                cell(value)
            } else if code.isUnusable {
                Text(L("No code"))
                    .font(Typography.listSubtitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// The countdown is here as well as in the detail pane because a list is scanned across rows. It is
    /// the detail pane's own shape — ring plus a number — rather than a second one: two screens
    /// counting the same thing down in two different ways is a thing the user has to learn twice.
    private func cell(_ digits: String) -> some View {
        HStack(spacing: 8) {
            Text(digits)
                .font(Typography.fieldValue.monospaced())
                .textSelection(.enabled)

            if let seconds = code.secondsRemaining {
                CountdownRing(fraction: code.remainingFraction)
                Text(L("%ds", seconds))
                    .font(Typography.utility.monospacedDigit())
                    .foregroundStyle(.secondary)
                    // Fixed width, so a code going from ten seconds left to nine does not slide the
                    // copy button sideways underneath the pointer.
                    .frame(width: Spacing.codesCountdownWidth, alignment: .trailing)
            }

            Spacer(minLength: 0)

            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help(L("Copy code"))
            .accessibilityLabel(L("Copy code"))
            .accessibilityIdentifier(AccessibilityID.VerificationCodes.copyButton(id))
        }
        // Announced as a sentence: a screen reader reaching a bare six-digit number has no way to know
        // what it belongs to. The visible seconds are part of that sentence, not a second element to
        // read.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@ code for %@, %d seconds left", digits, name, code.secondsRemaining ?? 0))
    }
}
