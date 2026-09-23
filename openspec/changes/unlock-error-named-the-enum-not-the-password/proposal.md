# Unlock answers a wrong master password with an enum index — Proposal

## Why

The requirement already exists and is merged:

> `openspec/specs/accessibility-error-suggestions/spec.md:10-12`
> #### Scenario: Invalid credentials error includes suggestion
> - **WHEN** the user enters wrong email or master password
> - **THEN** the error message SHALL suggest checking the email and master password

The login path satisfies it — `AuthError.invalidCredentials` carries
`L("Invalid email or master password. Check your email and master password.")`
(`Domain/Repositories/AuthRepository.swift:242-243`).

**The unlock path did not.** `AuthRepositoryImpl.unlockWithPassword` derives the master key from what
was typed and uses it to decrypt the stored `encUserKey`. A MAC mismatch there *is* the local proof of
a wrong password — it is the same fact the requirement names. But that one decryption was the only
step in the function left unguarded: the two failures before it (missing KDF params, undecodable KDF
params) were already mapped to `AuthError.invalidCredentials`, while this one let
`PrizmCryptoServiceError.invalidEncUserKey` propagate. `UnlockViewModel` shows whatever it is given
through `error.localizedDescription`, and `PrizmCryptoServiceError` had no `LocalizedError`
conformance — so an `Error` with no wording of its own got the system's fallback:

> 未能完成操作。（Prizm.PrizmCryptoServiceError错误1。）

Observed, not inferred: this is the string a user was shown, in the session log, three times in eleven
seconds, on the screen whose job is to tell them their password was wrong.

## What changes

- **`AuthRepositoryImpl.unlockWithPassword`** — the `decryptSymmetricKey` call is wrapped and rethrown
  as `AuthError.invalidCredentials`, which is what the requirement asks for and what the two neighbouring
  failures in the same function already answer with. The underlying error is logged, not displayed.
- **`PrizmCryptoServiceError` gains `LocalizedError`** — all four cases worded. The unlock path no
  longer surfaces this type, but `verifyMasterPassword` (the re-prompt gate) and the sync-time decrypt
  failures reach a banner through it directly, and each of them would print the same fallback. Fixing
  only the one call site would leave the class of the bug in place.
- **`vaultLocked` reuses the sentence the app already has** —
  `L("The vault is locked. Please unlock to continue.")` — rather than adding a second wording of it.

## No spec delta

The behaviour this change produces is the one `accessibility-error-suggestions` already specifies. A
delta would restate a merged requirement; what was missing was the implementation.

## Verification

`AuthRepositoryImplTests` and `PrizmCryptoServiceTests`, run against the unmodified code first:

- **5 failures**, naming each case: `kdfFailed`, `invalidEncUserKey`, `invalidSymmetricKeyLength` and
  `vaultLocked` all reported "fell back to the system's rendering of the type and case number", and the
  unlock test compared `("nil") is not equal to ("Optional(Prizm.AuthError.invalidCredentials)")`.
- After the change: **32 tests, 0 failures**.

The wording test asserts by *negation* — the message must not contain the type name, must not be the
Cocoa fallback string — because the type name survives translation while a fixed sentence would pin
the test to one locale.

## Deliberate limits

- **`UnlockViewModel` still displays `error.localizedDescription` for non-`AuthError` failures.** That
  is the wider defect — untranslated error strings reaching the interface from several screens — and it
  is listed as item ⑧ of the audit this session recorded, not folded in here.
- **No new wording for "the stored key is corrupt" versus "the password was wrong".** Both arrive as
  `invalidEncUserKey` and are answered with the invalid-credentials sentence. The distinction would
  need the crypto layer to separate a parse failure from a MAC failure, and the user's next step is the
  same either way: check the password, then sign in again.

## Impact

- 2 production files, 1 new test, 1 extended test file, 3 new keys in **both** `en.lproj` and
  `zh-Hans.lproj`.
- No crypto behaviour change: the same bytes are derived and checked; only what is said when it fails.
