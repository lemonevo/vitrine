# Remember two-factor device — Proposal

## Why

The "Remember this device" checkbox on the two-factor prompt does nothing.

It is wired all the way to the server — `TwoFactorPromptView` → `LoginViewModel` → `LoginUseCaseImpl`
→ `AuthRepositoryImpl:226` sends `twoFactorRemember: true` — and the server does its part, returning a
`twoFactorToken` in the token response (`TokenResponse.twoFactorToken`, `PrizmAPIClient.swift:274`).

**Prizm then discards it.** `finalizeSession` never reads the field, and the next login always sends
`twoFactorToken: nil` (`AuthRepositoryImpl.swift:159`). So the token is never replayed, the server has
no way to recognise the device, and the user is asked for a code every single time — having been
explicitly told, by a checkbox, that they would not be.

A control that reports success and has no effect is worse than one that is absent: the user believes
something is configured that is not, and the thing they believe is configured is a second factor.

## What Changes

- The `twoFactorToken` returned by a successful two-factor login SHALL be stored when the user asked to
  be remembered, in the Keychain under `WhenUnlockedThisDeviceOnly`.
- It SHALL be replayed on a subsequent login **for the same account**, so the server can skip the
  challenge. The stored value carries the email it belongs to, and is sent only when that matches.
- It SHALL be deleted on sign-out, with the rest of the account's session material.
- The app SHALL NOT report success for storing nothing: a login where the checkbox was ticked and the
  server returned no token is logged, since that is precisely the silent no-op being fixed.

## Non-goals

- **Any UI for the remembered state** (a "forget this device" row, or showing when it expires). The
  checkbox is the control the official client has; a settings row is a separate decision.
- **An expiry.** The token's lifetime is the server's; Prizm stores it and replays it until sign-out.
  Reinterpreting or pre-empting that expiry client-side would be guessing again.
- **Changing when a challenge is shown.** If the replayed token is rejected — expired, or revoked
  server-side — the server answers `twoFactorRequired` and the user is prompted, which is the existing
  path and needs no new handling.

## Two adjacent items this change does NOT do, because verification showed they are not gaps

Both were on the same "unlock and timeout" list, and both were checked against the official client
before being dropped:

- **An "On app restart" vault timeout.** Prizm already locks at launch, unconditionally: any stored
  account sends `RootViewModel` to `.unlock` (`PrizmApp.swift:492-494`), and a restart destroys the
  in-memory vault. The mode's *behaviour* already holds, so adding it would offer the user two options
  that do the same thing and differ only in label.
- **Making the lock-on-sleep/screensaver/screen-lock behaviour configurable.** The official client
  treats "On system lock" and "On system sleep" as choices; Prizm locks on all three unconditionally
  (`PrizmApp.swift:603-621`). Making them optional is weaker, not more complete — a user who chose
  "Never" would stop locking on lid-close. Left as-is deliberately; see the design note.

## Impact

- `Prizm/Data/Repositories/AuthRepositoryImpl.swift` — store, replay, delete
- `Prizm/Data/Repositories/AuthRepositoryImpl.swift` (`KeychainKey`) — two new key names
- `SECURITY.md` — the token is a credential that skips a second factor
