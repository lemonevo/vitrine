## MODIFIED Requirements

### Requirement: User can unlock the vault with biometrics

> **Superseded the same day** by `openspec/changes/biometric-system-prompt/`. The biometric row below
> and the rule "no separate Touch ID button SHALL be present" were both reversed: the embedded
> `LAAuthenticationView` is what suppressed the system dialog, and the user asked for the dialog. The
> always-armed re-prompting this text assumes was removed with it — correct for an inline glyph, a
> loop when the prompt is modal. Left here as the record of what this change shipped.

The system SHALL provide a biometric unlock path that re-opens the vault without requiring the master
password, using the platform biometric authenticator (Touch ID on macOS, Face ID on iOS). The system
SHALL store the derived vault symmetric key (`CryptoKeys`) in a Keychain item protected by
`kSecAccessControl` with `.biometryCurrentSet`. The master password path SHALL always remain
available as a fallback.

The biometric control is the system's own inline authentication view. It is kept armed continuously,
so it is presented as a **row in the unlock screen's layout** rather than as a badge drawn over
another element: the view has an intrinsic size that the surrounding layout does not constrain, and
an overlay sized to the icon pushed the glyph outside the icon it was meant to sit on.

#### Scenario: Successful Touch ID unlock
- **GIVEN** biometric unlock is enabled and the vault is locked
- **WHEN** the lock screen appears
- **THEN** the system SHALL automatically trigger the biometric prompt
- **AND** on successful biometric evaluation the vault SHALL unlock and the vault browser SHALL be shown without the user entering a password

#### Scenario: Touch ID row is shown when biometric unlock is enabled
- **GIVEN** biometric unlock is enabled and the vault is locked
- **WHEN** the lock screen is shown
- **THEN** the inline biometric authentication view SHALL be presented as its own row in the lock screen
- **AND** the subtitle SHALL read "Touch ID or enter the password for [email] to unlock."
- **AND** no separate Touch ID button SHALL be present, because the sensor is already armed and a button would imply a press that changes nothing

#### Scenario: Touch ID row is absent when biometric unlock is disabled
- **GIVEN** biometric unlock is not enabled
- **WHEN** the lock screen is shown
- **THEN** no biometric authentication view SHALL appear
- **AND** the subtitle SHALL read "Enter the password for [email] to unlock."
- **AND** no biometric affordance SHALL be offered — the master password field is the only way in, which does not remove the screen's ordinary controls

#### Scenario: Biometric unlock falls back to password on cancellation
- **GIVEN** biometric unlock is enabled and the auto-prompt fires
- **WHEN** the user cancels or dismisses the biometric prompt
- **THEN** the lock screen SHALL remain visible with the password field focused and no error message shown

#### Scenario: Biometric lockout shows an error message
- **GIVEN** biometric unlock is enabled
- **WHEN** the biometric prompt fails with a lockout error (too many failed attempts)
- **THEN** the system SHALL display the message "Too many failed Touch ID attempts — enter your master password" and fall back to the password path

## ADDED Requirements

### Requirement: The unlock screen offers a visible way to submit the master password
The lock screen SHALL present a enabled-when-ready submit control for the master password path, in
addition to accepting Return from the password field. The control SHALL reflect the same readiness
rule the submit handler already applies, and SHALL carry the accessibility identifier
`unlock.unlock`.

A screen whose only submit key is Return tells a user nothing about what it is waiting for. The
readiness rule existed and was applied — silently — before this requirement was written.

#### Scenario: Button appears and is disabled until a password is typed
- **WHEN** the unlock screen is shown with an empty password field
- **THEN** the unlock control SHALL be visible and disabled
- **AND** it SHALL become enabled once the field is non-empty

#### Scenario: Pressing the control unlocks
- **GIVEN** a correct master password has been typed
- **WHEN** the user activates the unlock control
- **THEN** the vault SHALL unlock by the same path Return takes

## ADDED Requirements

### Requirement: The lock screen fits its own worst case
The unlock screen SHALL declare a minimum window size that holds the biometric row, the PIN field and
an error banner at the same time, because window resizability is bound to content size and a card
that is vertically centred clips at both ends when the window is shorter than it.

#### Scenario: Every optional element at once
- **GIVEN** biometric unlock and PIN unlock are both available, one PIN attempt has been spent, and an error is showing
- **WHEN** the lock screen is rendered at the window's minimum size
- **THEN** no element SHALL be clipped
