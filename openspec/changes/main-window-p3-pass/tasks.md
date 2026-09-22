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

### Deliberate deviations from the mock in cut ②

Three things §6 draws that the live sidebar does not need, each checked rather than assumed:

- [x] **Counts stay on `.badge`.** The mock's complaint was "86 and 1 at two different x values". The
      render shows `.badge` already right-aligns every count in a column; a fixed 24pt frame would be a
      second mechanism doing what the first one already does.
- [x] **No custom selection in the sidebar.** `.listStyle(.sidebar)` already draws a rounded accent fill,
      which is the mock's own mark. Adding the bar there too would be a second signal for one state.
      Caveat recorded honestly: the harness window is never key, so its screenshot shows the *inactive*
      grey version of the native selection — what the live pane looks like in a key window is not
      verifiable from here, and nobody should read the shot as confirming it.
- [x] **No fixed sidebar row height.** §6 asks for one section rhythm and one indent; it does not ask for
      a row height, and the mock's 30pt is incidental. Forcing it would risk clipping the folder rows'
      badges for a goal the pass never stated.

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

## 4. Verification, per cut

- [x] 4.1 Full suite green after each cut, with the executed count equal to the `func test` declaration
      count: cut ① 1557/0, cut ② 1553/0 (five opacity tests became one), cut ③ see 4.6.
- [x] 4.2 Screenshots re-rendered and actually looked at, both appearances: `vault-login`,
      `vault-card`, `vault-identity`, `vault-ssh-key`, `sidebar`, `codes`, `auth-*`. The list selection,
      the 480pt column, the aligned action column and the filled CTA were confirmed from the render, not
      from the code.
- [ ] 4.3 **Still not verifiable from here:** hover, focus rings, the real `NSToolbar` chrome, a fetched
      favicon (the harness always falls back offline), the *active* appearance of the native sidebar
      selection, and Increase Contrast rendering. Each is a colour or a state a still image cannot show.
- [x] 4.4 A race the suite surfaced while verifying cut ③ — not from it, and not a flake.
      `TOTPCodeViewModel.scheduleNextRefresh` hands its work to the main actor with `Task { @MainActor }`,
      so a refresh queued just before `stop()` survives the stop and derives one more code.
      `test_timer_keepsTheCodeCurrentAndStopsWhenAsked` failed on it once in three full runs and then
      passed again, which is what a probabilistic test is for. Fixed by re-checking `isRunning` inside the
      hopped-to task; the test's comment now says the guard is the fix so nobody stabilises the test by
      deleting the assertion.

## 5. Close-out

- [x] 5.1 The mock and its screenshot test left the tree. Deleted would have been irreversible — they were
      never committed, and the mock carries the account identifiers the pass was reviewed against — so they
      are moved to `/tmp/prizm-design/mock-source/`, which is lost on reboot. The design record that has to
      outlive that is this change's proposal and the four deltas.
- [ ] 5.2 Remaining `.secondary` in sheets and edit forms (import/export, health report, attachment
      sheets, verification codes, the edit forms), and the yellow warning banner's icon-on-fill pair.
      Same defect class as cut ①, different screens; not swept in here so the numbers stay attributable.
