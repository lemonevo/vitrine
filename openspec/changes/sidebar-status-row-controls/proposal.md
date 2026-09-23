# Sidebar status row: refresh leading, settings gear trailing — Proposal

## Why

The sidebar's status row carried one control, the refresh button, pushed to its trailing end by a
spacer. Asking for a second route to Settings leaves the row needing to hold two actions and one
readout, and the arrangement that was asked for is the one where each end of the row owns an action:
refresh at the leading end, the gear at the trailing end, the status between them.

It also fixes a smaller thing the row had going for it: the refresh sat at the far end of a 216pt
column with nothing between it and the status text but empty space, so "beside the state it refreshes"
— the reason it was moved out of the titlebar in the first place — was true of the code's intent and
not of the layout.

## What Changes

- `SyncStatusView` gains `onOpenSettings`, drawn as a muted gear at the trailing end. Optional, like
  `onSync`: a caller that wants the readout alone still gets no button it did not ask for.
- The refresh control moves from the trailing end to the leading end, adjacent to the status text.
- The status label is held to one line and allowed to shrink slightly. The two controls take about
  44pt of the row's ~176pt, which leaves the English "Synced 2 minutes ago" on the boundary — it
  wrapped to a second line at the sidebar's real width before this guard.
- `VaultBrowserView` supplies the action from `@Environment(\.openSettings)`, so the button opens the
  app's existing `Settings` scene and ⌘, and the gear cannot drift to two different windows.
- `AccessibilityID.Vault.settingsButton` added; `syncButton`'s own doc comment corrected, since it
  named the end of the row the control has left.

## Non-goals

- **A gear in the titlebar.** `main-window-p3-pass` removed that one deliberately — the approved
  reference draws nothing between the traffic lights and the sidebar toggle. This button is inside
  the window's sidebar column, at its bottom, which is not that strip.
- **Changing what Settings contains**, or where else it can be reached from. ⌘, and the app menu item
  are untouched.
- **The toolbar question** (where the search field, sort and create controls belong). Measured and
  rendered separately; not decided here.

## Capabilities

- `settings-screen` — its entry points, which the canonical spec describes in a way that is now wrong
  twice over (see the delta)
- `vault-sync-status` — the row the refresh control lives in
- `voiceover-labels` — the new control needs a label and an identifier like the one beside it

## Impact

- One new control in the sidebar's status row; one existing control moved within it.
- No new localisation keys: `"Settings"` already exists in both tables, and the gear reuses it for
  its tooltip and its accessibility label.
- Suite: 1566 → 1572 (six probe shots), 0 failures. The probes render the real `SyncStatusView`, so
  the row in the pictures is the row in the app.
