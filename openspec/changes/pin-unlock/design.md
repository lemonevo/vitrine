# PIN unlock — Design

## Context

The biometric path is the shape to copy, and it is worth naming precisely because the difference is
the whole design:

`enableBiometricUnlock` takes the vault's live `CryptoKeys`, calls `toData()`, and writes those 64
bytes into a Keychain item whose access control is `.biometryCurrentSet`
(`AuthRepositoryImpl.swift:569-583`). The **gating is done by the Keychain** — the system refuses to
hand the bytes over until Touch ID succeeds. `unlockWithBiometrics` reads them back and calls
`crypto.unlockWith(keys:)` (`:604-625`).

A PIN cannot work that way. No Keychain access control evaluates a PIN, so the gating has to be
**cryptographic**: the stored bytes must be unreadable without the PIN. Which means the same 64 bytes
are stored, but *wrapped*, and the PIN derives the wrapping key.

## Decision 1 — wrap the key material with a PIN-derived key

```
salt      = 32 random bytes, generated once per installation
pinKeys   = PBKDF2-SHA256(pin, salt, iterations) → 64 bytes → CryptoKeys(enc, mac)
wrapped   = EncString.encrypt(CryptoKeys.toData(), keys: pinKeys)
```

and unlock is the inverse: read the salt and the wrapped value, derive with the entered PIN, decrypt,
rebuild `CryptoKeys`, `crypto.unlockWith(keys:)`.

Every primitive is already in the codebase and none of it is hand-rolled: `pbkdf2SHA256` is
CommonCrypto-backed (`PrizmCryptoService.swift:655`), and `EncString.encrypt`/`decrypt` is the
AES-256-CBC + HMAC-SHA256 Encrypt-then-MAC construction used for every field in the vault
(`EncString.swift:165,188`).

The derivation gets a small method on `PrizmCryptoService` rather than being assembled in the
repository, so the PBKDF2 helper stays private and PIN derivation sits beside `makeMasterKey` and
`stretchKey` — the other two things that turn a secret into keys.

## Decision 2 — a per-installation random salt, not a fixed one

A fixed salt (an email address is the obvious choice, and is what some clients have used) lets one
precomputation serve every installation in the world, and lets two users with the same PIN share a key.
A random salt per installation costs 32 bytes and removes both.

It is stored beside the wrapped value. It is not secret; it only has to be unique.

## Decision 3 — the attempt count is stored durably, and the fifth failure wipes

The count lives in the Keychain with the wrapped material, not in memory. An in-memory counter is
defeated by quitting the app — an attacker with the disk could take five guesses, restart, and take
five more, forever. That is the difference between a limit and the appearance of one.

On the fifth failure: delete the wrapped value, the salt and the count, then sign out. Deleting the
material is what makes the limit real; signing out is what makes the consequence visible.

The comparison is over the *decrypt*, not over a stored PIN: nothing anywhere holds the PIN itself or a
hash of it that could be tested offline. A wrong PIN simply fails to decrypt, which is also why there
is no "PIN is wrong" oracle beyond the AEAD's own authentication tag.

## Decision 4 — "Require master password on restart" defaults to on

Matching the official client, and it is the setting that keeps this from being an unconditional
weakening: with it on, the PIN does not unlock a freshly launched app at all. The user opts *in* to
the weaker behaviour instead of having to discover the setting to opt out.

Implementation note: with the setting on, the unlock screen does not offer the PIN until the master
password has been accepted once in this launch. The stored material is left alone — the PIN still
works after a lock, which is the case it is actually for.

## Decision 5 — iteration count

The account's own KDF iteration count is the obvious choice and the wrong one: it is tuned for a
master password, which has far more entropy than four digits, and it would make PIN unlock take
roughly as long as a master-password login — slow enough that people stop using it, for a gain that
does not close a 10^4 search space anyway.

A fixed, moderately high count is used instead, and **the honest framing is that the KDF is not what
protects this.** It raises the cost of a bulk offline attack on the wrapped blob; it does not make a
four-digit secret strong. See the proposal's section on what is given up.

## Non-goals recorded

- **No PIN change flow that keeps the old PIN valid.** Changing the PIN re-wraps with the new one; the
  vault must be unlocked to do it.
- **No interaction with biometrics.** Both can be enabled; the unlock screen offers whichever are.
- **No PIN strength meter.** A four-character minimum, as the official client requires, and the
  warning in `SECURITY.md`.

## Verification

Unit tests, against the real `KeychainPinUnlockService` with a Keychain double:

- the wrapped blob is not the key material — a test that reads the stored bytes and asserts the
  original key is not recoverable from them without the PIN
- a round trip: set a PIN, unlock with it, get the same key material back
- a wrong PIN fails and does not corrupt the stored material
- the count persists across a fresh service instance, and the fifth failure wipes
- sign-out removes everything; lock removes nothing
- with "require master password on restart" on, the PIN is not offered on a cold start

What they cannot show is the thing that matters most to a user: that a person who does not know the
PIN cannot get in. That is what the manual check is for — set a PIN, quit, relaunch, and confirm the
vault does not open without either the PIN or the master password.
