## ADDED Requirements

### Requirement: Previous passwords are displayed for an item

For a login item whose server-maintained password history is non-empty, the detail view SHALL offer
a password-history section listing each previous password with the date it was replaced, most recent
first. The section SHALL be collapsed by default and each password SHALL be masked until revealed.

#### Scenario: The section appears only when there is history
- **GIVEN** a login item with no password history
- **WHEN** its detail view renders
- **THEN** no password-history section SHALL be shown

#### Scenario: History entries are listed newest first
- **GIVEN** a login item with three history entries
- **WHEN** the section is expanded
- **THEN** three entries SHALL be listed
- **AND** the most recently replaced SHALL be first

#### Scenario: Passwords are masked until revealed
- **GIVEN** the section is expanded
- **WHEN** an entry is displayed
- **THEN** its password SHALL be masked
- **AND** revealing it SHALL require the re-prompt gate to be satisfied

#### Scenario: A history entry can be copied
- **GIVEN** an entry is revealed
- **WHEN** the user copies it
- **THEN** the value SHALL be on the clipboard
- **AND** the clipboard SHALL be cleared after the configured interval

#### Scenario: A malformed entry does not hide the rest
- **GIVEN** one of three history entries cannot be decrypted
- **WHEN** the section is expanded
- **THEN** the other two SHALL be listed
- **AND** the undecryptable entry SHALL be omitted

---

### Requirement: History is decrypted on demand and never cached

History values SHALL be decrypted only when the section is requested, using the item's own key
resolution, and the plaintext SHALL NOT be retained after the section is closed.

#### Scenario: Nothing is decrypted until requested
- **GIVEN** a login item with password history is selected
- **WHEN** the history section has not been opened
- **THEN** no history value SHALL have been decrypted

#### Scenario: Closing the section drops the plaintext
- **GIVEN** the history section is open
- **WHEN** it is closed
- **THEN** the decrypted values SHALL be discarded
