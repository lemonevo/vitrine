# Tasks — main window, P3 pass

Delivered in three cuts, lowest risk first. Each cut builds, passes the full suite, and is committed on
its own; the mock is deleted only after cut ③, because until then it is the reference.

## 1. Cut ① — colour and contrast

- [x] 1.1 `Foreground.mutedAlpha = 0.68`, separated from the `Color` so the test composites the same
      number the renderer does.
- [x] 1.2 `ItemType.tintComponents` + `tint` resolved per appearance. One definition, so the eight
      consumers (sidebar type rows, list chip and badge, favicon fallback, detail chip) all move
      together — which is the reason the extension exists at all.
- [x] 1.3 `Foreground.success` for the sync dot (`Color.green`, 2.22:1 light) and `Foreground.favorite`
      for the star (`Color.yellow`, 1.28:1 on the light window) in its three sites. `FaviconView`'s
      fallback glyph default moved from `.secondary` to `Foreground.muted`.
- [x] 1.3b The yellow *banner* (`VaultBrowserView`'s warning row, the edit forms' glyphs, the strength
      bar) is left alone: it is a background-plus-icon pair with its own question, and it is not in the
      main window's three panes. Recorded as remaining work in §5.2.
- [x] 1.4 `.secondary` / `.tertiary` removed from every foreground in the main window: `SidebarView` (9),
      `SyncStatusView` (2), `ItemRowView` (1), `ItemDetailView` (4), `CardBackground` (2),
      `FieldRowView` (2 + the "COPIED" word), `TOTPCodeView` (2 + "COPIED"), `AttachmentsSectionView` (2),
      `AttachmentRowView` (2), `CustomFieldsSection` (3), `PasskeysSection` (6),
      `PasswordHistorySection` (4), `TrashView` (1).
- [x] 1.5 Left alone on purpose: `Color.secondary.opacity(...)` as a *fill* (trash banner, TOTP ring
      track), the 2pt accent drag stroke, the drop-target fill.
- [x] 1.6 `ContrastTokenTests` — 8 tests. Two of them assert that the *rejected* values still fail
      (0.62 under 4.5:1, system yellow under 3:1), so neither can be reinstated as a preference.
- [x] 1.7 `CLAUDE.md`'s foreground table corrected, including how the wrong number was produced.
- [x] 1.8 `accessibility-contrast` delta: a recorded ratio must be reproducible by a test, and type
      colours are measured on their own chip.

## 2. Cut ② — list and sidebar (§5, §6 of the pass)

- [x] 2.1 Item rows: 40pt, chip 26pt with a 14pt glyph, name 13/medium, subtitle 11 muted. The chip
      shrink is what makes 40pt enough — at 30pt the row needed 44.
- [x] 2.2 Favourite star in a **reserved** 20pt trailing column, so a favourited row is not the only one
      whose text ends early. Resolves the `toggle-favorite` REMOVED vs `vault-browser-ui` contradiction
      in favour of keeping the star; the delta says why the REMOVED record's reasoning does not hold.
- [x] 2.3 Selection: accent fill + 3pt leading bar through `Opacity.selectionFill`, with
      `List(selection:)` still owning the selection — keyboard arrows, ⌘-click and VoiceOver traits
      unchanged. Verified in the render: the native full-width band is suppressed by
      `.listRowBackground`, so there is exactly one selection mark, not two.
- [x] 2.4 Row hairline drawn by the app (`.listRowSeparator(.hidden)` + an `Opacity.hairline` rule),
      inset to the text column, and absent under the last row.
- [x] 2.5 Sidebar section captions: 11pt semibold with 0.5pt tracking, through the shared
      `Typography.sectionLabel`.
- [x] 2.6 `Opacity.selectionFill` added, and `AccessibilityTier2Tests`' five copy-pasted direction tests
      replaced by one table over **all nine** functions — the five old ones covered five of eight and let
      `typeChip`, `hairline` and `authCardBorder` go unasserted while a contrast delta required them.

### Cut ② deviations, later reversed by the user

Cut ② declined three things the mock draws — the sidebar's fixed count column, its own selection marks,
and a fixed row height — on the argument that the native equivalents already achieved the same result.
The user's answer after seeing the running app was "我要的是全面仿造第一张做", so cut ④ implements all
three. The reasoning that declined them was not unreasonable, but it was mine, and the picture was the
spec.

## 3. Cut ③ — detail and controls (§1, §3, §4, §7)

- [x] 3.1 Detail content capped at `Spacing.detailContentWidth` (480pt) and centred.
- [x] 3.2 Rhythm: `detailHeaderBottom` 14→16, `detailActionsBottom` 18→20, `cardBottom` 18→20,
      `sectionLabelGap` 5→6, header columns 8→12 apart with a 4pt name/breadcrumb gap.
- [x] 3.3 Card rows: label column 130→100, a new reserved 56pt trailing slot, 42pt minimum height.
      **The masked row's eye moved into the slot too** — it sat after the dots, so it was at a different
      x from every copy glyph in the pane.
- [x] 3.4 Type scale: `detailTitle` 20→22, `detailFieldValue` 13→14, `detailFieldLabel` 12→11,
      `detailChipIcon` 24→22, card captions get the same 0.5pt tracking as the sidebar's.
- [x] 3.5 `ControlStyles.swift` — the app's first `ButtonStyle`s: filled, bordered, glyph, all 26pt with
      a 12pt glyph, plus `GlyphControl` for the affordances that cannot be buttons because their row
      already owns the tap. The old hand-drawn `DetailActionLabel` is deleted, and with it
      `Spacing.actionButtonVertical` and `Typography.chipIcon`, which nothing else used.
- [x] 3.6 The filled action's white label measured against candidate fills: `controlAccentColor` 4.02:1
      both appearances, `linkColor` 5.26:1 light but **2.83:1 dark**, so the fill is a hand-picked pair
      at 6.37:1 / 4.81:1 and is deliberately accent-independent.
- [x] 3.7 A header copy action now confirms for 0.8s with a checkmark and the word "Copied" (an existing
      key in both tables), which the row already did and the header button did not.
- [x] 3.8 Deltas: `detail-card-view` (column, slots, control roles, and the card fill this change
      refuses to adopt, with the reason), `vault-browser-ui` (row anatomy), `toggle-favorite` (the star).

### Verified from the render rather than assumed

- `Link` **does** accept `.buttonStyle`, so "Open website" can share the bordered style with the two
  buttons. The deleted `DetailActionLabel`'s comment claimed the two could not agree on a style; that
  was why the label view existed, and it is not true.
- The filled control draws its real colour in the harness, where `.borderedProminent` would have drawn
  grey — the reason it is hand-drawn.
- The reveal eye keeps `Color.accentColor`: `detail-card-view` pins it there. Making it match the muted
  copy glyphs would have been a spec violation for a cosmetic gain.
- The card fill stays `#FAFAFA` / `#2C2C2C` rather than the mock's white / `#212121`: in light aqua the
  pane's own background resolves to white, so the mock's card would be separated from its window by
  nothing but the hairline. Recorded in the delta.

## 4. Cut ④ — match the picture everywhere (the user's override)

- [x] 4.1 Titlebar: the sort control carries the current order's short word ("Name" / "Modified" /
      "Created") with its glyph, the refresh is a bare muted glyph, and the create menu reads
      "New Item" in the action colour — flat, no circular chips. Two new keys in both tables
      (`Modified`, `Created`); `Name` and `New Item` already existed.
      `ItemSortOrder.toolbarLabel` is separate from `displayName` because the menu needs the full order
      name and the titlebar would be the widest thing on the bar — and would change width on every
      choice, shuffling its neighbours.
- [x] 4.2 Column widths pinned to the pass: sidebar 216 ideal (max 280), list 262 ideal (max 340).
- [x] 4.3 Sidebar rows: 30pt, `List` separators hidden, counts moved off `.badge` into a fixed 24pt
      right-aligned `monospacedDigit` column, and the same selection marks as the list (accent fill +
      3pt bar) shared through one `sidebarRow(isSelected:contrast:)` modifier so the pane's four row
      kinds cannot disagree.
      Two rendering bugs the first screenshot caught: the bar landed **on top of** the row icon until the
      content got a 10pt leading inset, and stacking the pass's 16pt above a section header on top of the
      `List`'s own spacing doubled the gap — the pass describes a hand-built column, not a list, so only
      the 5pt below is applied.
- [x] 4.4 Card fill adopted from the pass: white / `#212121`. The reason cut ③ declined it was measured
      wrong — see the `detail-card-view` delta, which records the mistake.
- [ ] 4.5 **Not verifiable from here, and the user is the check:** whether macOS 26 renders those toolbar
      items flat. `.menuStyle(.button)` + `.buttonStyle(.plain)` is the standard route, but the toolbar is
      window chrome and the render harness cannot draw it — so this one is confirmed only by looking at
      the running app.
- [ ] 4.6 The `»` control macOS adds at the top right of a three-column split is not in the picture and
      is not ours to remove without a documented API. Flagged, not fixed.

## 5. Verification, per cut

- [x] 5.1 Full suite green after each cut, with the executed count equal to the `func test` declaration
      count: cut ① 1557/0, cut ② 1553/0 (five opacity tests became one), cut ③ 1550/0 (the mock's three
      tests left with it), cut ④ 1550/0.
- [x] 5.2 Screenshots re-rendered and actually looked at, both appearances: `vault-login`,
      `vault-card`, `vault-identity`, `vault-ssh-key`, `sidebar`, `codes`, `auth-*`. The list selection,
      the 480pt column, the aligned action column and the filled CTA were confirmed from the render, not
      from the code. The sidebar's first render in cut ④ showed two bugs no code read would have caught —
      the selection bar sitting on the icon, and doubled section gaps.
- [ ] 5.3 **Still not verifiable from here:** whether macOS 26 draws the toolbar items flat (cut ④; the
      harness cannot render window chrome, so the user's own look is the check), hover states, focus
      rings, a fetched favicon, and Increase Contrast rendering.
- [x] 5.4 A race the suite surfaced while verifying cut ③ — not from it, and not a flake.
      `TOTPCodeViewModel.scheduleNextRefresh` hands its work to the main actor with `Task { @MainActor }`,
      so a refresh queued just before `stop()` survives the stop and derives one more code.
      `test_timer_keepsTheCodeCurrentAndStopsWhenAsked` failed on it once in three full runs and then
      passed again, which is what a probabilistic test is for. Fixed by re-checking `isRunning` inside the
      hopped-to task; the test's comment now says the guard is the fix so nobody stabilises the test by
      deleting the assertion.

## 6. Close-out

- [x] 5.1 The mock and its screenshot test left the tree. Deleted would have been irreversible — they were
      never committed, and the mock carries the account identifiers the pass was reviewed against — so they
      are moved to `/tmp/prizm-design/mock-source/`, which is lost on reboot. The design record that has to
      outlive that is this change's proposal and the four deltas.
- [ ] 5.2 Remaining `.secondary` in sheets and edit forms (import/export, health report, attachment
      sheets, verification codes, the edit forms), and the yellow warning banner's icon-on-fill pair.
      Same defect class as cut ①, different screens; not swept in here so the numbers stay attributable.

## 7. Cut ⑤ — the controls, where the picture and the user's follow-ups put them

- [x] 7.1 The browser's controls are declared on the **detail column** with `ToolbarSpacer(.flexible)`
      ahead of them, which is the only arrangement that draws them at the window's trailing edge.
      Measured, in a window-sized probe of the three-column split, against four candidates: the content
      column, the split view itself, a `.primaryAction` group, and the spacer. The first three all drew
      at the leading edge within the content column's span; `placement` has no effect inside a column.
      Two earlier attempts guessed instead and were rejected against the running app.
- [x] 7.2 `folder.badge.plus` in the sidebar's FOLDERS caption is drawn at caption weight — 12.5pt and
      `Foreground.muted` — instead of `.title3` in the primary colour, which made it the heaviest thing
      in the pane and made the caption row taller than the captions above it. The symbol and its label
      are untouched: `vault-folder-organization` and `voiceover-labels` pin them, and this is the only
      place a folder can be created from (no menu item, no context menu).
- [x] 7.3 The verification-codes row gained the trailing chevron the picture shows and now shares the
      row anatomy of `SidebarRowView` (icon column, title, trailing slot), so it no longer sits at a
      different indent from every row around it. Confirmed in the render.
- [x] 7.4 Manual sync moved from the titlebar to the end of the sidebar's status row, where the state it
      refreshes already lives. `SyncStatusView` takes an optional `onSync` and draws the control only
      when given one. ⌘R is unchanged — it has always been the View menu's item. The control stays a
      glyph while a sync runs rather than becoming a second spinner beside "Syncing…".
- [x] 7.5 The settings gear is gone from the toolbar, with `AccessibilityID.Vault.settingsButton`
      deleted and the UI test that reached it repointed at the sync control (the browser's remaining
      icon-only button). Recorded as a `settings-screen` delta: the ⌘, route and the `Settings` scene
      are untouched, and they are now the only route.
- [x] 7.6 The create menu is now **absent from the view tree** in Trash, not merely disabled —
      `list-column-header` asked for that from the start, so the ⌘N shortcut that rides in its hidden
      companion button goes with it. It had been unconditional since the requirement was written.
- [x] 7.7 The sidebar column's width: its `navigationSplitViewColumnWidth` was being dropped because
      `.searchable` and `.toolbar` were applied after it, so the pane laid out at 144pt — below the
      200pt minimum declared in the same expression — while the content column, which applies the same
      modifier last, held its 262pt ideal. Moved last; the saved-column readout then gives 210/264pt
      against the reference's 216/262. The first diagnosis blamed a stale autosaved split frame and was
      wrong: the stale value (140) was the width the app picks by itself.
- [x] 7.8 The remaining toolbar items hide the macOS 26 shared capsule with
      `.sharedBackgroundVisibility(.hidden)`, so they read as flat labels. **Not verifiable from the
      harness** — the toolbar is window chrome — so the running app is the check.
- [x] 7.9 The app follows the device appearance again. Cut ④'s `NSApplication.shared.appearance = .aqua`
      is removed; no spec ever required light-only, and the dark renders are the standing check.
- [ ] 7.10 **Still open:** the `⌘F` hint inside the search field. The picture shows it, but the system
      draws it and the shortcut here is a zero-size hidden button rather than a menu item, so the field
      has no shortcut to display. The two routes both have costs — a hand-built field loses
      `SearchJourneyTests`' `app.searchFields` matches and the native behaviours, and a real menu command
      is not guaranteed to make AppKit draw the hint. Undecided, not silently dropped.

