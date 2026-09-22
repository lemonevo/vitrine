# Design — phase 2 (data sovereignty and security tools)

## D1. The export format is Bitwarden's own unencrypted JSON, not a Vitrine format

A backup that only Vitrine can read is not an escape hatch — it is a second lock. The file is
therefore the format every Bitwarden client already imports, so the vault can be restored by
Vitrine, by the official desktop app, by `bw`, or by any Vaultwarden-compatible tool.

**The shape below was read out of Bitwarden's own export classes, not reconstructed from
memory** — `libs/common/src/models/export/*.export.ts` and
`libs/tools/export-vault-core/src/services/individual-vault-export.service.ts` in
`bitwarden/clients`. That mattered: two of the assumptions this document started with were wrong,
and both are recorded below rather than quietly corrected.

```
{
  "encrypted": false,
  "folders": [ { "id": "...", "name": "..." } ],
  "items": [
    {
      "id": "...", "organizationId": null, "folderId": "...", "collectionIds": null,
      "type": 1, "reprompt": 0,
      "name": "...", "notes": "...", "favorite": false,
      "fields": [ { "name": "...", "value": "...", "type": 0, "linkedId": null } ],
      "login": { "uris": [ { "match": null, "uri": "..." } ],
                 "username": "...", "password": "...", "totp": "..." },
      "passwordHistory": [ { "password": "...", "lastUsedDate": "2024-01-01T00:00:00.000Z" } ],
      "creationDate": "...", "revisionDate": "...", "deletedDate": null, "archivedDate": null
    }
  ]
}
```

Type integers are the server's `CipherType` enum — 1 login, 2 secure note, 3 card, 4 identity,
5 SSH key — the same mapping `CipherMapper.mapContent` already uses. `encrypted: false` is what
makes every client treat the file as plaintext rather than trying to decrypt it.

Details that are easy to get wrong, each taken from the source:

- **Folders carry an `id`.** `FolderExport` alone has only a `name`; the individual export builds
  `FolderWithIdExport`. An item's `folderId` therefore refers to a folder in the same file, which
  is what makes the association restorable.
- **Items carry an `id` too** (`CipherWithIdExport`). It is written but **never read back on
  import** — the server assigns ids, and the file-local one means nothing on another server.
- **`match` is an integer, not a string** (`UriMatchStrategySetting`). `URIMatchType` is already
  `Int`-backed, so no translation layer is needed.
- **`collectionIds` is `null`, not `[]`, for a personal item.** The export service assigns `null`
  explicitly.
- **`key` is deleted before writing** (`delete cipher.key`). The unencrypted export carries no
  per-item key, which is consistent with not carrying the per-item key's payloads either.
- **Deleted items are not exported.** The service filters `deletedDate == null`. Trash is
  deliberately not part of a backup, and the consent sheet says so.
- **`passwordHistory` IS part of the format** — `{ password, lastUsedDate }`. The first draft of
  this document claimed the format had no place for it and that it would be dropped; that was
  wrong, and it is exported. The file already contains every *current* password in plaintext, so
  the previous ones add no new class of exposure, and omitting them would mean a restore silently
  loses them.
- **The org export uses a different wrapper** — `{ encrypted, collections, items }` — but the same
  `CipherWithIdExport`, with `organizationId` and `collectionIds` populated.

**What is deliberately NOT exported**, each because exporting it would be wrong rather than
merely incomplete:

| Field | Why not |
|---|---|
| `preserved.fido2Credentials` | A passkey's private key. Exporting it to a plaintext file would hand over an account credential that the file's stated contents do not mention, and the format's own `fido2Credentials` field is a `Fido2CredentialExport` whose plaintext form no client expects to receive. |
| `preserved.cipherKey` | Deleted from the unencrypted export by the reference implementation. |
| `attachments` | The reference export puts blobs in a separate ZIP (`getDecryptedExportZip`); the plain JSON carries none. A file listing attachment names without their contents is a false promise, so the names are not written either. |
| Items in Trash | Matches the reference implementation. |

**Vitrine exports organisation items; the reference individual export does not.** The official
individual export filters `c.organizationId != null` out, which means an official "export my
vault" silently omits everything the user holds through an organisation. Vitrine includes them, with
`organizationId` and `collectionIds` populated exactly as the official *org* export does. Every
field used is one of the reference classes' own fields, so the file is still readable by any
client; the difference is that it does not throw data away. Importing such a file into Vitrine drops
the organisation membership and reports it (D4).

The export therefore has a **documented boundary**, and the consent sheet names it. Silently
omitting fields is the failure mode this whole project exists to avoid.

## D2. Export requires explicit consent, and the file is written `0600`

Constitution, Bitwarden normative standards: *"Export consent: User consent is mandatory before any
vault export operation."* A modal sheet states, before anything is written:

- the file contains **every password in the vault, in plain text**;
- anyone who can read the file can read the vault;
- it will not be encrypted and Vitrine cannot protect it afterwards.

The user must confirm. Cancelling writes nothing and leaves no partial file.

The file is created with POSIX permissions `0600` (`FileManager.setAttributes` after the atomic
write, because `.atomic` renames a temporary file and the final mode is not guaranteed). This does
not make the file safe — it is plaintext — but it does keep it out of reach of other local
accounts, which is the difference between "a file you should delete" and "a file the whole machine
can read".

Nothing about the export is logged. The `Logger` calls that surround it record the item count and
the destination path, never a value.

## D3. Export is a use case returning bytes; the panel is injected

`ExportVaultUseCase.execute()` returns `VaultExport` — the encoded `Data` plus a suggested filename
— and writes nothing. The file is written by a `fileSaver: (String, Data) -> URL?` closure that
`AppContainer` supplies, wrapping `NSSavePanel`. This is the same seam
`AttachmentRowViewModel` already uses for `NSSavePanel`, and it exists for the same two reasons:
the Presentation layer must not import AppKit (Constitution §II), and a use case that pops a panel
cannot be unit-tested.

`NSSavePanel` is configured with `canCreateDirectories = true` and the `.json` allowed type, and
`nameFieldStringValue` defaults to `prizm_export_YYYYMMDD.json`.

## D4. Import is additive, sequential, and reports per outcome

**Additive.** Import never deletes, never overwrites and never merges. A file imported twice
produces two copies, which is the behaviour the official clients have and the only one that cannot
lose data.

**Personal items only.** An imported item's `organizationId` and `collectionIds` are dropped: the
user may not belong to that organisation on this server, and writing an item into a collection the
account cannot see would create an item that is invisible in every client. The report says so.

**Folders are matched by name, case-insensitively**, against the folders already in the vault, and
created when there is no match. The format identifies folders by a file-local `id`, which means
nothing on this server; the name is the only thing that survives the round trip.

**`id` is never imported.** The server assigns it. Carrying the old one would either be ignored or,
worse, collide.

**Sequential with a running count, not parallel.** `POST /api/ciphers` per item is the only
endpoint available, and firing 500 of them concurrently would be indistinguishable from an attack
to any rate limiter. Each item's outcome is recorded, and the run continues past a failure — the
same reasoning as `EmptyTrashUseCase` (phase 1 D10): N independent requests produce a partial
result, and reporting it honestly is better than stopping halfway.

**The report is the deliverable.** `ImportSummary` carries `imported`, `skipped` (with the reason —
unknown type integer, malformed item, no name) and `failed` (with the server's error). The UI shows
all three counts and lists the reasons; it does not show a green tick.

## D5. The strength estimator is local and pattern-aware, and says what it is

Bitwarden uses `zxcvbn`. Vitrine does not, and the reason is the Constitution: *"Prefer Apple-first
APIs; minimize external dependencies"* and the third-party crypto prohibition. `zxcvbn` is not
crypto, but a password-strength estimate is security-relevant input to a security decision, and
its value is almost entirely its dictionaries — 30k+ common passwords and a full English word
list, shipped as data.

`PasswordStrengthEstimator` therefore implements a **documented, testable, pattern-aware
guess-count model** instead:

1. **Tokenise** the password into runs of digits / lowercase / uppercase / symbols.
2. **Per-run guess count**: `charsetSize ^ length` for the run's own alphabet.
3. **Penalties**, each a divisor, each for a pattern that collapses the real search space:
   - a repeated character run (`aaaa`, `abab`);
   - a keyboard or alphabet sequence (`qwerty`, `abcde`, `12345`), scored as its start point plus
     length rather than as a full-length brute force;
   - a date-like run (`1998`, `12/25`);
   - a match against the embedded common-password list;
   - a match against the bundled EFF word list (a passphrase word is ~7776 options, not
     `26^length`).
4. **Sum** the per-token counts and take `log10`.

Scores follow `zxcvbn`'s thresholds so the numbers mean something familiar: `< 3` very weak,
`< 6` weak, `< 8` fair, `< 10` strong, else very strong.

**The limitation is documented in the type's doc comment and in `SECURITY.md`.** This is not
`zxcvbn`: it has a few hundred common passwords rather than tens of thousands, it does not model
l33t substitutions or multi-word combinations, and it will over-rate a password built from two
uncommon words. It is a directional signal, and the UI presents it as one ("estimate"), never as a
verdict.

**The leaked-password check is deliberately out of scope.** It requires sending a hash prefix to
Have I Been Pwned. That is exactly the class of third-party disclosure `FEATURE-GAP-ANALYSIS.md`
§2.5 was about, and a client whose selling point is self-hosting should not open a connection to a
public API the user did not configure. Stated in the report UI rather than left as a gap the user
cannot see.

## D6. The health report is five local checks, and the sixth is refused on purpose

| Check | Definition | Why it is worth a row |
|---|---|---|
| Weak | strength score ≤ *weak* | The estimator's output, applied across the vault. |
| Reused | the same non-empty password on ≥ 2 login items | One breach becomes several. |
| Stale | `preserved.passwordRevisionDate` is absent, or older than 2 years | The server maintains this date; ignoring it wastes a field Vitrine already carries. |
| Unsecured site | a URI whose scheme is `http` | Plaintext credentials on the wire, and it is a one-line check. |
| Missing TOTP | a login with a password and no `totp` seed | Bitwarden's "inactive 2FA". The seed is already decrypted and already in `LoginContent`. |

All five run against the **already-decrypted in-memory vault**. No request is made, and the report
is therefore available on a server with no internet access at all.

The report model carries, per check, the count and the offending `(id, name)` pairs, so the sheet
can list items and select one on click instead of showing five numbers the user cannot act on.

**Compromised passwords are not checked**, for the reason in D5. The sheet says so explicitly,
next to the five checks that did run, so the absence is visible rather than assumed.

## D7. Re-prompt is enforced in `RootViewModel`, once per unlock session

`VaultItem.reprompt` already round-trips (phase 0). What is added is the gate.

**Where the grant lives.** `RootViewModel` holds `repromptGrants: Set<String>` — the item ids whose
master password has been entered since this unlock. `lockVault()` and `signOut()` clear it, in the
same teardown that clears the vault store and every key cache (Constitution §III). A grant
therefore cannot outlive the key material it protects.

**Why once per session and not once per reveal.** Bitwarden's desktop client re-prompts on each
disclosure of a re-prompt-protected item within a short window. A session-scoped grant is simpler,
is what the official browser extension does for the session, and — more importantly — is
*auditable*: "this item was unlocked at this point in the session" is a statement the user can
reason about, where a 30-second timer is not.

**The gate is a boolean, not a closure.** The detail views take `isSecretRevealed: Bool` and
`onRequestReveal: () -> Void`. `VaultBrowserViewModel` owns
`@Published private(set) var revealedItemIds: Set<String>` and presents the sheet. Making the
detail view call back into the view model — rather than awaiting a closure inside the view —
keeps the reveal state in one place and keeps `LoginDetailView` a pure function of its inputs.

**What is gated:** revealing the password, copying the password, copying the TOTP code, revealing
hidden custom fields, and revealing password history. **What is not:** the item's name, username,
URIs, notes, card numbers and identities. Bitwarden gates the same set. Gating the item name would
make the list unusable, and gating the username would break the copy-username command that exists
precisely because it is the low-risk half.

**Verification is local.** `AuthRepository.verifyMasterPassword(_:) async throws -> Bool` derives
the key from the stored KDF parameters and compares, and **does not** touch the session: it does
not re-derive into the live key cache, does not change the account, and does not clear anything.
Using `unlockWithPassword` for this would work but would make a read-only check mutate session
state, which is the kind of coupling that later becomes a defect. A wrong password is `false`, not
a thrown error; a network failure is impossible because nothing is requested.

## D8. Custom CA trust and certificate pinning are one policy, applied to one host

`ServerTrustDelegate` implements `urlSession(_:didReceive:completionHandler:)`. Its decision table:

| Condition | Decision |
|---|---|
| Host ≠ the configured server's host | `.performDefaultHandling` |
| No trust configuration for this server | `.performDefaultHandling` |
| A custom CA is configured | Evaluate the chain against it with `SecTrustSetAnchorCertificates` + `SecTrustSetAnchorCertificatesOnly(true)` + `SecTrustEvaluateWithError`. Failure → cancel. |
| A fingerprint is pinned and matches | Accept |
| A fingerprint is pinned and does **not** match | Cancel, and surface a distinct error |
| Pinning enabled, no fingerprint stored yet | Accept and record the leaf's SHA-256 (trust on first use) |

**Scoped to one host, deliberately.** The Azure blob endpoint an attachment download redirects to
is a different host with a valid public certificate. Applying the user's private CA to it would
break attachment downloads, and applying a pin to it would be pinning a host the user never chose.
The check is therefore on the host, not on the app.

**Pinning is off by default and opt-in.** A pin that is enabled by default and silently records
the first certificate it sees would lock a user out of their own server the first time they
reinstall — and the recovery is a Keychain edit. It is offered, explained, and revocable with a
"Forget pinned certificate" button that is always reachable.

**Persistence is the Keychain, not `UserDefaults`.** The trusted CA and the pin are security
configuration: a process running as the user can rewrite `UserDefaults` with a single `defaults
write`, and doing so would let an attacker add their own CA. Keychain items are
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and never synchronisable, matching the existing
secret-storage rules. They are not secrets, but they are the inputs to a trust decision, and
`UserDefaults` is not an acceptable home for those.

**What is not tested.** The handshake itself. A unit test cannot stand up a TLS server with a
private CA, and faking `SecTrust` would test the fake. `ServerTrustPolicy.decide(...)` is
therefore a **pure function** over `(host, configuredHost, trustConfiguration, observedLeafHash)`
returning an enum, and that function is fully unit-tested. The delegate is a thin adapter over it.
This limitation is stated in the test file and in `SECURITY.md` rather than hidden.

## D9. Generator history is memory-only

A generated password that was never saved is still a credential: it is very often about to become
someone's actual password. Persisting it to disk would create a plaintext secret store that the
user never asked for and cannot see the contents of.

`GeneratorHistory` is therefore a bounded ring buffer — the most recent 20 values, each with the
timestamp it was generated — held in `AppContainer`, cleared by `lockVault()` and `signOut()`
alongside the key caches. Nothing is written anywhere. Quitting Vitrine loses it, which is the
correct behaviour and is stated in the section footer.

The generator sheet reads it; the entry is only added when the user copies or accepts a value, not
on every keystroke of a length slider. A history of values the user never looked at is noise.

## D10. Password history is decrypted on demand, and the doc comment changes with it

`PreservedCipherFields` currently states that nothing in it is ever decrypted, *because no screen
displays it*. This feature invalidates the second half of that sentence, so the first half has to
change with it — leaving the comment in place would make the file lie about itself, which is the
failure mode Constitution §VII exists to prevent.

The rule becomes: password history is decrypted **only** by `GetPasswordHistoryUseCase`, **only**
when the user has passed the re-prompt gate for that item, and the plaintext is never cached — the
use case re-derives on every call, matching `itemDetail(id:)`'s existing "decrypt on demand"
contract. `fido2Credentials` and `cipherKey` remain never-decrypted.

The decryption key is the item's own: `preserved.cipherKey` when present, otherwise the vault or
organisation key — the same resolution `CipherMapper` performs for the current password, reused
rather than reimplemented.

The section is collapsed by default, and the re-prompt gate applies to it because a previous
password is frequently the current password of the account next door.

## D11. Two-factor: two new methods, and an honest name for the rest

Provider numbers are the server's `TwoFactorProviderType` enum. Vitrine now handles:

| # | Method | How it is completed |
|---|---|---|
| 0 | Authenticator app (TOTP) | 6-digit code typed in |
| 1 | Email | A code the server emails; typed in. A "Resend code" button calls `POST /api/two-factor/send-email`. |
| 3 | YubiKey OTP | The key types a 44-character OTP into the same field. No SDK: a YubiKey in OTP mode is a keyboard. |

Still unsupported, and now **named** rather than generic: Duo (2), YubiKey NFC (4), Remember (5),
Organisation Duo (6), WebAuthn (7). Duo needs its web SDK embedded; WebAuthn needs an associated
domain and an entitlement. Both are real projects and are not smuggled into this one.

**Selection order** when the server offers several: authenticator app → YubiKey OTP → Email. TOTP
is the method that needs nothing else from the environment, so it is the least likely to fail
mid-login.

**The pending provider is remembered.** `PendingTwoFactor` gains the chosen provider number, so the
second request sends `twoFactorProvider` matching the code that was actually entered. Sending the
wrong provider number is the difference between "the code was wrong" and "the code was right and
the server rejected it anyway".

## D12. The fingerprint phrase is computed only after the algorithm is verified

Bitwarden's fingerprint phrase is a five-word phrase derived from the account's public key. Its
entire value is that it **matches what another client shows** — it is a comparison, so a phrase
that is merely plausible is worse than no phrase at all.

The account's public key is not on the wire; the sync profile carries the encrypted RSA private
key. Deriving the public key from it and hashing it is mechanical. The wordlist mapping is not, and
the exact byte order, chunk size and wordlist are the parts that have to match Bitwarden's
implementation precisely.

**This item is therefore gated on verifying the algorithm against the Bitwarden client source
before any code is written.** If the algorithm cannot be confirmed, the feature is dropped rather
than shipped as "a phrase Vitrine computes", and the gap analysis records why. A five-word phrase
that does not match the official client would be actively misleading in exactly the situation it
exists for.

## D13. Preferences follow the phase 1 shape, and mutable fields follow the phase 0 rule

New preferences (`repromptEnforcement`, `certificatePinning`, the trusted CA and the pin) use the
same shape as `ClipboardClearInterval` and `WebsiteIconsPreference`: an explicit "key absent"
branch, never the type's zero value, and an injectable store so tests never touch the real one.

`DraftVaultItem.reprompt` changes from `let` to `var`, and `DraftLoginContent.totp` likewise — the
import path has to be able to set a TOTP seed, and the edit form has to be able to toggle
re-prompt. Both are documented as newly mutable at the point of change, because the surrounding
`let` fields are deliberate and a reader should not conclude the rule was relaxed.

## D14. Everything new is gated on the vault being unlocked, and on nothing else

Every one of these features reads or writes decrypted vault data. Export, import, the health
report, password history, the fingerprint phrase and the re-prompt gate all require
`isVaultUnlocked`; the menu items are disabled otherwise, matching how ⌘R and ⌘D were handled in
phase 1.

There is no partial-availability mode. A half-working export is worse than a disabled one.
