# PIN unlock — Proposal

## Why

Unlocking without the master password is offered by every official client, and Prizm has half of it:
biometrics. Bitwarden's own documentation states that "mobile apps, browser extensions, and **desktop
apps** can be unlocked with a PIN", so this is a genuine gap on this platform rather than a mobile-only
feature — checked before starting, because an earlier batch of this work was planned around gaps that
turned out not to exist.

The value is specific: Touch ID is unavailable on a Mac without a fingerprint sensor and on a Mac
whose sensor has failed, and it can be unavailable in a build without the entitlement. A PIN is the
fallback for exactly those cases, and it is also simply faster for a user who unlocks many times a day.

## What Changes

- A PIN can be set while the vault is unlocked. Setting it wraps the vault's key material under a
  key derived from the PIN, and stores the wrapped material in the Keychain.
- The unlock screen offers the PIN, and unlocking with it produces the same session the master
  password would have.
- **Five wrong attempts wipe the stored material and sign the user out** — matching the official
  behaviour ("you will be automatically logged out after five failed attempts").
- **"Require master password on restart" is available and defaults to on** — also matching the
  official behaviour, and it is the setting that keeps the PIN from being a permanent weakening.
- Signing out removes everything; locking removes nothing.

## Non-goals

- **Biometric and PIN are independent.** Enabling one does not disable the other.
- **No PIN recovery.** There is nothing to recover: the wrapped key is the only thing a PIN unlocks,
  and losing the PIN means using the master password, which is still the account's real credential.
- **No attempt-limit escalation** beyond the wipe (no backoff, no lockout timer, no "N attempts left"
  beyond the count itself). The official behaviour is a hard limit, and a softer variant would be an
  invented policy.
- **No change to what the master password can do.** The PIN is a second way in, not a replacement.

## What this deliberately gives up, stated plainly

A PIN is low-entropy — four digits is ten thousand guesses — and the official documentation says so
itself: "Using a PIN can weaken the level of encryption that protects your application's local vault
database."

So the protection does **not** rest on the key derivation being slow. It rests on two things, and
`SECURITY.md` will say both:

1. the wrapped material lives in the Keychain under `WhenUnlockedThisDeviceOnly` — device-only, not
   synchronised, not backed up, unreadable while the Mac is locked; and
2. the five-attempt limit, whose count is also stored durably, so restarting the app does not hand an
   attacker a fresh set of guesses.

This is a deliberate, documented weakening chosen by the user, off by default, and reversible. It is
in the same family as the biometric key that already exists — and it is the reason the
"require master password on restart" default matters.

## Impact

- `Prizm/Domain/Repositories/PinUnlockService.swift` — **new**
- `Prizm/Data/Repositories/KeychainPinUnlockService.swift` — **new**
- `Prizm/Data/Crypto/PrizmCryptoService.swift` — expose PIN-key derivation over the existing PBKDF2
- `Prizm/Data/Repositories/AuthRepositoryImpl.swift` — enable / disable / unlock / wipe
- `Prizm/Presentation/Unlock/UnlockView.swift`, `UnlockViewModel.swift` — the PIN path
- `Prizm/Presentation/Settings/` — the toggle, the set-PIN sheet, the restart setting
- `SECURITY.md` — the mechanism and the weakening
