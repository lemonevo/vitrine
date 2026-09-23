# Codes as a destination — Proposal

## Why

Verification codes shipped behind a sheet: a sidebar row opened a modal list, and dismissing it was how
you stopped showing every second factor in the vault. That was a security decision — the sheet's own
comment and Decision 5 of the `verification-codes` change both say so — and it made the feature the one
thing in the window that did not behave like the rest of the window. The reviewer asked for it to be a
destination like Trash: a row in the sidebar, a list in the middle column, no popup.

This change does that, and carries the cost in writing rather than dropping it.

## What Changes

- `SidebarSelection` gains `.verificationCodes`. The sidebar row becomes a normal, selectable row: same
  highlight, same anatomy, and the chevron goes with the sheet — a row you *are in* does not lead
  somewhere else.
- The list column renders the codes in that column, under the window's toolbar, instead of in a sheet.
  Rows are laid out for a 262pt column (code under the name) rather than a 420pt sheet.
- Clicking a row selects that item, so the detail column behaves as it does for every other list.
- The sheet, its dismiss button, `isShowingVerificationCodes`, and the retained-window plumbing are
  deleted. The rows' timers still start on entry and stop on exit; leaving the destination is now the
  dismissal.
- The existing entry point — the menu command and the toolbar button — selects the destination rather
  than presenting a sheet.

## What does NOT change

Every guard the sheet carried, because they are not about modality:

- A re-prompt-protected item stays masked in the list until the master password is given, through the
  same `RevealGateBinding` the detail pane uses.
- The stored seed is still never on screen and never on the clipboard; the row shows a derived code.
- Copying still goes through `copyGated`, so a gated row cannot be walked around by clicking the value.

## Non-goals

- **Editing or adding seeds here** — the item's edit form owns that.
- **A count in the sidebar row.** Every other row shows one; this shows none, because "how many codes"
  is not answerable from `itemCounts` without duplicating the predicate that decides which logins carry
  a usable key. Worth doing, not worth guessing at.

## Capabilities

- `verification-codes` (its reachability and its presentation)
- `vault-browser-ui` (the sidebar's rows and the list column's destinations)

## Impact

- The vault's second factors are now on screen for as long as the destination is selected. That is the
  whole of the trade, and it is the user's to carry: they asked for it knowing the sheet existed, and
  Decision 5's reasoning is quoted in `VerificationCodesPane`'s doc comment rather than deleted.
- Suite: the codes' unit tests are untouched. The screenshot harness's two codes shots now build a pane.
