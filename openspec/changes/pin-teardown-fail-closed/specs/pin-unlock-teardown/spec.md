## ADDED Requirements

### Requirement: Turning PIN unlock off only succeeds when the stored key is gone
`PinUnlockService.remove(userId:)` SHALL report whether the wrapped key, its salt and the attempt count
were actually deleted, and SHALL NOT treat a Keychain error as a successful removal. Removing an item
that does not exist is not an error.

The leftover is a vault key wrapped under a short code. A settings screen that shows the feature off
while that key is still stored both misinforms the user and removes their way to retry, because a switch
that already reads off cannot be turned off again.

#### Scenario: A failed delete is a failed disable
- **GIVEN** the Keychain refuses to delete the wrapped material
- **WHEN** the user turns PIN unlock off
- **THEN** the operation SHALL fail with a message saying the feature is still enabled
- **AND** the setting SHALL remain on so the user can try again

#### Scenario: Nothing enrolled is not a failure
- **GIVEN** no PIN has ever been set for the account
- **WHEN** the removal runs
- **THEN** it SHALL succeed

---

### Requirement: The attempt limit stops existing if it cannot be counted
A failed write of the PIN failure counter SHALL destroy the stored PIN material and report the operation
as unavailable, rather than continuing with a limit it can no longer enforce.

The counter is the whole of a short PIN's protection: a four-digit code is about ten thousand
candidates, and the only thing between that number and an attacker holding the device is that the app
stops after five. A silently unwritten count means every later attempt re-reads the same stale number and
the ceiling never arrives.

#### Scenario: Unwritable counter, no PIN
- **GIVEN** the attempt count cannot be written after a wrong PIN
- **WHEN** the failure is recorded
- **THEN** the wrapped material, its salt and the counter SHALL be removed
- **AND** the caller SHALL be told the PIN path is unavailable

#### Scenario: Writable counter, five attempts is five attempts
- **GIVEN** a PIN is enrolled and the Keychain is healthy
- **WHEN** the user enters a wrong PIN five times
- **THEN** the fourth SHALL report four and one remaining attempt in order
- **AND** the fifth SHALL report exhaustion and leave no wrapped material behind

---

### Requirement: Sign-out reports a key it could not remove without aborting
Sign-out SHALL continue tearing down the session when a PIN or biometric key cannot be deleted, and SHALL
record at fault level that the material may still be stored.

Aborting would leave live session keys in memory and the user unable to leave — a worse state than the
one being cleaned up. This is deliberately different from the settings screen, where the same failure
throws: there is nothing else to clean up there, and the user has a retry available.

#### Scenario: A failed removal does not stop the teardown
- **GIVEN** deleting the PIN material fails during sign-out
- **WHEN** sign-out continues
- **THEN** the session keys, cached vault and stored tokens SHALL still be cleared
- **AND** the log SHALL name the material that may remain
