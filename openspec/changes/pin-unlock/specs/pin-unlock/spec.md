## ADDED Requirements

### Requirement: A PIN SHALL provide an alternative unlock

When a PIN has been set, the app SHALL allow the vault to be unlocked with it, producing the same
session the master password would. The master password SHALL remain available and SHALL NOT be stored.

#### Scenario: Setting a PIN

- **GIVEN** an unlocked vault
- **WHEN** a PIN of at least four characters is set
- **THEN** the vault's key material SHALL be stored in a form that requires the PIN to read
- **AND** the PIN itself SHALL NOT be stored

#### Scenario: Unlocking with it

- **GIVEN** a PIN has been set and the vault is locked
- **WHEN** the correct PIN is entered
- **THEN** the vault SHALL unlock

#### Scenario: A wrong PIN

- **GIVEN** a PIN has been set
- **WHEN** an incorrect PIN is entered
- **THEN** the vault SHALL NOT unlock
- **AND** the stored material SHALL remain usable with the correct PIN

#### Scenario: A too-short PIN is refused

- **GIVEN** the set-PIN flow
- **WHEN** a PIN shorter than four characters is entered
- **THEN** it SHALL be refused

### Requirement: Attempts SHALL be limited durably

At most five consecutive incorrect PINs SHALL be accepted. The count SHALL survive the app being
restarted, and the fifth failure SHALL remove the stored material and sign the user out.

#### Scenario: The count persists

- **GIVEN** four incorrect attempts
- **WHEN** the app is restarted
- **THEN** the count SHALL still be four

#### Scenario: The fifth failure removes the PIN

- **GIVEN** four incorrect attempts
- **WHEN** a fifth incorrect PIN is entered
- **THEN** the stored key material SHALL be deleted
- **AND** the user SHALL be signed out
- **AND** the master password SHALL still work

#### Scenario: A success resets the count

- **GIVEN** some incorrect attempts
- **WHEN** the correct PIN is entered
- **THEN** the count SHALL return to zero

### Requirement: A PIN SHALL not unlock a restarted app by default

A setting SHALL control whether the master password is required after the app restarts, and it SHALL
default to requiring it. Locking the vault SHALL NOT be affected by it.

#### Scenario: Cold start requires the master password

- **GIVEN** a PIN is set and the restart setting is at its default
- **WHEN** the app is launched
- **THEN** the PIN SHALL NOT be offered until the master password has been accepted

#### Scenario: A lock is not a restart

- **GIVEN** a PIN is set and the master password has been accepted in this launch
- **WHEN** the vault is locked and then unlocked
- **THEN** the PIN SHALL be offered

### Requirement: A PIN SHALL not outlive the session it was set in when that session is discarded

Signing out SHALL remove the PIN material. Locking SHALL NOT.

#### Scenario: Sign-out removes the PIN

- **GIVEN** a PIN has been set
- **WHEN** the user signs out
- **THEN** the stored key material, salt and attempt count SHALL be removed

#### Scenario: Locking keeps it

- **GIVEN** a PIN has been set
- **WHEN** the vault is locked
- **THEN** the PIN SHALL still unlock it
