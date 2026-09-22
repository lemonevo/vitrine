# PIN and biometric teardown — Design

## D1 — Fail closed, and only where closing is the honest state

"Fail closed" is not one decision here, it is three, and they differ:

- **Counter unwritable → destroy the PIN.** The limit cannot be enforced, so the thing the limit protects
  is given up. Chosen because an unbounded guess is the outcome the feature exists to prevent.
- **Delete failed on disable → keep the setting on.** The key is still there, so the feature genuinely
  still works. Reporting "off" would be a lie with no retry attached to it.
- **Delete failed during sign-out → continue, and log it.** The alternative keeps the user signed in with
  live keys in memory. Here the honest thing is to finish and say what is outstanding.

## D2 — Why `remove()` throws instead of returning a Bool

A Bool invites every caller to ignore it and still be type-correct. `throws` makes ignoring a compile
error or, at worst, a `try?` that is visibly a decision. There were four call sites; all four now say
what they do with the failure.

## D3 — The mocks had no failure path, so neither did the tests

`MockKeychainService` could not fail a write or a delete, and `MockBiometricKeychainService` had
`readError` and `writeError` but no `deleteError`. Every branch this change is about was therefore
unreachable under test — which is not a coincidence: the reason the production code used `try?` is that
nothing could ever have proved it wrong. Failure stubs came first; the tests were written against them
before the behaviour was called done.

## D4 — Not verified

- **No real Keychain failure was provoked.** Every test drives a double. Whether `SecItemDelete` returns
  a retryable error in the same shape is unobserved; the code treats any error the same way, which is the
  safe direction.
- **The settings UI was not clicked.** `BiometricUnlockToggle` already shows `localizedDescription` on
  failure, and `PinUnlockSection` calls the throwing path inside a `do`, but the new message was never
  watched on screen.
- **A leftover wrapped key was not brute-forced.** The claim is that it remains guessable; that follows
  from how the wrapping works, not from an experiment.
