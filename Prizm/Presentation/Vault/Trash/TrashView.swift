import SwiftUI

// MARK: - TrashView

/// Middle-column list of trashed vault items (items where `isDeleted == true`).
///
/// Provides:
/// - Empty state when no items are in trash.
/// - An "Empty Trash" action that permanently deletes everything, behind a confirmation naming the
///   count.
/// - Per-row context menus with "Restore" and "Delete Permanently" actions.
/// - Confirmation alerts before any permanent deletion.
struct TrashView: View {

    let items:         [VaultItem]
    @Binding var selection: VaultItem?
    let faviconLoader: FaviconLoader
    let onRestore:          (String) async -> Void
    /// Called to permanently delete a single trashed item (irreversible).
    let onPermanentDelete:  (String) async -> Void
    /// Called to permanently delete every trashed item. Nil hides the empty-Trash action.
    var onEmptyTrash: (() async -> Void)? = nil

    // Confirmation alert state for single-item permanent delete.
    @State private var itemToDelete:    VaultItem? = nil
    @State private var showDeleteAlert: Bool       = false

    // Confirmation alert state for emptying Trash.
    @State private var showEmptyTrashAlert: Bool = false

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if onEmptyTrash != nil {
                        emptyTrashBar
                        Divider()
                    }
                    List(items, id: \.id, selection: $selection) { item in
                        ItemRowView(item: item, faviconLoader: faviconLoader)
                            .tag(item)
                            .accessibilityIdentifier(AccessibilityID.ItemList.row(item.id))
                            .contextMenu {
                                Button("Restore") {
                                    Task { await onRestore(item.id) }
                                }
                                Divider()
                                Button("Delete Permanently", role: .destructive) {
                                    itemToDelete    = item
                                    showDeleteAlert = true
                                }
                                .accessibilityIdentifier(AccessibilityID.Trash.permanentDeleteButton)
                            }
                    }
                }
            }
        }
        // Confirmation alert: single permanent delete.
        .alert(
            "Delete Permanently?",
            isPresented: $showDeleteAlert,
            presenting:  itemToDelete
        ) { item in
            Button("Delete Permanently", role: .destructive) {
                Task { await onPermanentDelete(item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("\"\(item.name)\" will be permanently deleted and cannot be recovered.")
        }
        // Confirmation alert: empty the whole Trash. Names the count, because permanent deletion
        // cannot be undone and "Empty Trash" alone does not say how much that is.
        .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
            Button("Empty Trash", role: .destructive) {
                Task { await onEmptyTrash?() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L("%d items will be permanently deleted and cannot be recovered.", items.count))
        }
    }

    // MARK: - Empty Trash bar

    private var emptyTrashBar: some View {
        HStack {
            Spacer()

            Button("Empty Trash") {
                showEmptyTrashAlert = true
            }
            .foregroundStyle(.red)
            .help(L("Permanently delete every item in Trash"))
            .accessibilityIdentifier(AccessibilityID.Trash.emptyTrashButton)
        }
        .padding(.horizontal, Spacing.bannerHorizontal)
        .padding(.vertical, Spacing.bannerVertical)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Items in Trash",
            systemImage: "trash",
            description: Text("Items you delete will appear here.")
        )
        .accessibilityIdentifier(AccessibilityID.Trash.emptyState)
    }
}
