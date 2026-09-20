## ADDED Requirements

### Requirement: The vault can be exported to a portable file

The application SHALL offer a command that writes the vault to a single file in Bitwarden's
unencrypted JSON export format: `encrypted: false`, a `folders` array of `{ id, name }` and an
`items` array whose type integers follow the server's `CipherType` enum (1 login, 2 secure note,
3 card, 4 identity, 5 SSH key).

The file SHALL be readable by any Bitwarden-compatible client. The export SHALL therefore contain
every field the format can express: id, name, notes, favourite, re-prompt, folder, collection
membership, custom fields, password history, and all type-specific fields including the TOTP seed
and the login URIs.

The command SHALL be unavailable unless the vault is unlocked.

#### Scenario: Exporting writes the whole vault
- **GIVEN** the vault is unlocked and contains 86 items across 3 folders
- **WHEN** the user confirms an export
- **THEN** a file SHALL be written containing 86 items and 3 folders
- **AND** the file SHALL contain `"encrypted": false`
- **AND** the item count in the file SHALL equal the item count in the vault

#### Scenario: Every item type survives the round trip
- **GIVEN** the vault contains a login, a secure note, a card, an identity and an SSH key
- **WHEN** the vault is exported
- **THEN** the file SHALL contain five items with type integers 1, 2, 3, 4 and 5 respectively
- **AND** each item's type-specific fields SHALL be present in its type's sub-object

#### Scenario: Custom fields and notes are exported
- **GIVEN** an item has two custom fields and a note
- **WHEN** the vault is exported
- **THEN** both custom fields SHALL appear in the item's `fields` array with their names, values,
  types and linked ids
- **AND** the note SHALL appear as the item's `notes`

#### Scenario: The TOTP seed is exported
- **GIVEN** a login item has a TOTP seed
- **WHEN** the vault is exported
- **THEN** the seed SHALL appear in the item's `login.totp`

#### Scenario: Password history is exported
- **GIVEN** a login item has two previous passwords recorded by the server
- **WHEN** the vault is exported
- **THEN** the item's `passwordHistory` array SHALL contain two entries
- **AND** each entry SHALL carry its password and its last-used date

#### Scenario: Folders are written with their ids so items can reference them
- **GIVEN** an item is in a folder
- **WHEN** the vault is exported
- **THEN** the folder SHALL appear in `folders` with its id and name
- **AND** the item's `folderId` SHALL equal that id

#### Scenario: Organisation items are included
- **GIVEN** the vault contains 5 personal items and 3 items belonging to an organisation
- **WHEN** the vault is exported
- **THEN** all 8 items SHALL be written
- **AND** the 3 organisation items SHALL carry their `organizationId` and `collectionIds`

#### Scenario: Trashed items are not exported
- **GIVEN** the vault contains active items and 2 items in Trash
- **WHEN** the vault is exported
- **THEN** the file SHALL contain only the active items

#### Scenario: Export is unavailable while locked
- **GIVEN** the vault is locked
- **WHEN** the export command is inspected
- **THEN** it SHALL be disabled

#### Scenario: An empty vault is refused
- **GIVEN** the vault is unlocked and contains no items
- **WHEN** the user requests an export
- **THEN** no file SHALL be written
- **AND** the user SHALL be told there is nothing to export

---

### Requirement: Export requires explicit consent naming the risk

Before anything is written, the application SHALL display a confirmation stating that the file will
contain every password in the vault in plain text, that anyone who can read the file can read the
vault, and that the file is not encrypted. The export SHALL proceed only on explicit confirmation.
Cancelling SHALL write nothing.

#### Scenario: Consent is shown before the file is chosen
- **GIVEN** the vault is unlocked
- **WHEN** the user invokes the export command
- **THEN** the consent SHALL be displayed before any save panel appears
- **AND** no file SHALL exist until the consent is confirmed

#### Scenario: Cancelling writes nothing
- **GIVEN** the consent is displayed
- **WHEN** the user cancels
- **THEN** no file SHALL be written
- **AND** no save panel SHALL be shown

#### Scenario: The consent names what is not included
- **GIVEN** the consent is displayed
- **WHEN** the user reads it
- **THEN** it SHALL state that attachments and passkeys are not included
- **AND** it SHALL state that items in Trash are not included

---

### Requirement: The exported file is created with owner-only permissions

The exported file SHALL be written with POSIX permissions `0600`. No vault value SHALL appear in
any log.

#### Scenario: The file is not world-readable
- **GIVEN** an export completed
- **WHEN** the file's permissions are inspected
- **THEN** the mode SHALL be `0600`

#### Scenario: Values are not logged
- **GIVEN** debug logging is enabled
- **WHEN** an export runs
- **THEN** the log SHALL record the item count and the destination path
- **AND** the log SHALL NOT contain any item's name, password, note or custom field value

---

### Requirement: The export names its destination and warns about the file

After a successful export the application SHALL report the path the file was written to and state
that the file is unencrypted and should be deleted when it is no longer needed.

#### Scenario: The destination is reported
- **GIVEN** an export completed to `/Users/x/Desktop/prizm_export_20260920.json`
- **WHEN** the completion is displayed
- **THEN** that path SHALL be shown
- **AND** a reminder to delete the file SHALL be shown
