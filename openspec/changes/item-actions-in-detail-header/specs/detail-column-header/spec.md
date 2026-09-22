## MODIFIED Requirements

### Requirement: Detail pane toolbar shows contextual action buttons
The detail column's toolbar SHALL display only the commands that belong to a **trashed** item. The
commands that belong to an active item — favouriting it and editing it — are in the item's header,
beside the name they act on. See `toggle-favorite` and `detail-card-view`.

Button visibility depends on the current state:

**Trashed item selected:**
- `[Restore]` button via `ToolbarItem(placement: .primaryAction)` — restores the item to the active
  vault immediately, with no confirmation alert (non-destructive). SHALL carry
  `AccessibilityID.Trash.restoreButton`.
- `[Delete Permanently]` button via `ToolbarItem(placement: .destructiveAction)` — triggers a
  confirmation alert before permanent deletion. SHALL carry
  `AccessibilityID.Trash.permanentDeleteButton`. The confirmation alert state SHALL live in
  `VaultBrowserView`.

**Active item selected (not trash):**
- No toolbar buttons. The header carries the star toggle and `[Edit]`.

**No item selected:**
- No action buttons shown.

#### Scenario: Trashed item — Restore and Delete Permanently visible
- **WHEN** a trashed vault item is selected
- **THEN** [Restore] and [Delete Permanently] buttons are visible in the toolbar

#### Scenario: Active item shows no toolbar actions
- **WHEN** an active (non-trashed) vault item is selected
- **THEN** the detail column's toolbar SHALL contain no buttons
- **AND** the item's header SHALL show the favourite toggle and [Edit]

#### Scenario: Restore executes immediately
- **WHEN** the user clicks [Restore]
- **THEN** the item is restored to the active vault without a confirmation alert

#### Scenario: Permanent delete triggers confirmation
- **WHEN** the user clicks [Delete Permanently]
- **THEN** a confirmation alert is shown before the item is permanently deleted

---

## ADDED Requirements

### Requirement: The item header carries the edit command
The detail pane's item header SHALL offer an `[Edit]` button that opens the edit sheet for the
selected item. It SHALL be disabled while the edit sheet is already open, SHALL carry
`.keyboardShortcut("e", modifiers: .command)` and `AccessibilityID.Edit.editButton`, and its title
SHALL be resolved through `L("Edit")` rather than passed as a string literal.

The button previously lived in the detail column's toolbar, where its title was the literal
`Button("Edit")` — so the Chinese interface showed the English word "Edit" whatever else had been
translated. Moving it is what made that visible.

#### Scenario: Edit opens the sheet
- **WHEN** the user clicks [Edit] in the header
- **THEN** the edit sheet opens for the selected item

#### Scenario: Edit disabled while sheet is open
- **WHEN** the edit sheet is currently open
- **THEN** the [Edit] button is disabled

#### Scenario: Edit button carries ⌘E shortcut
- **WHEN** the user presses ⌘E with an active item selected and the edit sheet closed
- **THEN** the edit sheet opens for the selected item

#### Scenario: Edit is labelled in the interface language
- **GIVEN** the interface language is Simplified Chinese
- **WHEN** the header renders for an active item
- **THEN** the button SHALL read "编辑"

---

### Note on a requirement this delta drops rather than restates
The superseded text required a `[Delete]` button via `ToolbarItem(placement: .destructiveAction)` for
an active item, opening a confirmation alert held by `VaultBrowserView`. **The code has not had that
button for some time** — soft delete is reached from the item row (`ItemListView`'s `onDelete`) and from
the edit sheet. This delta does not restate the bullet, so the stale requirement is retired here rather
than carried forward silently; nothing about the delete path changed in this change.
