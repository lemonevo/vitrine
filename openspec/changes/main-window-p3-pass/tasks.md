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

- [ ] 3.1 Detail content capped at 480pt and centred, so a wide pane becomes margin rather than a gulf
      between a label and its value.
- [ ] 3.2 Rhythm: 16pt header→actions, 20pt between cards and to the footer.
- [ ] 3.3 Card rows: 100pt label column, 56pt trailing action slot, 42pt minimum height — one x for the
      copy glyphs across all three cards.
- [ ] 3.4 Type scale: title 22/semibold, card values 14, labels and meta 11.
- [ ] 3.5 Header controls as three styles at 26pt — filled, bordered, glyph — with hover and the
      post-copy state. First real `ButtonStyle`s in this app.
- [ ] 3.6 Measure white-on-fill for the prominent CTA's 12pt label and pick the fill from that
      (the current accent is ~3.5:1, which fails; see proposal "Deliberate limits").
- [ ] 3.7 Deltas: `detail-card-view` (card fill, caption size, column widths), `vault-browser-ui`
      (row anatomy), `toggle-favorite` (the star).

## 4. Verification, per cut

- [ ] 4.1 Full suite green, with the executed count equal to the `func test` declaration count.
- [ ] 4.2 Screenshots re-rendered in both appearances and actually looked at: `vault-login`,
      `vault-card`, `vault-identity`, `vault-ssh-key`, `sidebar`, `codes`, `auth-*`.
- [ ] 4.3 The specific thing a still image cannot show: hover, focus rings, the real `NSToolbar`
      chrome, and a fetched favicon (the harness always falls back offline).

## 5. Close-out

- [ ] 5.1 Delete `P3MainWindow.swift` and `P3MainWindowScreenshotTests.swift` — the mock's own header
      says to, and leaving it means two definitions of the same palette in one repo.
- [ ] 5.2 Remaining `.secondary` in sheets and edit forms, if that pass is taken up.
