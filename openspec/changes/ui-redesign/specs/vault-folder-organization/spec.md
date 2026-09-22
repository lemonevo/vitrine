## MODIFIED Requirements

### Requirement: Item detail view shows folder assignment

The item detail pane SHALL display the assigned folder's name, read-only, whenever the item has a
`folderId`, and SHALL omit it entirely when `folderId` is nil. The name SHALL be resolved from the
in-memory folder list by `folderId`, never shown raw.

The folder name is shown in the detail pane's header breadcrumb, beside the item's name — not in a
field row after the last content section. A breadcrumb is where placement is read from; a row at the
bottom of a scrolling card stack is where it is missed.

#### Scenario: Detail view shows folder name for assigned item
- **GIVEN** an item is assigned to folder "Work"
- **WHEN** the user views the item in the detail pane
- **THEN** the header breadcrumb SHALL include "Work"

#### Scenario: Detail view omits folder for unfoldered item
- **GIVEN** an item has no folder assigned (`folderId` is nil)
- **WHEN** the user views the item in the detail pane
- **THEN** the breadcrumb SHALL NOT include a folder name
- **AND** when nothing else places the item either, the breadcrumb SHALL read "Personal vault"

#### Scenario: Folder name resolves from in-memory list
- **GIVEN** an item has `folderId` matching folder "Finance"
- **WHEN** the detail pane renders
- **THEN** the breadcrumb SHALL display "Finance" (resolved name, not the raw ID)
