## ADDED Requirements

### Requirement: Disabling biometric unlock reports a key it could not delete
`disableBiometricUnlock()` SHALL delete the biometric-protected vault key before clearing the
`biometricUnlockEnabled` preference, and SHALL fail without clearing it when the delete fails.

The item stays gated by `.biometryCurrentSet`, so a leftover is not an open door — but it is a vault key
that an enrolled fingerprint can still unwrap, and clearing the flag over it would report "off" while
taking away the only retry: a switch that already reads off cannot be turned off again.

#### Scenario: Delete fails, setting stays on
- **GIVEN** the Keychain refuses to delete the biometric vault key
- **WHEN** the user turns Touch ID unlock off
- **THEN** the operation SHALL fail with a message saying the feature is still enabled
- **AND** `biometricUnlockEnabled` SHALL remain true

#### Scenario: Retrying succeeds
- **GIVEN** the first attempt failed and the Keychain now cooperates
- **WHEN** the user turns it off again
- **THEN** the key SHALL be deleted and `biometricUnlockEnabled` set to false

#### Scenario: Sign-out finishes anyway
- **GIVEN** the biometric key cannot be deleted during sign-out
- **WHEN** sign-out continues
- **THEN** the session SHALL still be fully torn down and the failure recorded at fault level
