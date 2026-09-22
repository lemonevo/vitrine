# PIN and biometric teardown: fail closed, and say so — Proposal

## Why

**Turning a security feature off could fail silently, and the app would then report that it had
succeeded.** Three places, one shape:

- `KeychainPinUnlockService.remove()` was non-throwing and deleted with `try?`. Its callers —
  `disablePinUnlock()` and sign-out — then logged "PIN unlock disabled" unconditionally. If the delete
  failed, the vault key stayed wrapped under a four-digit code in the Keychain, the settings screen
  showed the feature off, and the user had no way to find out or to retry, because the switch already
  read off.
- `recordFailure()` wrote the incremented attempt count with `try?`. A failed write left the stored
  count where it was; the next wrong PIN read the same stale number and incremented it again. **The
  five-attempt limit, which is the entire protection a short PIN has, quietly stopped existing** — an
  attacker with the device could guess without ever hitting a ceiling. The code then logged
  "key material has been destroyed" on the exhaustion path whether or not the deletion had worked.
- `disableBiometricUnlock()` did `try?` on the delete, then set the preference to false, then logged
  success.

None of these produced a symptom. The counter is not visible, the leftover Keychain item is not visible,
and the log line said the opposite of the truth in each case.

## What changes

- **`PinUnlockService.remove(userId:)` now throws**, and reports how many of the three items survived.
  Deleting an item that is not there is still not an error, which `testRemove_whenNothingIsSet_doesNotThrow`
  keeps honest.
- **A counter that cannot be written destroys the PIN** and throws, rather than carrying on with a
  limit it can no longer count against. Losing a convenience the user can re-set beats keeping a bound
  they cannot see.
- **`disableBiometricUnlock()` leaves the setting on when the delete fails.** Clearing the flag over a
  failed delete is the worst of both: it reports "off", leaves a key an enrolled fingerprint can still
  unwrap, and takes away the only retry path — you cannot turn off a switch that already says off.
- **Sign-out keeps tearing down.** Both removals are reported at `.fault` with the consequence named,
  and do not abort the rest of sign-out: leaving live session keys in memory because a Keychain delete
  failed is a worse state than the one being cleaned up. That is a deliberate asymmetry against the
  settings screen, which *does* throw, because there is nothing else to clean up there.
- New `AuthError.secretRetirementFailed`, with a message that says what is still true ("this is still
  enabled") and what to do about it. `BiometricUnlockToggle` already surfaces `localizedDescription`, so
  no new UI was needed.
- `isSet()` distinguishes "no PIN" from "the Keychain would not say", and logs the second.

## Tests

`MockKeychainService` and `MockBiometricKeychainService` had no way to make a delete or a write fail —
so every one of these branches was structurally untestable, which is how it stayed wrong. Both mocks now
take failure stubs, and four tests cover the new behaviour, including that a biometric disable can fail,
be retried, and succeed.

## What this does not change

No change to how a PIN is derived, wrapped, or verified; no change to the attempt limit's value; no
change to what is stored where. This is entirely about what happens when the Keychain says no.

## Still open, found here

`remove()` on the **login-path** key zeroing (inventory §7) is untouched: login and unlock still do not
zero the master-password-derived buffers, and `Data`'s copy-on-write means zeroing one reference is
partly cosmetic. That needs its own change with a real design question behind it, not a bolt-on.
