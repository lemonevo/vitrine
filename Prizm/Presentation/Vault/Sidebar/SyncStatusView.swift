import SwiftUI

// MARK: - SyncStatusView

/// Displays the last successful vault sync timestamp at the very bottom of the sidebar.
///
/// Pinned outside the scrollable list so it remains visible regardless of scroll position.
/// Uses `Typography.listSubtitle` to stay visually unobtrusive.
/// The view is only rendered when the vault browser is active — the parent screen state
/// machine (RootViewModel) hides the entire vault browser when locked, satisfying the
/// "hidden when vault is locked" requirement without additional logic here.
///
/// While a manual sync is in flight the timestamp is replaced by a spinner and "Syncing…", so the
/// progress is visible next to the button that started it as well as in the toolbar.
///
/// Below the timestamp it may also report how many items the last sync could not read. That line is
/// deliberately not the dismissable error banner `syncErrorMessage` drives: a banner reports an
/// *event* (a sync failed), which the user can read and dismiss, whereas this reports a *condition*
/// — the vault on screen is incomplete — which does not go away when the message does.
struct SyncStatusView: View {

    /// Relative label produced by the ViewModel's 60-second timer (e.g. "Synced 2 minutes ago").
    let label: String

    /// Whether a manual sync is in flight.
    var isSyncing: Bool = false

    /// Whether the vault has ever been synced successfully.
    ///
    /// Defaults to `true` so existing call sites and previews keep the "this is a good timestamp"
    /// reading. Drives the status dot's colour and nothing else — the label already carries the
    /// content, and a dot that disagreed with it would be the kind of decoration that misleads.
    var hasSynced: Bool = true

    /// Items the last sync could not read. Zero renders nothing.
    var unreadableCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Syncing…"))
                } else {
                    // A dot rather than a word: the label beside it already says whether the sync
                    // succeeded, so the dot's only job is to make the state visible at a glance from
                    // across the room.
                    Circle()
                        .fill(hasSynced ? Foreground.success : Foreground.muted)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(label)
                }
            }
            .font(Typography.listSubtitle)
            .foregroundStyle(Foreground.muted)
            .accessibilityIdentifier(AccessibilityID.Vault.syncStatusLabel)

            if let warning = UnreadableItemsLabel.make(count: unreadableCount) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(warning)
                        .font(Typography.listSubtitle)
                }
                .foregroundStyle(.orange)
                // The tooltip carries the half a bare count cannot: the items were not deleted.
                .help(UnreadableItemsLabel.explanation(count: unreadableCount))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(UnreadableItemsLabel.explanation(count: unreadableCount))
                .accessibilityIdentifier(AccessibilityID.Vault.unreadableItemsLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sidebarHorizontal)
        .padding(.top, Spacing.rowVertical)
        .padding(.bottom, Spacing.sidebarStatusBottom)
    }
}

#Preview("Synced recently") {
    SyncStatusView(label: "Synced 2 minutes ago")
        .frame(width: 220)
}

#Preview("Never synced") {
    SyncStatusView(label: L("Never synced"))
        .frame(width: 220)
}

#Preview("Syncing") {
    SyncStatusView(label: "Synced 2 minutes ago", isSyncing: true)
        .frame(width: 220)
}

#Preview("Some items unreadable") {
    SyncStatusView(label: "Synced 2 minutes ago", unreadableCount: 3)
        .frame(width: 220)
}
