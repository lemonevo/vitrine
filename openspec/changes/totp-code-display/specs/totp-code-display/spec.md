# TOTP code display

Show the current one-time code for a login item in the detail view, with the time it remains valid.

The code is a live credential. Everything below about masking, the gate and the seed follows from
that: the row exists to let the user *read* a code, and it must not become a second way to obtain one
that skips the controls the copy command already has.

## ADDED Requirements

### Requirement: The login detail view SHALL show the current one-time code

For a login item whose stored value produces a code, the Credentials card SHALL contain a row showing
that code, and the row SHALL show the number of seconds the code remains valid.

The code SHALL be recomputed from the stored value at least once per second while the row is on
screen, so that it changes when the time step changes. The stored value itself SHALL NOT be displayed
or copied by the row.

#### Scenario: The code is shown

- **GIVEN** a login item whose stored value is a usable authenticator key
- **WHEN** the item's detail view is displayed and the code is revealed
- **THEN** the current code SHALL be shown
- **AND** the seconds it remains valid SHALL be shown

#### Scenario: The code follows the time step

- **GIVEN** the code is displayed
- **WHEN** the time step rolls over
- **THEN** the code shown SHALL be the code for the new step
- **AND** it SHALL differ from the code for the previous step

#### Scenario: The remaining time never reads zero while the code is valid

- **GIVEN** the code is displayed
- **WHEN** the remaining time is computed at any instant within the step
- **THEN** it SHALL be at least one second
- **AND** it SHALL NOT exceed the length of the step

#### Scenario: An item without an authenticator key shows no code row

- **GIVEN** a login item with no stored authenticator key
- **WHEN** the detail view is displayed
- **THEN** no code row SHALL be shown

#### Scenario: An item with only an authenticator key still shows its credentials card

- **GIVEN** a login item with a stored authenticator key and neither a username nor a password
- **WHEN** the detail view is displayed
- **THEN** the Credentials card SHALL be shown

#### Scenario: The stored value is never shown

- **GIVEN** the code row is displayed, revealed
- **WHEN** the row renders
- **THEN** the stored value SHALL NOT appear anywhere in the row

---

### Requirement: The code SHALL be masked until revealed

The row SHALL show a placeholder rather than the code until the user asks for it, and SHALL NOT show
the remaining time while masked.

#### Scenario: Masked by default

- **GIVEN** the detail view has just been opened for an item with an authenticator key
- **WHEN** the row renders
- **THEN** the code SHALL NOT be shown
- **AND** the remaining time SHALL NOT be shown

#### Scenario: Revealing shows the code and the time together

- **GIVEN** the row is masked
- **WHEN** the user reveals the code
- **THEN** the code SHALL be shown
- **AND** the remaining time SHALL be shown

---

### Requirement: A re-prompt-protected item's code SHALL require the master password to read

When the item carries re-prompt protection, revealing the code SHALL go through the master-password
gate, and the code SHALL be shown only while the gate's grant is in effect.

#### Scenario: Revealing a protected item's code asks for the password

- **GIVEN** the item carries re-prompt protection and no grant has been given this session
- **WHEN** the user asks to reveal the code
- **THEN** the master password SHALL be requested
- **AND** the code SHALL NOT be shown until it is answered correctly

#### Scenario: A declined prompt leaves the code masked

- **GIVEN** the master-password request is on screen
- **WHEN** the user declines it
- **THEN** the code SHALL remain masked

#### Scenario: A grant covers the code and the password

- **GIVEN** a grant for the item has been given this session
- **WHEN** the row renders
- **THEN** the code SHALL be shown without a further request

#### Scenario: An unprotected item reveals without a prompt

- **GIVEN** the item does not carry re-prompt protection
- **WHEN** the user reveals the code
- **THEN** the code SHALL be shown
- **AND** no password SHALL be requested

---

### Requirement: Copying the code SHALL use the same gate as the copy-code command

The row's copy action SHALL put the **code** on the clipboard and SHALL NOT put the stored value
there. For a re-prompt-protected item it SHALL go through the master-password gate, so that the row
is not a way around the gate the menu command already applies.

#### Scenario: Copying on a protected item asks for the password

- **GIVEN** the item carries re-prompt protection and no grant has been given this session
- **WHEN** the user copies the code from the row
- **THEN** the master password SHALL be requested
- **AND** nothing SHALL be placed on the clipboard until it is answered correctly

#### Scenario: The clipboard receives the code

- **GIVEN** the row shows a code
- **WHEN** the user copies it
- **THEN** the clipboard SHALL contain that code
- **AND** the clipboard SHALL NOT contain the stored value

#### Scenario: The copied value is not grouped

- **GIVEN** the code is displayed with its digits grouped for reading
- **WHEN** the user copies it
- **THEN** the clipboard SHALL contain the bare digits

---

### Requirement: A stored value that produces no code SHALL be reported

When the item has a stored authenticator key that cannot produce a code, the row SHALL say so rather
than being omitted.

#### Scenario: An unusable stored value

- **GIVEN** a login item with a stored authenticator key that cannot produce a code
- **WHEN** the detail view is displayed
- **THEN** the row SHALL be shown
- **AND** it SHALL state that the code cannot be generated
- **AND** it SHALL NOT show a code, a countdown, or an empty value

---

### Requirement: The code SHALL NOT be derived while the row is off screen

The derivation SHALL run only while the row is displayed, and SHALL stop when the item is deselected
or the detail view is dismissed.

#### Scenario: Leaving the item stops the derivation

- **GIVEN** the code row is displayed and its derivation is running
- **WHEN** the item is deselected
- **THEN** the derivation SHALL stop
