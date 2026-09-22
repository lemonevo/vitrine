## ADDED Requirements

### Requirement: The app SHALL list the vault's verification codes together

The app SHALL provide a screen listing every login in the vault that carries a TOTP secret, each with
its current code and the time remaining.

#### Scenario: A login with a code appears

- **GIVEN** a login with a TOTP secret
- **WHEN** the list is opened
- **THEN** it SHALL show that item with its current code

#### Scenario: Items without a code do not appear

- **GIVEN** a login with no TOTP secret, and items of other types
- **WHEN** the list is opened
- **THEN** none of them SHALL appear

#### Scenario: Trashed items do not appear

- **GIVEN** a login with a TOTP secret that is in Trash
- **WHEN** the list is opened
- **THEN** it SHALL NOT appear

#### Scenario: An unusable secret is reported

- **GIVEN** a login whose stored secret cannot produce a code
- **WHEN** the list is opened
- **THEN** its row SHALL say so rather than showing an empty code

### Requirement: A re-prompt-protected code SHALL remain protected in the list

An item whose secrets require the master password SHALL NOT have its code shown in the list until the
gate is satisfied, and copying it SHALL go through the same gate.

#### Scenario: The code is withheld

- **GIVEN** an item with re-prompt protection and a TOTP secret
- **AND** the gate has not been satisfied this session
- **WHEN** the list is opened
- **THEN** its code SHALL NOT be shown

#### Scenario: Revealing asks for the password

- **GIVEN** the same item
- **WHEN** its row is revealed
- **THEN** the master password SHALL be required, as it is in the item's detail view

#### Scenario: Copying cannot walk around the gate

- **GIVEN** a gated row whose code is not revealed
- **WHEN** its copy control is used
- **THEN** the master password SHALL be required before anything reaches the clipboard

### Requirement: The stored secret SHALL NOT be exposed by the list

The list SHALL show and copy only derived codes. A stored TOTP secret SHALL NOT be displayed or placed
on the clipboard by any control on this screen.

#### Scenario: Copying yields a code

- **GIVEN** a row showing a derived code
- **WHEN** it is copied
- **THEN** the value on the clipboard SHALL be the code
- **AND** it SHALL NOT be the stored secret

### Requirement: Codes SHALL stay current while the list is open

Each row SHALL refresh from its own stored secret, honouring that item's own period.

#### Scenario: A code expires

- **GIVEN** the list is open
- **WHEN** a code's step elapses
- **THEN** that row SHALL show the new code

#### Scenario: Rows do not interfere

- **GIVEN** two items whose codes have different periods
- **WHEN** the shorter one expires
- **THEN** the longer one SHALL be unaffected
