## ADDED Requirements

### Requirement: A remembered device SHALL be remembered

When the user asks to be remembered during a two-factor login, and the server returns a token for that
purpose, the app SHALL store the token and replay it on a later login for the same account so that the
challenge is not repeated.

The app SHALL NOT store a token when the user did not ask to be remembered.

#### Scenario: The token is stored when asked for

- **GIVEN** a two-factor login in progress
- **WHEN** the code is accepted with "remember this device" selected
- **THEN** the returned token SHALL be stored, with the account's email

#### Scenario: Nothing is stored when not asked for

- **GIVEN** a two-factor login in progress
- **WHEN** the code is accepted without "remember this device" selected
- **THEN** no token SHALL be stored

#### Scenario: The stored token is replayed

- **GIVEN** a remembered device for an account
- **WHEN** that account signs in again
- **THEN** the stored token SHALL be sent with the login request

#### Scenario: The token belongs to one account

- **GIVEN** a remembered device for one account
- **WHEN** a different account signs in
- **THEN** the stored token SHALL NOT be sent
- **AND** it SHALL remain available for its own account

#### Scenario: A rejected token is not an error

- **GIVEN** a remembered device whose token the server no longer accepts
- **WHEN** the account signs in
- **THEN** the two-factor challenge SHALL be presented as it would be without the token

### Requirement: A remembered device SHALL NOT outlive its session

Signing out SHALL remove the remembered device. Locking the vault SHALL NOT, because locking keeps the
session rather than ending it.

#### Scenario: Sign-out forgets the device

- **GIVEN** a remembered device
- **WHEN** the user signs out
- **THEN** the token and the email it was stored with SHALL both be removed

#### Scenario: Locking does not

- **GIVEN** a remembered device
- **WHEN** the vault is locked
- **THEN** the token SHALL remain stored
