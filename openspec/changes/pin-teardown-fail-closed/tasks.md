# PIN and biometric teardown — Tasks

## 1. Make the failures reachable in tests

- [x] 1.1 `MockKeychainService`: `failingWrites` / `failingDeletes`.
- [x] 1.2 `MockBiometricKeychainService`: `deleteError` (it had read and write stubs, no delete).

## 2. The service

- [x] 2.1 `PinUnlockService.remove(userId:)` throws; the protocol documents why.
- [x] 2.2 `recordFailure` throws; an unwritable counter destroys the PIN instead of continuing.
- [x] 2.3 The post-success counter reset logs rather than throwing — a stale-high count locks out early,
      which is the safe direction to be wrong in.
- [x] 2.4 `isSet()` distinguishes "no PIN" from "would not say", and logs the second.
- [x] 2.5 `setPin`'s rollback says what it says.

## 3. The repository

- [x] 3.1 `disablePinUnlock()` propagates.
- [x] 3.2 `disableBiometricUnlock()` clears the flag only after a successful delete (D1).
- [x] 3.3 Sign-out reports both failures at `.fault` and continues (D1).
- [x] 3.4 New `AuthError.secretRetirementFailed`, in both string tables.

## 4. Tests

- [x] 4.1 `testRemove_whenADeleteFails_throwsRatherThanClaimingSuccess`.
- [x] 4.2 `testWrongPin_whenTheCounterCannotBeWritten_destroysThePin`.
- [x] 4.3 `testWrongPin_fiveWrongGuessesDestroyTheMaterial` — the cap, asserted per attempt.
- [x] 4.4 `testDisableBiometricUnlock_whenTheDeleteFails_keepsTheSettingOnAndThrows`, including the retry.
- [x] 4.5 `testRemove_whenNothingIsSet_doesNotThrow` still passes, so idempotence did not regress.

## 5. Not verified

- 5.1 No real Keychain failure was provoked; every branch is driven through a double (design D4).
- 5.2 The settings UI was not watched showing the new message.
- 5.3 A leftover wrapped key was not actually brute-forced.

## 6. Deliberately not done

- 6.1 Login/unlock key-buffer zeroing (inventory §7) stays open — it needs its own change.
- 6.2 The attempt limit's value and the PIN derivation are unchanged.
