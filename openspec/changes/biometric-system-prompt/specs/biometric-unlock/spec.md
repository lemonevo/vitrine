## MODIFIED Requirements

### Requirement: User can unlock the vault with biometrics
The system SHALL provide a biometric unlock path that re-opens the vault without requiring the master
password, using the platform biometric authenticator (Touch ID on macOS, Face ID on iOS). The system
SHALL store the derived vault symmetric key (`CryptoKeys`) in a Keychain item protected by
`kSecAccessControl` with `.biometryCurrentSet`. The master password path SHALL always remain
available as a fallback.

The prompt SHALL be the system's own — raised by `LAContext.evaluatePolicy` and drawn by the security
agent over whichever app the user was in. The authentication view an app can embed
(`LAAuthenticationView`) suppresses that dialog by pairing with the context, so presenting the system
prompt requires not pairing. The unlock screen's own contribution is therefore an affordance that
*asks*, labelled with the sensor the device reports.

The system SHALL NOT re-trigger evaluation after the user dismisses a prompt. Each dismissal that
raised a replacement would be a loop the user could only leave by authenticating.

#### Scenario: Successful Touch ID unlock
- **GIVEN** biometric unlock is enabled and the vault is locked
- **WHEN** the lock screen appears
- **THEN** the system SHALL automatically raise the biometric prompt once
- **AND** on successful biometric evaluation the vault SHALL unlock and the vault browser SHALL be shown without the user entering a password

#### Scenario: The unlock screen offers a button that names the sensor
- **GIVEN** biometric unlock is enabled and the vault is locked
- **WHEN** the lock screen is shown
- **THEN** a control labelled "Unlock with Touch ID" (or Face ID, for a device that reports one) SHALL be present, carrying the accessibility identifier `unlock.biometricButton`
- **AND** activating it SHALL raise the system prompt
- **AND** the subtitle SHALL read "Touch ID or enter the password for [email] to unlock."

#### Scenario: The button is absent when biometric unlock is disabled
- **GIVEN** biometric unlock is not enabled
- **WHEN** the lock screen is shown
- **THEN** no biometric control SHALL appear
- **AND** the subtitle SHALL read "Enter the password for [email] to unlock."

#### Scenario: The prompt says who is asking
- **WHEN** the system prompt is raised
- **THEN** its reason line SHALL name the application and the sensor — "Open your Vitrine vault with Touch ID"
- **AND** it SHALL NOT be a bare verb phrase that could belong to any process on the machine

#### Scenario: Dismissing the prompt leaves the screen alone
- **GIVEN** biometric unlock is enabled and the auto-prompt fired
- **WHEN** the user cancels or dismisses the biometric prompt
- **THEN** the lock screen SHALL remain visible with no error message shown
- **AND** no further prompt SHALL be raised until the user asks again
- **AND** the password field SHALL have stayed usable throughout

#### Scenario: A second request while a prompt is up is dropped
- **GIVEN** a biometric prompt is on screen
- **WHEN** the unlock control is activated again
- **THEN** the system SHALL NOT queue a second prompt
- **AND** once the first resolves, the control SHALL be effective again

#### Scenario: Biometric lockout shows an error message
- **GIVEN** biometric unlock is enabled
- **WHEN** the biometric prompt fails with a lockout error (too many failed attempts)
- **THEN** the system SHALL display the message "Too many failed Touch ID attempts — enter your master password" and fall back to the password path
