# Vault UI redesign — Tasks

## 1. Artifacts

- 1.1 `proposal.md`, `design.md`, `tasks.md` (this file).
- 1.2 Delta specs: `item-sorting`, `detail-card-view`, `accessibility-contrast`, `vault-browser-ui`,
      and the three the redesign turned up once the detail pane moved — `vault-folder-organization`,
      `org-vault-items`, `toggle-favorite`.

## 2. Tokens

- 2.1 Add `ItemType.tint` as a Presentation extension (design D1).
- 2.2 Add `Opacity.typeChip`, `Opacity.listSelection`, `Opacity.hairline` (design D7).
- 2.3 Add the new `Typography` roles: `sectionLabel`, `detailTitle`, `breadcrumb`, `detailFieldLabel`,
      `detailFieldValue`, `actionButton`, `totpCode`, `metaLine`, `orgBadge`, `chipIcon`; revalue
      `listTitle`, `listSubtitle`, `sidebarRow`.
- 2.4 Add the new `Spacing` roles: sidebar row padding/icon width/section gaps, item chip size and row
      padding and divider inset, detail margin, label-column width, row paddings, chip radii, action
      button padding, TOTP ring.
- 2.5 Update the token table in `CLAUDE.md` so the "no raw literals in views" rule stays enforceable.

## 3. Sidebar

- 3.1 Section headers → uppercase small labels; keep the pinned section order.
- 3.2 Rows: tinted icon, denser vertical padding, right-aligned count.
- 3.3 Folder rows keep `folder.badge.plus`, nesting, drag-and-drop, rename/create and context menus.
- 3.4 Organisation and collection rows keep the disclosure, the `+` button and `canManageCollections`.
- 3.5 `Verification Codes` keeps its identifier and its button-not-a-scope behaviour, restyled to match.
- 3.6 Apply the `AccessibilityID.Sidebar` identifiers, which were declared and never attached.
- 3.7 `SyncStatusView`: status dot driven by `lastSyncedAt`; the unreadable-items line untouched.
- 3.8 Move `.searchable` to the sidebar column with `placement: .sidebar` (design D3).

## 4. Item list

- 4.1 Remove the letter headings and the `sections` grouping; one flat list under every sort order.
- 4.2 Row: 30pt tinted chip containing `FaviconView` (design D2), name, subtitle, org badge, star.
- 4.3 Keep the context menu, the move-to-trash confirmation and the empty state.
- 4.4 Apply `AccessibilityID.ItemList.list`, which the attachment UI journeys query and nothing set.
- 4.5 Delete `ItemSortOrder.isNameBased` and its test — the headings were its only consumer.

## 5. Detail pane

- 5.1 Header: 44pt tinted chip, name, breadcrumb (username · folder · organisation), favourite star.
- 5.2 Action row: Copy password (through the gate), Copy code, Open website (design D5).
- 5.3 `DetailSectionCard` header → uppercase small label; card body unchanged (`CardBackground` stays).
- 5.4 `FieldRowView`: shared `DetailFieldLabel` column, proportional values, monospaced only for
      values that are transcribed, always-visible copy icon.
- 5.5 `TOTPCodeView`: same label column, larger monospaced code, countdown ring replacing the bar.
- 5.6 Metadata footer → one relative-time line, formatted in the interface language.
- 5.7 Attachments section and rows adopt the same paddings and value font.
- 5.8 Remove the separate Organization and Folder cards; the breadcrumb carries both.
- 5.9 Localise the new strings in `en` and `zh-Hans`.

## 6. Verification

- 6.1 Screenshot harness renders the redesigned real views (light/dark, all five types, trash,
      empty selection, re-prompt item) — `PrizmTests/Presentation/Design/`.
- 6.2 Delete `ProposedDesignMockup.swift` once the real views match (design D9).
- 6.3 Full `PrizmTests` suite: 1432 passed, 0 failed.
- 6.4 `ACCESSIBILITY.md` 1.4.13 updated for the permanent copy affordance; `DEVELOPMENT.md` test count.
- 6.5 **Not verifiable offscreen — needs a running app:**
      - the search field's placement in the sidebar, and that ⌘F still focuses it;
      - the sidebar's native selection highlight, which only renders when the window is key;
      - favicons actually loading (the harness has no network, so every chip shows the fallback glyph);
      - the re-prompt gate firing from the header's Copy password / Copy code buttons.
- 6.6 Canonical specs under `openspec/specs/` still describe the pre-redesign behaviour for the six
      requirements the deltas replace. They are updated when this change is archived, per the repo's
      openspec workflow.

## 7. Follow-up from the live screenshot

Drawn against the real vault (86 items, 84 of them logins) rather than the fixture, which changed the
verdict on part of §2 and surfaced four local defects.

- 7.1 **The per-type tint does not work in the item list.** At 84 logins out of 86 the chips are one
      uniform colour and distinguish nothing. The tint stays in the sidebar, where the reader really is
      choosing among five types. Removing it from the list is part of the list redesign, not this batch.
- 7.2 Passkeys and password history: give each a section label above its card like every other card,
      and move the count into the collapsed row. They previously rendered as a titleless card with the
      heading inside it, which read as a rendering glitch beside the labelled cards. The collapsed row
      offers to expand rather than claiming to load — nothing has been requested yet.
      (`SectionCountLabel`, shared by both.)
- 7.3 The one-time-code row: the copy icon now appears only once the code is revealed. Beside eight
      bullets it asked what it copied, and the answer was a code nobody could see.
- 7.4 The metadata line: "Updated" is an age only within 30 days and an absolute date beyond, because
      "上个月" is vaguer than the date it replaced — on the one value the reader is judging for
      staleness. Clock-skewed future dates take the absolute branch rather than reading as the future.
      Extracted as `ItemDetailView.updatedLabel` and tested (`ItemDetailUpdatedLabelTests`, 7 cases).
- 7.5 New strings: `Expand`, `Loading…` in both languages. `Expand` rather than `Show` so the key does
      not collide with the reveal controls, which mean a different verb.
- 7.6 Suite after this batch: 1453 passed, 0 failed.
