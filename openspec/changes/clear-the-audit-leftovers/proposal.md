# The rest of the audit list — Proposal

## Why

The audit that opened this session graded its findings and the first three were fixed in
`cut-redundant-render-asks`. What is left was reported and deferred, item by item, with reasons.
This closes those items — the ones that are defects — and states plainly which ones it does not, so
the list stops being re-derived from scratch by whoever reads the code next.

Nothing here is a performance change. These are the lines that mislead: a type that looks used and is
not, a comment that describes a call site that does not exist, a check that can never fail, a rule
written down twice, a user-facing error that arrives as a type name and a case index.

## What changes

**Dead code (⑥).** `GlyphControl` (`Presentation/Components/ControlStyles.swift`) had no call site
anywhere in the repository, and its own doc comment described detail-row usage that belongs to a
*different* type — `GlyphControlStyle`, which is used and is not this. `main-window-p3-pass` records
adding it, and that record is accurate: it was added, and nothing was ever switched over to it, so its
comment described a call site the redesign left behind. Also
`AccessibilityID.Vault.verificationCodesButton`, the toolbar button the sidebar destination replaced;
its comment still described a button that opens a sheet.

**Compiler warnings.** Five, all of them load-bearing rather than cosmetic:

- `KeychainPinUnlockService.isSet` was written `try keychain.read(...) != nil` against a `read` that
  returns non-optional `Data` and *throws* when absent. The comparison is always true — the compiler
  said so. The behaviour was right only because the `catch` below does the actual detecting, which is
  the kind of line a later reader "simplifies" into a real bug.
- `AuthRepositoryImpl` bound `if let pending = pendingTwoFactor` and then never used `pending`,
  deliberately (zeroing the copy would zero a CoW copy). The binding made the compiler report a value
  defined but never used; the check is now written as the test it is.
- Three `var`s in `OpenSSHPrivateKey` that are never mutated. Left as `var` they sit next to the four
  that *are* mutated and zeroized, which invites the reader to assume they are key material that needs
  erasing. They are the public halves.

**The duplicated date rule (⑦).** `VaultRepositoryImpl` and `VaultExportDocument` each carried a
byte-identical pair of `ISO8601DateFormatter`s plus the same "try fractional seconds, then plain"
fallback. Extracted to `Domain/Utilities/ISO8601WireDate`. This is *not* the duplication that
`SyncTimestampRepositoryImpl`'s comment declines to merge — that decision is about two Data-layer
types each holding **one** formatter, and it stands, unchanged, and the new file says so by name so
nobody "finishes" the consolidation without reading it. What was merged is a *rule*, where drift is
silent: a date format one copy learns to reject degrades to `nil`, so the two disagreeing would show
up as items with no revision date rather than as a failure.

**Two layering violations (⑤).** `AGENTS.md` states that `Domain/` imports Foundation only and that
crypto lives in `Data/` behind the crypto service. Two files broke both:

- `AccountFingerprintPhrase` — `import CryptoKit` in `Domain/`, for `SHA256` and `HMAC<SHA256>`. Its
  only production caller was already `Data/UseCases/GetAccountFingerprintUseCaseImpl`, so it moved to
  `Data/Crypto/`. The type is unchanged; the move is the fix.
- `GeneratorHistory` — `import Combine` in `Domain/`, solely to be an `ObservableObject`. Its observers
  are all presentation (`PasswordGeneratorViewModel`, `EditFieldRow` via the environment), so it moved
  to `Presentation/Vault/Edit/`.

Both test files moved with their subjects, so the test tree mirrors the source tree as it did before.

**Unworded data-layer errors (⑧, the reachable part).** Four enums — `AttachmentCryptoError`,
`EncStringError`, `KeychainError`, `IdentityTokenError` — now answer `localizedDescription` with a
sentence. The reason is not theoretical: the attachment screens interpolate the error into their own
localised message (`L("Upload failed: %@", error.localizedDescription)`), so the user got a correct
Chinese wrapper around an English type name and a number. `DataErrorWordingTests` locks it.

**One new permanent check.** `testDataLayerErrorStringsAreTranslatedNotEchoed` reads the `zh-Hans`
table out of the bundle and asserts each of these sentences is present *and differs from its key*.
`AGENTS.md` names the failure: a key missing from one table renders as the key itself, so Chinese
silently reads as English — and because the key **is** the English sentence, "the key exists" is not
enough. This is the only mechanical guard the repository has against that, and it is the one thing in
this change that keeps working after the change is archived.

## What this change deliberately does not do

- **The two deprecated API calls** (`SecTrustGetCertificateAtIndex` in `ServerTrustDelegate`,
  `String(cString:)` in `SSHAgentPeerProcess`). Deprecation is not a defect: both work, and the first
  is inside TLS trust evaluation, where a mechanical swap is a behaviour change in the security path
  and deserves its own pass with the pinning tests in view.
- **`CipherMapperError` and `AttachmentMapperError`** stay unworded. Both are caught where they are
  thrown and mapped to a type that is worded, so wording them would be text no one can reach.
- **The 12 sites that display `error.localizedDescription` directly** stay as they are. That is the
  right choice in most of them — the server's own 401 body is what diagnosed the login failure in this
  session, and a generic "something went wrong" would have hidden it. The fix for an unworded error
  arriving there is to word the error, which is what this change does, not to stop showing it.
- **The performance items ④** — `KeychainService`'s whole-store read-modify-write per key,
  `AuthRepositoryImpl` being `@MainActor`, the keychain read during `AppContainer.init`. Deferred by
  the reviewer at the time, and they are one change of their own with a real risk surface.
- **The two `TODO`s in `VaultRepositoryImpl`** (biometric re-auth before an encrypt-and-send, and the
  offline write-ahead queue). Both are unfinished features, not bugs.

## Impact

- 2 files moved between layers (contents unchanged), 1 new file (`ISO8601WireDate.swift`), 2 dead
  declarations deleted, 4 enums extended, 5 warning sites corrected.
- `project.pbxproj`: one new file registered, two file references re-parented, Sources phase unchanged
  in size.
- 17 new keys in **both** `en.lproj` and `zh-Hans.lproj`; parity checked mechanically and now partly
  enforced by a test.
- 1 new test file, 6 tests.
- No behaviour change beyond the text of error messages that were previously unreadable.
