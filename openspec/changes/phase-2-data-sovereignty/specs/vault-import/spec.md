## ADDED Requirements

### Requirement: The vault can be imported from a Bitwarden JSON export

The application SHALL offer a command that reads a Bitwarden **unencrypted** JSON export and creates
the items it contains. The command SHALL be unavailable unless the vault is unlocked.

An input with `encrypted: true`, or without an `items` array, SHALL be refused with an explanation
that Prizm imports unencrypted exports only. Nothing SHALL be created in that case.

#### Scenario: Importing creates the items
- **GIVEN** a file containing 12 items
- **WHEN** the user imports it
- **THEN** 12 new items SHALL be created in the vault
- **AND** the vault SHALL contain 12 more items than before

#### Scenario: All five item types are imported
- **GIVEN** a file containing one item of each type
- **WHEN** the user imports it
- **THEN** the vault SHALL contain one login, one secure note, one card, one identity and one SSH
  key
- **AND** each item's type-specific fields SHALL match the file

#### Scenario: An encrypted export is refused
- **GIVEN** a file whose `encrypted` field is `true`
- **WHEN** the user imports it
- **THEN** no item SHALL be created
- **AND** the user SHALL be told that only unencrypted exports can be imported

#### Scenario: A file that is not an export is refused
- **GIVEN** a file that is not JSON, or is JSON without an `items` array
- **WHEN** the user imports it
- **THEN** no item SHALL be created
- **AND** an error SHALL be reported

---

### Requirement: Import is additive and never overwrites

Importing SHALL NOT delete, modify or merge with any existing item. Importing the same file twice
SHALL produce two copies of each item.

#### Scenario: Existing items are untouched
- **GIVEN** the vault contains 10 items
- **WHEN** a file containing 3 items is imported
- **THEN** the vault SHALL contain 13 items
- **AND** the original 10 SHALL be unchanged

#### Scenario: Importing twice duplicates
- **GIVEN** a file containing 3 items was imported once
- **WHEN** the same file is imported again
- **THEN** the vault SHALL contain 6 items from that file

---

### Requirement: Imported items become personal items, and folders are matched by name

An imported item's `organizationId` and `collectionIds` SHALL be discarded; every imported item
SHALL belong to the personal vault. The report SHALL state this when the file contained
organisation membership.

The item's `folderId` SHALL be resolved by matching the file's folder **name**, case-insensitively,
against the folders already in the vault. A folder with no match SHALL be created.

#### Scenario: Organisation membership is dropped
- **GIVEN** a file contains an item with an `organizationId` and two `collectionIds`
- **WHEN** it is imported
- **THEN** the created item SHALL have no organisation
- **AND** it SHALL appear in the personal vault
- **AND** the report SHALL state that organisation membership was not imported

#### Scenario: An existing folder is reused
- **GIVEN** the vault already has a folder named "Work"
- **AND** the file has a folder named "work" containing an item
- **WHEN** the file is imported
- **THEN** no second folder SHALL be created
- **AND** the item SHALL be placed in the existing "Work" folder

#### Scenario: A missing folder is created
- **GIVEN** the vault has no folder named "Archive"
- **AND** the file has a folder named "Archive" containing an item
- **WHEN** the file is imported
- **THEN** a folder named "Archive" SHALL be created
- **AND** the item SHALL be placed in it

---

### Requirement: Import reports every outcome instead of aborting

Because the server exposes only per-item creation, an import is a sequence of independent requests.
The application SHALL therefore process every item and report how many were imported, how many were
skipped and how many failed, with a reason for each skip and each failure. A failure SHALL NOT stop
the remaining items.

#### Scenario: A partial failure is reported honestly
- **GIVEN** a file contains 12 items and the server rejects 3 of the create requests
- **WHEN** the file is imported
- **THEN** 9 items SHALL be created
- **AND** the report SHALL state that 3 items failed
- **AND** the report SHALL name the reason for at least one failure

#### Scenario: A malformed item is skipped with a reason
- **GIVEN** a file contains an item with an unknown type integer
- **WHEN** the file is imported
- **THEN** that item SHALL be skipped
- **AND** the report SHALL state that its type is not supported
- **AND** the remaining items SHALL still be imported

#### Scenario: The report is not a success message
- **GIVEN** every item in the file fails
- **WHEN** the file is imported
- **THEN** the report SHALL state that 0 items were imported
- **AND** it SHALL NOT indicate success

---

### Requirement: Import progress is visible and the run can be abandoned

While an import is running the application SHALL show how many items have been processed out of the
total. The run SHALL stop before creating the next item when the sheet is dismissed.

#### Scenario: Progress is shown
- **GIVEN** a file contains 40 items
- **WHEN** the import runs
- **THEN** a progress indicator SHALL advance from 0 to 40

#### Scenario: Dismissing stops the run
- **GIVEN** an import of 40 items is in progress
- **WHEN** the user dismisses the sheet
- **THEN** no further items SHALL be created
- **AND** the items already created SHALL remain
