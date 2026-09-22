# Item actions in the detail header — Proposal

## Why

The user circled the toolbar in a screenshot and asked whether it looked off. Rendering that toolbar
from the real view tree says why:

`NavigationSplitView` lays its columns' toolbar items out in column order, so with an item selected
the titlebar carries **seven equal-weight outlined shapes** — ⚙, the sidebar toggle, ⇅, ↻, ▾, ☆,
"Edit" — all bunched between the traffic lights and about 60% of the window width, with the right-hand
end empty. Two of the seven are the odd ones out:

- **☆ and "Edit" are commands on the selected item**, sitting in a row of window-level commands, and
  they appear and disappear with the selection — so the toolbar's shape changes as you click around
  the vault, and the empty right half is never filled.
- The favourited state was also shown **twice**: a display-only filled star in the item header, and a
  working star in the toolbar. One of them did nothing when clicked, because it was not a button.

Moving the item's own commands into the item's header fixes both with one rule: **the toolbar holds
commands about the window and the vault; the header holds commands about the thing you are looking
at.** The titlebar drops to five controls, and the detail pane gains a right-hand anchor where its
corner was empty.

## What changes

- `ItemDetailView.itemHeader` gains a trailing cluster: a favourite toggle and an **Edit** button.
  `AccessibilityID.Edit.editButton` and the ⌘E shortcut move with it; the new star carries
  `detail.favorite`.
- `ItemDetailView` gains `onToggleFavorite`, wired in `VaultBrowserView` to the existing
  `viewModel.toggleFavorite(item:)` — the same path the list row and the context menu use.
- `VaultBrowserView`'s detail toolbar keeps only the trashed item's Restore / Delete Permanently.
- `Button("Edit")` becomes `Button(L("Edit"))`. It was an unlocalised literal, so the Chinese
  interface showed **"Edit" in English** — one of the nine `en.lproj` findings' quieter cousins.
- The verification-codes list's countdown becomes the detail pane's shape: a ring plus a monospaced
  seconds number, replacing a thin bar with no number. `CountdownRing` is extracted from
  `TOTPCodeView` so there is one drawing of a countdown, not two.
- **And the countdown had to be made to reach the screen at all.** The row held its
  `TOTPCodeViewModel` as a plain `let`, which subscribes to nothing, so the cell drew once when the
  sheet opened and never again — the seconds froze, and `displayCode` froze with them, leaving an
  expired code on screen looking current. The cell is now its own type with `@ObservedObject`, guarded
  by a render test that advances the clock by hand (tasks §5).

## What this does not change

- **Trash keeps its two commands in the toolbar.** They are also item-level, so the rule is not applied
  uniformly — deliberately. Restore and Delete Permanently are only meaningful together, they are the
  pair a `destructive-action-styling` requirement governs, and the trash pane is a rare destination
  rather than the screen you live on. Design D3 has the reasoning; this is the one place the rule is
  knowingly broken, and it is stated rather than hidden.
- The sidebar, list, search field, and the gear / sort / sync / new-item controls are untouched. The
  remaining question — whether ⚙ belongs in a titlebar at all — is a separate decision (tasks §5).

## Contradicts, deliberately

Three canonical requirements pin these controls to the toolbar, all of them from the archived change
`2026-03-25-no-toolbar-ui`, which moved the app off custom chrome and *into* the native toolbar:

- `detail-column-header`: "The detail column SHALL display contextual action buttons **in the
  toolbar**", naming `ToolbarItem(placement: .primaryAction)` for Edit.
- `toggle-favorite`: "The detail view **toolbar** SHALL display a star toggle button."
- `voiceover-labels`: "VoiceOver focus lands on the star button **in the detail toolbar**".

That change was about removing hand-rolled column headers and a custom search field; where the
commands land afterwards was a second decision it happened to make. This reverses the second one and
keeps the first. Deltas are in `specs/`.

`detail-column-header` also still requires a `[Delete]` button for active items that **the code has not
had for some time** — soft delete lives on the row (`ItemListView`'s `onDelete`). The delta drops that
bullet and says so, rather than letting it vanish silently in an archive step.
