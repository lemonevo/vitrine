# Codes as a destination — Tasks

## 1. The destination

- [x] 1.1 `SidebarSelection.verificationCodes` added, with `displayName`, `==` and `hash`. Its doc
      comment records what the sheet was for and what this gives up.
- [x] 1.2 The sidebar row is a `SidebarRowView` like Trash's: selectable, with a count slot, and the
      chevron removed — a row you are *in* does not lead somewhere else.
- [x] 1.3 `SidebarRowView` uses `AccessibilityID.Sidebar.verificationCodes`; the old
      `AccessibilityID.Vault.verificationCodesButton` no longer names this row.
- [x] 1.4 The list column renders it: `verificationCodesPane` sits beside the Trash branch, before the
      item list.

## 2. The sheet goes

- [x] 2.1 `VerificationCodesSheet.swift` deleted; `VerificationCodesPane.swift` replaces it, and the
      project file's six references follow (the app target lists files individually).
- [x] 2.2 `.sheet(isPresented: $viewModel.isShowingVerificationCodes)` and the flag itself removed.
- [x] 2.3 `AccessibilityID.VerificationCodes`: `sheet` → `pane`, `doneButton` removed.
- [x] 2.4 The menu command and the sidebar action select the destination instead of presenting a sheet.
- [x] 2.5 Rows are two lines for the 262pt column; the countdown ring, seconds and copy control are the
      same ones the detail pane uses.
- [x] 2.6 Clicking a row calls `viewModel.selectItem(id:)`, so the detail column behaves as it does for
      the item list.

## 3. The record

- [x] 3.1 `verification-codes` Decision 5 marked **SUPERSEDED** with a pointer to this change, keeping
      its reasoning as the cost of the override rather than deleting it.
- [x] 3.2 `VerificationCodesPane`'s doc comment states the exposure in its own words, so the argument
      does not have to be hunted down.
- [x] 3.3 This change's proposal and design record the trade, the alternative that was rejected (masking
      while the app is inactive, which would break the feature's purpose), and the guards that did not
      change.

## 4. Verification

- [x] 4.1 Both targets build (`xcodebuild build`, `build-for-testing`) — the mock repository's
      `items(for:)` switch and the screenshot harness's two codes shots were the only call sites that
      had to be updated, and the compiler named both.
- [ ] 4.2 **Not run:** the full suite. The codes' unit tests are untouched by this change, and per the
      working agreement a UI-shaped change is verified by building and looking rather than by a 3-minute
      suite run.
- [ ] 4.3 **Not verified, needs the running app:** that a row click drives the detail column, that the
      destination renders correctly at 240pt and at 340pt, and that the timers stop when the destination
      is left.
- [ ] 4.4 **Not done:** a count in the sidebar row. Every other row has one; this one shows none,
      because it needs the same predicate the codes view model uses, and duplicating it is how the two
      would drift.

## 5. The bug this change shipped with, and its cause

- [x] 5.1 The pane rendered its empty state and never left it. `.task { await viewModel.start() }` had
      been put **inside the `else` branch** — the branch that only runs once there are rows. Loading the
      rows is what makes them non-empty, so the load could never happen: an empty state and its own exit
      condition, each waiting on the other. The sheet had the `.task` on its outer container; moving it
      into the branch is what broke it, and the fix is to put it back on the container.
- [x] 5.2 Reported from the running app within a minute of the first build, which is the argument for
      building and looking rather than reasoning about a branch that reads plausibly.

## 6. Search and sort on this destination

Reported: the toolbar's search and sort did nothing here. They were the item list's controls, drawn on a
column that now hosts a second list. The reviewer chose to make them **work** rather than disappear.

- [x] 6.1 The toolbar's search field binds to `listSearchQuery`, which resolves to the codes query on
      this destination and to the item list's on every other. One field, two subjects — the field belongs
      to the column, not to a list.
- [x] 6.2 The sort menu offers the destination what it can be ordered by: **the two name orders only**.
      The other four (`Last Modified`, `Date Created`, each in two directions) describe fields a code row
      does not have, and offering them would be four items that do nothing.
- [x] 6.3 `displayedRows` filters on the name and the username, case-insensitively, and sorts with
      `localizedStandardCompare` — a plain `<` puts "item10" before "item9", which vault names are full
      of.
- [x] 6.4 **No matches is its own state.** A query that excludes every code is not an empty vault, and
      one message for both would tell the user their vault is empty when it is not. New identifier and
      two new localisation keys.
- [x] 6.5 ⌘F no longer calls `activateGlobalSearch()` on this destination. That call widens the item
      list's scope and drops the sidebar selection, which would take the user off the destination
      mid-keystroke; here ⌘F only has to reach the field.
- [ ] 6.6 **Not verified by a test.** The filtering is three lines and the risk is in the wiring — that
      the field really drives this list — which the probe cannot see, because the query lives in the
      view's state and the probe rebuilds the controls. Needs the running app.

## 7. Clicking a row: it jumped, and it did not copy

- [x] 7.1 **The jump was `selectItem(id:)`.** Its first line is `sidebarSelection = .allItems` — it
      moves the scope so the item is in the list it selects from, which is right for the item list and
      wrong here: it took the user off the codes destination. `highlightItem(id:)` was added for this
      pane: it resolves the item through `vault.itemDetail(id:)` and sets `itemSelection` without
      touching the scope.
- [x] 7.2 **Clicking a row now copies.** A list of codes exists for the moment something else asks for
      one, so the click does the thing the screen is for. It goes through `viewModel.copy(row)`, which
      routes a gated row through `copyGated` — tapping a masked row asks for the master password rather
      than handing the code over.
- [x] 7.3 **The row is marked**, because a copy with no visible effect is indistinguishable from a click
      that did nothing. The mark uses the item list's own selection fill
      (`Opacity.selectionFill` + `Spacing.selectionCornerRadius`), not a second treatment for the same
      idea.
- [ ] 7.4 The copy button inside the cell stays. It is the same action, but a discoverable one — the row
      tap is invisible until it is tried.
- [ ] 7.5 **Not verified:** that the click copies and marks, that a gated row prompts, and that the
      detail column follows without the scope moving. All three need the running app.
