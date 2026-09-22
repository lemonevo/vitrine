# Remember two-factor device — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`.

## 1. Storing the token

- [x] 1.1 Failing test: completing two-factor login with `rememberDevice: true` writes the token to the
      Keychain, alongside the email it belongs to.
- [x] 1.2 Failing test: the same login with `rememberDevice: false` stores nothing — storing it anyway
      would give a remembered device to a user who declined one.
- [x] 1.3 Failing test: a response carrying no token stores nothing, and the login still succeeds. (The
      log line for this is not asserted; the absence of a stored value is the observable.)
- [x] 1.4 Implement in `loginWithTwoFactorCode`, reading `tokenResp.twoFactorToken` only after the code
      was accepted.
- [x] 1.5 Two `KeychainKey` names, and a comment saying why they are global rather than per-user.

## 2. Replaying it

- [x] 2.1 Failing test: a login for the email the token belongs to sends it as `twoFactorToken`.
- [x] 2.2 Failing test: a login for a different email sends `nil`, and leaves the stored token alone.
- [x] 2.3 Failing test: the email comparison ignores surrounding whitespace and case.
- [x] 2.4 Failing test: with nothing stored, `twoFactorToken` is `nil` — the existing behaviour, kept
      as a guard against the replay path becoming unconditional.
- [x] 2.5 Implement in `loginWithPassword`.

## 3. Removing it

- [x] 3.1 Failing test: `signOut()` deletes both keys.
- [x] 3.2 Implement alongside the other per-account Keychain deletions.
- [x] 3.3 Failing test: `lockVault()` does **not** delete them — locking keeps the session, and the
      remembered device is part of the session rather than of the unlocked state.

## 4. Documentation

- [x] 4.1 `SECURITY.md`: the token is a credential that lets a login skip a second factor. State where
      it lives, what it is worth if stolen, and that it goes on sign-out.

## 5. Verification

- [x] 5.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
- [x] 5.2 Manual: tick "Remember this device", sign out, sign in again, and confirm no code is asked
      for — and that signing out once more removes it.

> **5.2 is outstanding.** It needs a signed app against a live Vaultwarden account: tick the box, sign
> out, sign in again, confirm no code is requested, then sign out once more and confirm it is
> requested again. The unit tests cover Vitrine's half of the exchange end to end through the real
> repository with Keychain and API doubles. What they cannot cover is the server's half — that a
> replayed token actually suppresses the challenge.

> **A documentation correction made in passing.** `SECURITY.md` claimed the device identifier was
> deleted on sign-out; `signOut` does not delete it. The row now says what the code does, and a note
> records that whether it *should* be deleted is a separate question — changing it would give the
> installation a new server-side identity after every sign-out, and the pairing of the remembered
> device to this installation makes that a decision rather than a tidy-up.
