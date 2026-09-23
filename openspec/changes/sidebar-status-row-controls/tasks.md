# Sidebar status row — Tasks

## 1. The row

- [x] 1.1 `SyncStatusView.onOpenSettings` added, optional, drawing nothing when nil — the same
      contract as `onSync`.
- [x] 1.2 The refresh control moved from the trailing end to the leading end; the spacer now sits
      between the status text and the gear.
- [x] 1.3 `settingsControl(_:)` added: `gearshape`, `Foreground.muted`, `.buttonStyle(.plain)`, with a
      tooltip, an accessibility label and an identifier.
- [x] 1.4 The status label held to one line with `.minimumScaleFactor(0.85)`, so English no longer
      wraps the row onto two lines at 216pt.
- [x] 1.5 The type's doc comment and the inline comment updated: they described a refresh at the end
      of the row, which is no longer where it is.
- [x] 1.6 A `#Preview("With controls")` added, so the arrangement is visible in Xcode without
      running the app.
- [x] 1.7 **The status dot removed, on request.** `hasSynced` is gone from the view and from the call
      site — it had no other consumer, and the view's own comment already said the label carries the
      content. The comment that argued the dot's case is replaced by one recording the decision, so
      the argument is not rediscovered and re-implemented.
- [x] 1.8 The token the dot motivated was **kept**: `Foreground.success`. Nothing about it is wrong —
      its measurements still hold — so the three places that claimed it exists *for the dot*
      (`DesignSystem.swift`'s doc, `ContrastTokenTests`' MARK, and the test's own name and failure
      message) were corrected instead. Removing it is a separate decision; see 5.3.

## 2. Wiring

- [x] 2.1 `AccessibilityID.Vault.settingsButton = "vault.button.settings"` added; `syncButton`'s doc
      comment corrected from "the end of the sidebar's status row" to the leading end.
- [x] 2.2 `VaultBrowserView` supplies `onOpenSettings: { openSettings() }` from
      `@Environment(\.openSettings)`.
- [x] 2.3 `PrizmApp`'s comment on the `Settings` scene corrected — it still said the window opens via
      "the gear toolbar button", which `main-window-p3-pass` had already removed.

## 3. Spec

- [x] 3.1 `specs/settings-screen/spec.md` delta added: a requirement for the sidebar row's entry point,
      and a note on the canonical requirement it sits beside.

## 3a. The item list's three controls move into the toolbar (added during review)

Asked for after the settings gear went in: create, sort and search together at the top-right of the
list column, icons only, search collapsed to a magnifier that expands.

- [x] 3a.1 All three are `ToolbarItem`s on the content column, after a flexible spacer, in the order
      create → sort → search.
- [x] 3a.2 The search is **not** `.searchable`. That hands the field to the window's toolbar, which
      draws it in the trailing slot beyond the detail column — so it can never sit beside the other
      two. Verified by rendering both arrangements; this is why the field is drawn by hand.
- [x] 3a.3 The field collapses to a magnifier and expands on click. Focus is set one run-loop turn
      after the reveal, because `@FocusState` cannot point at a view that is not in the hierarchy
      yet — setting it in the same turn is dropped, and reads as "the click did nothing".
- [x] 3a.4 Escape clears, collapses and defocuses, which is what the system field did for free and
      what the `global-search` requirement has a scenario for. ⌘F expands and focuses.
- [x] 3a.5 **`ToolbarSpacer(.fixed)` between each pair.** macOS 26 merges adjacent toolbar items into
      one shared capsule: without it, sort and search drew as a *single* control and three functions
      looked like two. The fixed spacer ends the group. Confirmed by rendering.
- [x] 3a.6 The field draws no background or border of its own — the toolbar's capsule is the chrome,
      as it is for the system field. Drawing a rounded rectangle inside the capsule produced a box
      inside a box. Confirmed by rendering.
- [x] 3a.7 The `sharedBackgroundVisibility(.hidden)` on these items was **removed**: the reviewer's
      reference image shows the capsule chrome, which reverses the earlier decision to hide it. The
      comment that argued for hiding it was rewritten rather than left contradicting the code.
- [x] 3a.8 Rendered both states through the real-toolbar probe before shipping, which is what
      established 3a.5 and 3a.6 — neither was visible from reading the code.
- [x] 3a.9 **The chrome is drawn, not borrowed.** A square content frame does **not** make macOS 26's
      shared capsule a circle — measured by rendering it, not assumed — so the three items hide the
      capsule and draw a 26pt disc from the app's own `Opacity.controlHover` / `Opacity.cardBorder`
      tokens, the same metrics as `GlyphControlStyle`. The expanded field draws a capsule for the same
      reason: the item can only wear one chrome, so it wears the one whose shape matches.
- [x] 3a.10 **Collapse on losing focus, when the query is empty.** Reported as "once it expands it will
      not go back" — Escape was the only way out, which is not how a toolbar search behaves. An
      un-cleared query keeps the field open on purpose: hiding an active filter behind a glyph would
      hide the fact that the list is showing fewer items than the vault holds.
- [x] 3a.11 **The disc matches the sidebar toggle, measured.** The reviewer's screenshot was measured
      rather than eyeballed: the toggle is 74px in a 2× capture (37pt), the discs were 52px (26pt, from
      `Spacing.controlHeight` — the size for controls *inside* a pane). `Spacing.toolbarDisc = 37` is
      now the toolbar's number, and the fill changed to the toggle's white-and-shadow treatment.
- [x] 3a.12 **The expanded field's width is computed, not fixed.** A fixed 130pt overflowed the column
      once the discs grew to 37pt, pushing the group off column 2's trailing edge. The column's width is
      read with `onGeometryChange` and the field takes what is left after the discs and their gaps,
      clamped to 80–180pt — the floor being why the column's own 240pt minimum matters.
- [x] 3a.13 **The field is the discs' height.** It was 21pt against their 37pt, which is what "it got
      shorter when it expanded" described. All four controls in the row are now one height.
- [x] 3a.14 **The first attempt at 3a.13 did not work, and the reason is modifier order.** The height
      frame was applied at the *call site*, outside the view that draws the capsule: `.frame` after a
      `.background` sizes the layout but not the shape, so the capsule stayed at the content's 21pt and
      the field still looked short. Both dimensions now go into `searchField(width:)` *before* the
      background. This is the second time in this change that modifier ordering — not the API — was the
      bug; the first was the box-inside-a-box at 3a.6.
- [x] 3a.15 Verified by measuring the rendered probe rather than looking at it: the capsule's rounded
      ends measure 74px = 37pt in a 2× capture, the same as the discs.

## 4. Verification

- [x] 4.1 Full suite: **1572 tests, 0 failures** (`** TEST SUCCEEDED **`), 1566 before — the six added
      are the probe shots.
- [x] 4.2 Rendered before/after, and the render read: `[refresh] [dot + status] … [gear]`, one line in
      English at the real width. Output at `/tmp/prizm-design/probe/`:
      `STATUS-ROW-COMPARE.png`, `sidebar-status-row.png`.
- [x] 4.3 No new localisation keys: `"Settings"` exists in both tables, confirmed by grepping rather
      than assumed.

## 5. Not done, and why

- [ ] 5.1 **The button has not been pressed.** The action resolves to the `Settings` scene and the
      suite covers the wiring's shape, but nothing in this repository exercises a click and asserts
      that the window appeared — that needs a running, unlocked app. The same gap the SSH agent records
      for its own end-to-end path. **This also leaves the "both routes reach one window" scenario
      unverified**: it rests on `openSettings()` activating an existing Settings window rather than
      creating a second, which is how a single `Settings` scene behaves but which no test here checks.
- [ ] 5.2 **The gear's icon weight was not compared against the refresh glyph** at rendering. They are
      both `Foreground.muted` at the default symbol size, which is what the picture shows, but a
      designer might want the gear a step smaller than the refresh since it is the secondary action.
- [ ] 5.3 **`Foreground.success` now has no consumer.** It is the palette's positive-state colour,
      kept because it is correct and measured; but the two contrast tests pinning it and the numeric
      palette entry behind it exist for a control that no longer exists. Deleting them is defensible
      and so is keeping them for the next positive state — that call belongs to the owner, and this
      change records which way it went (kept) rather than leaving the question unasked.
- [x] 5.4 `xcodebuild test` does not touch `dist/Vitrine.app` — the two build paths are independent,
      and a change can be fully green while the app on screen is stale. Discovered by making exactly
      that mistake; the rebuild and relaunch are part of shipping a UI change here, not an extra.
