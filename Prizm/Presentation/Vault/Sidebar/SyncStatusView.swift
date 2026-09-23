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
/// progress is visible right beside the control that started it. That control is the refresh button
/// at the **leading** end of this row, with the settings gear at the trailing end — the two ends
/// carry the two actions and the status sits between them, rather than both actions stacking on one
/// side of a readout.
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

    /// Items the last sync could not read. Zero renders nothing.
    var unreadableCount: Int = 0

    /// Starts a manual sync. Nil draws no control at all, so the view stays a pure readout wherever
    /// only the readout is wanted (the previews below, and any future caller).
    var onSync: (() -> Void)? = nil

    /// Opens the Settings window. Optional for the same reason as `onSync`: a caller that wants the
    /// readout alone gets no button it did not ask for.
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The refresh control leads the row and the gear closes it, so each end of the row owns
            // one action.
            //
            // **The whole readout is the control, not just the glyph.** The icon is 12pt, which is a
            // small target for the one action this row exists to offer, and the label beside it is part
            // of the same thing rather than a separate readout — so the tap area covers both. When
            // there is no `onSync` the row stays a pure readout, with nothing to click.
            if let onSync {
                Button(action: onSync) { statusArea }
                    .buttonStyle(.plain)
                    .disabled(isSyncing)
                    .help(L("Sync Now (⌘R)"))
                    // The label is the visible status, so VoiceOver should read that; the *action* goes
                    // in the hint. Labelling this "Sync Now" would replace "Synced 2 minutes ago" with
                    // the verb and lose the state, which is the half a user actually wants.
                    .accessibilityHint(L("Sync Now (⌘R)"))
                    .accessibilityIdentifier(AccessibilityID.Vault.syncButton)
            } else {
                statusArea
            }
            Spacer(minLength: 0)
            if let onOpenSettings {
                settingsControl(onOpenSettings)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sidebarHorizontal)
        .padding(.top, Spacing.rowVertical)
        .padding(.bottom, Spacing.sidebarStatusBottom)
    }

    /// The glyph and the label, which together are the refresh control.
    ///
    /// `contentShape` on the container rather than on each part: without it the gap between the glyph
    /// and the text is a dead zone, which is most of the target this change exists to widen.
    private var statusArea: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(Foreground.muted)
                .accessibilityHidden(true)
            statusText
        }
        .contentShape(Rectangle())
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Syncing…"))
                } else {
                    // The status dot that used to open this row was removed on request. It was there
                    // to make "synced or not" legible at a glance from across the room, which the
                    // label already does in words — and next to a refresh control it read as a third
                    // glyph in a row that has two. This note is left so the argument is not
                    // rediscovered and re-implemented: the label is the status, by decision.
                    Text(label)
                }
            }
            .font(Typography.listSubtitle)
            .foregroundStyle(Foreground.muted)
            // One line, and it shrinks slightly rather than wrapping.
            //
            // The row now spends ~44pt of its ~176pt on the two controls, which leaves the English
            // "Synced 2 minutes ago" right at the boundary: at the sidebar's 216pt it wrapped onto a
            // second line, and a status row that grows a line depending on the language is the kind
            // of thing that only shows up in one of them. Chinese is unaffected — "同步于 2 分钟前"
            // is about half the width. Truncating was the alternative and it is worse: the label is
            // the whole content of the row, so losing its tail loses the answer.
            .lineLimit(1)
            .minimumScaleFactor(0.85)
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
    }

    /// The Settings entry point, at the trailing end of the row.
    ///
    /// Muted and unlabelled on purpose: settings is not what this row is about, and a control drawn
    /// at the same weight as the sync state would compete with the one piece of information here.
    /// It is a second route to the same window ⌘, opens, for the same reason the app menu keeps the
    /// item — a Mac user looks for it in both places.
    private func settingsControl(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .foregroundStyle(Foreground.muted)
        }
        .buttonStyle(.plain)
        .help(L("Settings"))
        .accessibilityLabel(L("Settings"))
        .accessibilityIdentifier(AccessibilityID.Vault.settingsButton)
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

/// The row as the browser draws it: refresh leading, status between, gear trailing.
#Preview("With controls") {
    SyncStatusView(label: "Synced 2 minutes ago",
                   onSync: {},
                   onOpenSettings: {})
        .frame(width: 216)
}
