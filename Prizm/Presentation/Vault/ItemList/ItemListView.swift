import SwiftUI

// MARK: - ItemListView

/// Middle-column list of vault items for the currently selected sidebar category (FR-040).
///
/// Items arrive already ordered by `VaultBrowserViewModel` — this view renders them as-is. An empty
/// state message is shown when the list is empty (FR-042). Each row has a context menu with
/// Favorite / Duplicate / Delete actions.
///
/// **One flat list, under every sort order.** The list used to group items under A/B/C… headings when
/// a name order was selected. The headings were removed because they cost the vertical space the rows
/// need — four of the seven visible slots in a 720pt window went to them — and because a heading set
/// at a weight legible enough to read competes with the names it introduces. Position within an
/// ordered list already conveys the letter, which is the same argument that had already removed them
/// from date orders.
struct ItemListView: View {

    let items:         [VaultItem]
    @Binding var selection: VaultItem?
    let faviconLoader: FaviconLoader
    var searchQuery:   String? = nil
    /// Organizations list for resolving org names shown on item rows (6.1).
    var organizations: [Organization] = []
    /// Called when the user confirms moving an item to Trash from the row context menu.
    /// Nil disables the delete context-menu action (e.g. when trash actions are unavailable).
    var onDelete: ((String) async -> Void)? = nil
    var onToggleFavorite: ((VaultItem) -> Void)? = nil
    /// Called to create a copy of the item. Nil disables the Duplicate context-menu action.
    var onDuplicate: ((VaultItem) -> Void)? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    // Tracks which item is pending a soft-delete confirmation alert.
    @State private var itemToDelete:    VaultItem? = nil
    @State private var showDeleteAlert: Bool       = false

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "tray",
                    description: Text("No items in this category.")
                )
                .accessibilityIdentifier(AccessibilityID.ItemList.emptyState)
            } else {
                List(selection: $selection) {
                    // Enumerated rather than plain `items` for one reason: the last row must not draw the
                    // hairline under itself, where there is nothing left to separate.
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, isLast: index == items.count - 1)
                    }
                }
                // The identifier the attachment UI journey looks the table up by. It was declared
                // in `AccessibilityID.ItemList` and never applied, so those tests were querying a
                // table that did not exist.
                .accessibilityIdentifier(AccessibilityID.ItemList.list)
            }
        }
        // Soft-delete confirmation alert — shown when the user selects "Delete"
        // from a row context menu. The item is only moved to Trash, not permanently
        // deleted; it can be recovered from the Trash view.
        .alert(
            "Move to Trash?",
            isPresented: $showDeleteAlert,
            presenting:  itemToDelete
        ) { item in
            Button("Move to Trash", role: .destructive) {
                Task { await onDelete?(item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("\"\(item.name)\" will be moved to Trash.")
        }
    }

    // MARK: - Row

    /// A row, its selection marks, and the hairline below it.
    ///
    /// **Why the selection is drawn here.** `List(selection:)` still owns the selection — keyboard
    /// arrows, ⌘-click and VoiceOver row traits all keep working, because the binding is untouched — but
    /// the *marking* is the app's: a faint accent fill plus a 3pt full-opacity bar. AppKit cannot give the
    /// bar, and its own highlight is a band that runs the full width of the pane.
    ///
    /// **Why the separator is drawn here too.** The `ui-redesign` requirement is that the hairline
    /// between rows respond to Increase Contrast, which a native `List` separator does not.
    @ViewBuilder
    private func row(_ item: VaultItem, isLast: Bool) -> some View {
        let isSelected = selection == item
        ItemRowView(item: item, faviconLoader: faviconLoader, searchQuery: searchQuery,
                    orgName: orgName(for: item))
            .overlay(alignment: .leading) {
                if isSelected { selectionBar }
            }
            .overlay(alignment: .bottom) {
                if !isLast { rowDivider }
            }
            .tag(item)
            .draggable(item.id)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: Spacing.listRowEdgeInset,
                bottom: 0,
                trailing: Spacing.listRowEdgeInset
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: Spacing.selectionCornerRadius)
                    .fill(isSelected
                          ? Color.accentColor.opacity(Opacity.selectionFill(contrast))
                          : Color.clear)
            )
            .accessibilityIdentifier(AccessibilityID.ItemList.row(item.id))
            .contextMenu {
                if let onToggleFavorite {
                    Button(item.isFavorite ? L("Unfavorite") : L("Favorite")) {
                        onToggleFavorite(item)
                    }
                }
                if let onDuplicate {
                    Button("Duplicate") { onDuplicate(item) }
                        .accessibilityIdentifier(AccessibilityID.ItemList.duplicateAction)
                }
                if onDelete != nil {
                    Button("Delete", role: .destructive) {
                        itemToDelete    = item
                        showDeleteAlert = true
                    }
                }
            }
    }

    /// The full-opacity accent bar marking the selected row.
    private var selectionBar: some View {
        RoundedRectangle(cornerRadius: Spacing.selectionBarRadius)
            .fill(Color.accentColor)
            .frame(width: Spacing.selectionBarWidth, height: Spacing.selectionBarHeight)
    }

    /// The rule between two rows. Inset to the text column so it reads as a break between items rather
    /// than a line through them — the chip is what the eye follows down the list.
    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(Opacity.hairline(contrast)))
            .frame(height: 0.5)
            .padding(.leading, Spacing.listDividerInset - Spacing.listRowEdgeInset)
    }

    /// Returns the org name for a vault item, or nil for personal items.
    private func orgName(for item: VaultItem) -> String? {
        guard let orgId = item.organizationId else { return nil }
        return organizations.first(where: { $0.id == orgId })?.name
    }
}
