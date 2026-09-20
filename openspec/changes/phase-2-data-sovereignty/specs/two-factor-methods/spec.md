## ADDED Requirements

### Requirement: Three two-factor methods can be completed

The application SHALL complete an authenticator-app (TOTP) challenge, an email challenge and a
YubiKey OTP challenge. The prompt SHALL state which method the server is asking for.

The provider number sent with the code SHALL be the provider the code belongs to, not a fixed
value.

#### Scenario: An authenticator-app challenge is completed
- **GIVEN** the server offers only the authenticator-app provider
- **WHEN** the user enters the current 6-digit code
- **THEN** the code SHALL be submitted with that provider's number
- **AND** the login SHALL succeed

#### Scenario: An email challenge is completed
- **GIVEN** the server offers only the email provider
- **WHEN** the prompt renders
- **THEN** it SHALL state that a code was emailed
- **AND** a resend action SHALL be offered
- **AND** the submitted provider number SHALL be the email provider's

#### Scenario: A YubiKey challenge is completed
- **GIVEN** the server offers only the YubiKey OTP provider
- **WHEN** the prompt renders
- **THEN** it SHALL instruct the user to tap the key
- **AND** the submitted provider number SHALL be the YubiKey provider's

#### Scenario: Resending is offered only for email
- **GIVEN** the server offers the authenticator-app provider
- **WHEN** the prompt renders
- **THEN** no resend action SHALL be offered

#### Scenario: The code is rejected
- **GIVEN** the user submits a code the server rejects
- **WHEN** the server responds
- **THEN** an error SHALL be shown
- **AND** the prompt SHALL remain open
- **AND** the derived key material SHALL NOT be discarded, so the user can retry

---

### Requirement: The offered method is chosen in a fixed preference order

When the server offers more than one supported method, the application SHALL choose in this order:
authenticator app, then YubiKey OTP, then email. The chosen method SHALL be the one the prompt asks
for.

#### Scenario: The authenticator app wins
- **GIVEN** the server offers the authenticator-app, YubiKey and email providers
- **WHEN** the challenge is presented
- **THEN** the prompt SHALL ask for an authenticator-app code

#### Scenario: YubiKey beats email
- **GIVEN** the server offers the YubiKey and email providers
- **WHEN** the challenge is presented
- **THEN** the prompt SHALL ask for a YubiKey tap

---

### Requirement: Unsupported methods are named

When the server offers only methods the application cannot complete, the error SHALL name the method
the server asked for, rather than reporting a generic unsupported method.

#### Scenario: Duo is named
- **GIVEN** the server offers only the Duo provider
- **WHEN** the user attempts to log in
- **THEN** the error SHALL name Duo
- **AND** it SHALL state that Prizm cannot complete that method

#### Scenario: WebAuthn is named
- **GIVEN** the server offers only the WebAuthn provider
- **WHEN** the user attempts to log in
- **THEN** the error SHALL name WebAuthn

#### Scenario: An unknown provider number is reported honestly
- **GIVEN** the server offers a provider number the application does not recognise
- **WHEN** the user attempts to log in
- **THEN** the error SHALL report the unrecognised number
- **AND** it SHALL NOT claim to know which method it is

---

### Requirement: Cancelling a challenge discards the pending key material

Dismissing the prompt without submitting a code SHALL discard the stretched keys and password hash
held from the password step.

#### Scenario: Cancelling clears the pending state
- **GIVEN** the prompt is displayed after a password step
- **WHEN** the user cancels
- **THEN** the pending key material SHALL be discarded
- **AND** the application SHALL return to the login screen
