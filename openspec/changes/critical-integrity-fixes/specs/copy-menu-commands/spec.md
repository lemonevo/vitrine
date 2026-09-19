## MODIFIED Requirements

### Requirement: Copy field commands in Item menu
The Item menu SHALL provide Copy Username (⇧⌘C), Copy Password (⌥⌘C), Copy Code (⌃⌘C), and Copy Website (⌥⇧⌘C) commands. Each command SHALL copy the corresponding field from the selected Login item to the clipboard with 30-second auto-clear. Commands SHALL be disabled when the selected item does not have the corresponding field or is not a Login item.

**Copy Code SHALL copy the current one-time password derived from the item's stored TOTP secret, never the secret itself.** The command SHALL be disabled when no code can be derived from the stored value. No menu command SHALL place the stored TOTP secret on the clipboard.

#### Scenario: Copy Username copies username to clipboard
- **GIVEN** a Login item with a username is selected
- **WHEN** the user presses ⇧⌘C or selects Copy Username from the Item menu
- **THEN** the username SHALL be copied to the clipboard with 30s auto-clear

#### Scenario: Copy Password copies password to clipboard
- **GIVEN** a Login item with a password is selected
- **WHEN** the user presses ⌥⌘C
- **THEN** the password SHALL be copied to the clipboard with 30s auto-clear

#### Scenario: Copy Code copies the generated one-time code
- **GIVEN** a Login item with a valid TOTP secret is selected
- **WHEN** the user presses ⌃⌘C
- **THEN** the current one-time code SHALL be copied to the clipboard with 30s auto-clear
- **AND** the clipboard SHALL NOT contain the stored secret

#### Scenario: Copy Code is disabled when no code can be derived
- **GIVEN** a Login item whose TOTP value is absent or malformed is selected
- **WHEN** the Item menu is opened
- **THEN** the Copy Code command SHALL be disabled

#### Scenario: Copy Website copies first URI to clipboard
- **GIVEN** a Login item with at least one URI is selected
- **WHEN** the user presses ⌥⇧⌘C
- **THEN** the first URI SHALL be copied to the clipboard with 30s auto-clear

#### Scenario: Commands disabled when field unavailable
- **GIVEN** the selected item is not a Login or the Login item lacks the field
- **THEN** the corresponding copy command SHALL be disabled (grayed out)

#### Scenario: Commands disabled when no item selected
- **GIVEN** no item is selected in the item list
- **THEN** all four copy commands SHALL be disabled
