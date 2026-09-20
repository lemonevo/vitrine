## ADDED Requirements

### Requirement: Trash can be emptied in a single action

The Trash view SHALL offer an action that permanently deletes every item currently in Trash. The
action SHALL require confirmation that names the number of items about to be deleted, because
permanent deletion cannot be undone.

The action SHALL NOT be offered when Trash is empty.

Because the server exposes only per-item permanent deletion, emptying Trash is a sequence of
independent requests. The action SHALL therefore report how many items were deleted and how many
failed, rather than aborting on the first failure — a partial outcome is the honest result and
leaving the user unable to tell how much was removed would be worse.

After the action the item list and sidebar counts SHALL reflect what is actually left, and the
detail pane SHALL be cleared if the selected item was deleted.

#### Scenario: Emptying Trash deletes every trashed item
- **GIVEN** Trash contains 12 items
- **WHEN** the user confirms emptying Trash
- **THEN** all 12 items SHALL be permanently deleted from the server
- **AND** Trash SHALL be empty
- **AND** the sidebar count for Trash SHALL be zero

#### Scenario: Confirmation names the count
- **GIVEN** Trash contains 12 items
- **WHEN** the user invokes the empty-Trash action
- **THEN** a confirmation SHALL be shown stating that 12 items will be permanently deleted
- **AND** cancelling SHALL delete nothing

#### Scenario: Partial failure is reported
- **GIVEN** Trash contains 12 items and the server rejects 3 of the delete requests
- **WHEN** the user confirms emptying Trash
- **THEN** 9 items SHALL be deleted
- **AND** an error SHALL report that 3 items could not be deleted
- **AND** the 3 remaining items SHALL still be listed in Trash

#### Scenario: Action unavailable when Trash is empty
- **GIVEN** Trash contains no items
- **WHEN** the Trash view renders
- **THEN** no empty-Trash action SHALL be offered

#### Scenario: Selected item is deselected when deleted
- **GIVEN** a trashed item is selected in the detail pane
- **WHEN** Trash is emptied
- **THEN** the detail pane SHALL return to its empty state

#### Scenario: Non-trashed items are never touched
- **GIVEN** the vault contains active items and trashed items
- **WHEN** the user empties Trash
- **THEN** only the trashed items SHALL be deleted
- **AND** every active item SHALL remain
