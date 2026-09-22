## ADDED Requirements

### Requirement: The unlock screen SHALL ask for one credential at a time

The lock screen SHALL present a single credential field, and every element that describes which
credential is being asked for — the heading sentence, the field label, the attempt count, and whatever
the submit action sends — SHALL derive from that one value. Where more than one credential exists for
the account, the one not being asked for SHALL be offered as a control that is visible whenever it
exists.

#### Scenario: A PIN exists but the screen asks for the password

- **GIVEN** an account with a PIN set and available on this launch
- **WHEN** the lock screen is shown and it is asking for the master password
- **THEN** only the master-password field SHALL be present
- **AND** a control labelled "Use PIN instead" SHALL be visible
- **AND** no PIN attempt count SHALL be shown

#### Scenario: The attempt count follows the credential it counts

- **GIVEN** a PIN has already been guessed wrong once on this launch
- **WHEN** the lock screen is asking for the master password
- **THEN** the remaining-attempts line SHALL NOT be shown
- **AND** when the same screen is asking for the PIN
- **THEN** that line SHALL be shown, directly under the PIN field

#### Scenario: An empty submission is answered rather than prevented

- **GIVEN** the credential field is empty
- **WHEN** the user activates the unlock action
- **THEN** the button SHALL have been live, not greyed out
- **AND** the screen SHALL state which credential is missing
- **AND** no key derivation or PIN verification SHALL have been attempted

#### Scenario: Switching credentials carries nothing across

- **GIVEN** the user has typed into the field the screen was showing
- **WHEN** they switch to the other credential
- **THEN** the newly shown field SHALL be empty
- **AND** the text typed for the other credential SHALL NOT be submitted through it

### Requirement: The default credential SHALL be earned within the launch and never persisted

The lock screen SHALL default to the master password. It SHALL default to the PIN only after a PIN has
successfully unlocked the vault during the same process, and that fact SHALL be held in memory only.

#### Scenario: A PIN that exists is not a default

- **GIVEN** an account with a PIN set, and no successful PIN unlock since the app started
- **WHEN** the vault locks
- **THEN** the screen SHALL ask for the master password

#### Scenario: A PIN that worked becomes the next default

- **GIVEN** a PIN unlocked the vault during this launch
- **WHEN** the vault locks again
- **THEN** the screen SHALL ask for the PIN

#### Scenario: A failed PIN earns nothing

- **GIVEN** a PIN was rejected on this launch
- **WHEN** the lock screen is shown again
- **THEN** the screen SHALL still ask for the master password

#### Scenario: A PIN that has stopped existing cannot stay the default

- **GIVEN** the PIN became unavailable — its attempts were exhausted, or it was removed
- **WHEN** the lock screen is built
- **THEN** the screen SHALL ask for the master password, whatever was used last

#### Scenario: Nothing about the choice reaches storage

- **WHEN** a PIN unlock succeeds
- **THEN** no preference, default, or Keychain item SHALL record that this account unlocks with a PIN
- **AND** after a restart the screen SHALL ask for the master password
