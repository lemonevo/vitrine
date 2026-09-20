## ADDED Requirements

### Requirement: An item can be marked for master-password re-prompt

The item edit form SHALL offer a **Master password re-prompt** toggle. When enabled, the setting
SHALL be sent to the server and SHALL survive a subsequent sync.

#### Scenario: The toggle is available for every item type
- **GIVEN** the edit form is open for any item type
- **WHEN** the form renders
- **THEN** a master-password re-prompt toggle SHALL be visible

#### Scenario: The setting persists
- **GIVEN** the toggle is enabled and the item is saved
- **WHEN** the vault is synced
- **THEN** the item's re-prompt setting SHALL still be enabled

#### Scenario: The setting survives an unrelated edit
- **GIVEN** an item has re-prompt enabled
- **WHEN** its name is changed and saved
- **THEN** the re-prompt setting SHALL still be enabled

---

### Requirement: Protected secrets require the master password

When an item has re-prompt enabled, revealing or copying a secret belonging to it SHALL require the
master password to be entered first. The following SHALL be gated:

- revealing the item's password
- copying the item's password
- copying the item's one-time code
- revealing a hidden custom field
- revealing a password-history entry

The item's name, username, URIs, notes and non-hidden fields SHALL NOT be gated.

#### Scenario: Revealing the password asks first
- **GIVEN** an item has re-prompt enabled and the master password has not been entered this session
- **WHEN** the user reveals the password
- **THEN** a master-password prompt SHALL be shown
- **AND** the password SHALL NOT be displayed until it is answered correctly

#### Scenario: Copying the password asks first
- **GIVEN** an item has re-prompt enabled and the master password has not been entered this session
- **WHEN** the user invokes Copy Password
- **THEN** a master-password prompt SHALL be shown
- **AND** nothing SHALL be placed on the clipboard until it is answered correctly

#### Scenario: Copying the one-time code asks first
- **GIVEN** an item has re-prompt enabled and a TOTP seed
- **WHEN** the user invokes Copy Code
- **THEN** a master-password prompt SHALL be shown

#### Scenario: An unprotected item never asks
- **GIVEN** an item does not have re-prompt enabled
- **WHEN** the user reveals or copies its password
- **THEN** no prompt SHALL be shown

#### Scenario: The username is not gated
- **GIVEN** an item has re-prompt enabled
- **WHEN** the user invokes Copy Username
- **THEN** no prompt SHALL be shown

#### Scenario: A wrong password does not grant access
- **GIVEN** the prompt is displayed
- **WHEN** the user enters an incorrect master password
- **THEN** the secret SHALL remain hidden
- **AND** an error SHALL be shown
- **AND** the prompt SHALL remain open

#### Scenario: Cancelling grants nothing
- **GIVEN** the prompt is displayed
- **WHEN** the user cancels
- **THEN** the secret SHALL remain hidden
- **AND** nothing SHALL be placed on the clipboard

---

### Requirement: A successful prompt covers the item for the rest of the unlock session

After the master password is entered correctly for an item, that item's secrets SHALL remain
accessible without a further prompt until the vault is locked or the user signs out. The grant
SHALL be per item.

#### Scenario: The grant covers the rest of the session
- **GIVEN** the user has entered the master password for an item
- **WHEN** they reveal the password, copy it, and copy the one-time code in turn
- **THEN** no further prompt SHALL be shown

#### Scenario: The grant is per item
- **GIVEN** the user has entered the master password for item A
- **WHEN** they reveal a secret of item B, which also has re-prompt enabled
- **THEN** a prompt SHALL be shown

#### Scenario: Locking clears the grants
- **GIVEN** the user has entered the master password for an item
- **WHEN** the vault is locked and unlocked again
- **THEN** revealing that item's password SHALL prompt again

#### Scenario: Signing out clears the grants
- **GIVEN** the user has entered the master password for an item
- **WHEN** the user signs out
- **THEN** the grant SHALL be discarded

---

### Requirement: Verification is local and does not disturb the session

The master password SHALL be verified by re-deriving the key from the stored parameters on the
device. No network request SHALL be made, and a verification SHALL NOT change the session, the
account, the vault contents or any cached key material.

#### Scenario: No network request is made
- **GIVEN** the prompt is displayed
- **WHEN** the user submits a password
- **THEN** no network request SHALL be made

#### Scenario: The session is unaffected
- **GIVEN** the vault is unlocked and the prompt is answered correctly
- **WHEN** verification completes
- **THEN** the vault SHALL remain unlocked
- **AND** the selected item SHALL remain selected
- **AND** no sync SHALL be triggered
