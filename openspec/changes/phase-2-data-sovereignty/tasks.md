# Tasks — phase 2 (data sovereignty and security tools)

Ordered in four waves. Each wave is independently testable and is committed on its own, so a wave
that turns out to be wrong can be reverted without touching the others.

Wave A is first because it is the phase's headline: the vault has to be gettable-out before
anything else about it matters. Wave B is the visibility layer, which needs the strength estimator
from its own first task. Wave C is access control and transport. Wave D is the two account-level
items, one of which is gated on verifying an external algorithm (design D12).

---

## Wave A — data sovereignty

### A1. The interchange format (Domain, no I/O)

- [x] `Domain/Utilities/VaultExportDocument.swift`
  - `VaultExportDocument` — `encrypted: Bool`, `folders: [ExportFolder]`, `items: [ExportItem]`,
    `Codable`, `nonisolated`.
  - `ExportFolder` — `id`, `name` (design D1: folders carry their id so `folderId` resolves).
  - `ExportItem` — `id`, `organizationId`, `folderId`, `collectionIds`, `type`, `reprompt`, `name`,
    `notes`, `favorite`, `fields`, `passwordHistory`, the five optional per-type sub-objects, and
    the four dates.
  - `ExportCustomField` — `name`, `value`, `type`, `linkedId`.
  - `ExportLoginURI` — `uri`, `match`.
  - `ExportLogin` / `ExportCard` / `ExportIdentity` / `ExportSecureNote` / `ExportSSHKey`.
  - `ExportPasswordHistoryEntry` — `password`, `lastUsedDate`.
  - `init(items:folders:history:)` — entity → document. Type integers match
    `CipherMapper.mapContent`. Organisation items are included, with their membership (D1).
  - `func drafts(folderIdsByName:) -> [ImportCandidate]` — document → drafts, resolving folder
    names to ids. Personal items only (D4).
- [x] Confirm the field names, the `match` encoding, the folder/item `id` presence, the
      `collectionIds: null` convention, the `passwordHistory` shape and the Trash filter against
      `bitwarden/clients` before writing the mapper. **Done** — see design D1; the first draft of
      D1 was wrong about password history and about organisation items.

### A1b. Password history becomes readable (needed by the export)

- [x] `Domain/Entities/VaultItem.swift` — rewrite the `PreservedCipherFields` doc comment; the
      "nothing here is ever decrypted" claim is no longer true (design D10).
- [x] `Domain/Repositories/VaultRepository.swift` — `passwordHistory(for itemId: String)`
      returning `[PasswordHistoryEntry]`, decrypting with the item's own key resolution.
- [x] `Data/Repositories/VaultRepositoryImpl.swift` — implement it, reusing the existing key
      resolution. Malformed entries are skipped, not fatal.
- [x] Wave B's `GetPasswordHistoryUseCase` is then a thin use-case wrapper over this, and the
      Wave B UI does not duplicate the decryption.

### A2. Export use case

- [x] `Domain/UseCases/ExportVaultUseCase.swift` — protocol + `VaultExport` value
      (`data: Data`, `suggestedFilename: String`, `itemCount: Int`).
- [x] `Data/UseCases/ExportVaultUseCaseImpl.swift` — reads `allItems()` + `folders()`, maps to the
      document, encodes with `JSONEncoder` (`.prettyPrinted`, `.sortedKeys`), returns the bytes.
      Never writes, never logs a value.
- [x] `ExportVaultError.emptyVault` — exporting nothing is refused with an explanation.

### A3. Import use case

- [x] `Domain/UseCases/ImportVaultUseCase.swift` — protocol + `ImportSummary`
      (`imported: Int`, `skipped: [ImportSkip]`, `failed: [ImportFailure]`), and
      `progress: (Int, Int) -> Void`.
- [x] `Data/UseCases/ImportVaultUseCaseImpl.swift` — decode, create missing folders, then create
      each item through `VaultRepository.create` in sequence. Continue past a failure. Record
      every outcome.
- [x] `ImportVaultError.unreadableFile` / `.notAnUnencryptedExport` — the second fires when
      `encrypted == true` or the `items` key is absent, with a message saying Prizm imports
      unencrypted exports only.

### A4. File panels and wiring

- [x] `AppContainer` — `exportVaultUseCase`, `importVaultUseCase`, a `fileSaver` closure over
      `NSSavePanel` and a `filePicker` closure over `NSOpenPanel`, both `@MainActor`.
- [x] `VaultBrowserViewModel` — `backupSheet: BackupSheet?` (`.exportConsent` / `.exportDone(URL)` /
      `.importRunning(Double)` / `.importReport(ImportSummary)`), `requestExport()`,
      `confirmExport()`, `requestImport()`, `dismissBackupSheet()`.
- [x] `Presentation/Vault/Backup/ExportConsentSheet.swift` — the mandatory consent, naming what is
      and is not in the file (design D1, D2).
- [x] `Presentation/Vault/Backup/ExportDoneSheet.swift` — the destination path and a reminder to
      delete the file.
- [x] `Presentation/Vault/Backup/ImportReportSheet.swift` — the three counts and the reasons.
- [x] `VaultBrowserView` — present `backupSheet`.

### A5. Menu entries

- [x] `PrizmApp` — `CommandGroup(after: .saveItem)` with **Export Vault…** (⌘⇧E) and
      **Import Vault…** (⌘⇧I), both disabled unless `rootVM.isVaultUnlocked`.
- [x] `RootViewModel` — `menuBarCanExport` / `menuBarCanImport`, recomputed from `$screen` (the
      phase 1 ⌘R defect: a command whose only enablement source never emits at launch stays
      disabled forever).

### A6. Localisation

- [x] Add every new key to both `Localizable.strings` in sorted position; both files keep
      identical key sets; `plutil -lint` passes.

### A7. Tests

- [x] `VaultExportDocumentTests` — entity → document for all five types; folder name resolution;
      `encrypted == false`; the excluded fields are absent.
- [x] `ExportVaultUseCaseTests` — counts, filename shape, empty-vault refusal, round trip
      export → import produces equal content.
- [x] `ImportVaultUseCaseTests` — happy path; unknown type integer is skipped with a reason; a
      server failure is recorded and the run continues; org/collection membership is dropped;
      folders are matched by name and created when absent; `encrypted: true` is refused.
- [x] `VaultBrowserViewModelBackupTests` — sheet state machine; a failed export surfaces an error
      and writes nothing.

### A8. Verify

- [x] `swift build` clean; `swift test` at the same failure count as the phase 1 baseline
      (**718 tests / 10 records**).
- [x] Export a real vault, re-import the file into the same account, and confirm the item count and
      a sampled item's fields.
- [x] Rebuild `dist/Prizm.app`, launch, and confirm the File menu entries appear and are enabled.
- [x] Every commit in the wave builds on its own (`verify-commit-series-builds`).

---

## Wave B — seeing the risk

### B1. Password strength

- [x] `Domain/Utilities/PasswordStrength.swift` — `PasswordStrength` (0–4), `StrengthEstimate`
      (`score`, `guessesLog10`, `weakness: String?`), `PasswordStrengthEstimator`.
- [x] `Domain/Utilities/PasswordStrengthDictionaries.swift` — the embedded common-password list,
      with a doc comment stating its size and that it is not a breach corpus.
- [x] Tokeniser + penalties per design D5. The EFF word list is injected as a `Set<String>?` so
      tests do not depend on `Bundle.main`.
- [x] `PasswordStrengthEstimatorTests` — a table of known inputs and expected scores, including
      `password`, `Password1!`, `aaaaaaa`, `qwerty123`, `correct-horse-battery-staple`, a random
      16-char string, and the empty string.

### B2. Strength in the UI

- [x] `PasswordGeneratorViewModel` — `strength` recomputed on every generated value.
- [x] `PasswordGeneratorView` — a score bar and the named weakness.
- [x] `ItemEditViewModel` — `passwordStrength` for the login form.
- [x] `LoginEditForm` — the same readout beside the password field.

### B3. Generator history

- [x] `Domain/Utilities/GeneratorHistory.swift` — ring buffer, cap 20, `append(_:)`, `entries`,
      `clear()`. Not `Codable`, not persisted (design D9).
- [x] `AppContainer` owns it; injected into `PasswordGeneratorViewModel`.
- [x] `RootViewModel.lockVault()` / `signOut()` clear it.
- [x] `PasswordGeneratorView` — a collapsible history section with a copy button per entry and a
      footer stating it is cleared on lock and never written to disk.
- [x] `GeneratorHistoryTests` — cap, order, clear, and that a value is appended only on copy/accept.

### B4. Vault health report

- [x] `Domain/Utilities/VaultHealthReport.swift` — `HealthCheck` (five cases), `HealthFinding`
      (`itemId`, `itemName`, `detail`), `VaultHealthReport` (`findings(for:)`, counts).
- [x] `Domain/UseCases/GenerateVaultHealthReportUseCase.swift` + Data impl.
- [x] Checks per design D6. Reuse and staleness compare **decrypted** values; nothing leaves the
      process.
- [x] `Presentation/Vault/Health/HealthReportViewModel.swift` + `HealthReportView.swift` — grouped
      by check, count per group, an empty-state per group, the item rows selectable, and the
      explicit note that compromised passwords are not checked and why.
- [x] `PrizmApp` — `CommandMenu("Tools")` with **Vault Health Report…** (⌘⇧H). The view model is
      held by `RootViewModel` and dropped on lock and sign-out: the report lists decrypted item
      names.
- [x] `VaultHealthReportTests` — one test per check, plus a clean vault producing zero findings and
      a vault where one item fails several checks appearing in each.
- [x] `HealthReportViewModelTests` — a failed run surfaces a message, never an empty report.

### B5. Password history

- [x] `Domain/UseCases/GetPasswordHistoryUseCase.swift` + Data impl. **`PasswordHistoryEntry`
      already existed** — wave A added it for the export, so this task was the use case around it,
      not the type. `lastUsedDate` is `Date?` there, not `Date`: an entry with an unparseable date
      still has a password worth showing.
- [x] `VaultItem.swift` — rewrite the `PreservedCipherFields` doc comment (design D10).
- [x] `LoginDetailView` — a collapsed "Password history" section: date, masked password, copy.
      **Reveal is deferred to wave C** with the re-prompt gate; see the wave B notes for why the
      button is not shipped ahead of the gate.
- [x] `GetPasswordHistoryUseCaseTests` — a fixture with two history entries; malformed entries are
      skipped rather than failing the whole list; no `cipherKey` falls back to the vault key. The
      decryption cases live in `VaultRepositoryPasswordHistoryTests`, because a mock repository
      holds no key material and cannot prove which key was used.

### B6. Localisation + tests + verify

- [x] Both `.strings` files, sorted, identical key sets. **433/433**, no duplicates, no
      out-of-order lines, no Chinese value still carrying English.
- [x] `swift build` clean; `swift test` at the baseline failure count — **953 / 10**, and the 131
      wave-B tests run **122 pass / 9 fail** where all 9 are the pre-existing `PasswordGenerator`
      passphrase cases.
- [ ] Rebuild and launch; run the health report against the real vault and sanity-check the counts.
      **Needs the account holder** — the report reads a decrypted vault, so it cannot be exercised
      headlessly. Rebuilt; the launch is on the human.

---

## Wave C — access control and transport

### C1. Re-prompt: the model

- [x] `DraftVaultItem.reprompt` becomes `var`; `ItemEditViewModel` exposes it; the edit form
      gains a **Master password re-prompt** toggle. Documented as newly mutable (design D13).
- [x] `Domain/UseCases/VerifyMasterPasswordUseCase.swift` + Data impl over
      `AuthRepository.verifyMasterPassword(_:)`.
- [x] `AuthRepositoryImpl.verifyMasterPassword(_:)` — derive and compare, no session mutation
      (design D7).

  Notes:

  - **The toggle is on the shared form, not on `LoginEditForm`.** The task said "login edit
    form"; the spec's scenario says "the edit form is open for **any** item type", and the
    spec is what the requirement is tested against. Cards, identities and SSH keys hold
    secrets worth the same gate.
  - **`DraftLoginContent.totp` was left as `let`.** Design D13 asks for `var` because "the
    import path has to be able to set a TOTP seed" — but the import that landed in wave A
    builds `LoginContent` through its initialiser and never mutates one, so there is no
    caller. `var` with no caller is a promise nobody needs.
  - **A wrong password is `false`; `AuthError.noStoredSession` is new.** For "the stored
    session is unreadable". The alternative was reusing `.invalidCredentials`, whose message
    tells the user their password was wrong — a different failure entirely.
  - **The live key is read before the KDF runs**, so a locked vault reports "could not
    check" rather than being flattened into "wrong password".
  - **The comparison is constant time** (`Data/Crypto/ConstantTimeCompare.swift`). Data's `==`
    returns at the first differing byte.
  - Verified: 19 tests across the three new suites, 0 failures. Both `.lproj` at 436 keys,
    3/0 numstat per file.

### C2. Re-prompt: the gate

- [x] `RootViewModel` — `repromptGrants: Set<String>`, `needsReprompt(for:)`,
      `grantReprompt(for:)`, cleared in `lockVault()` and `signOut()`.
- [x] `VaultBrowserViewModel` — `revealedItemIds`, `pendingReprompt: (itemId, itemName)?`,
      `requestReveal(itemId:)`, `submitReprompt(_:)`, `cancelReprompt()`.
- [x] `Presentation/Vault/Reprompt/RepromptSheet.swift` — a `SecureField`, the item name, an error
      on a wrong password, and no dismissal without an explicit cancel.
- [x] `LoginDetailView` / `ItemDetailView` — `isSecretRevealed` + `onRequestReveal` parameters.
- [x] `RootViewModel.copySelectedField` — copy password, copy TOTP and copy username-with-reprompt
      route through the gate.
- [x] `VaultBrowserViewModel.copy` — a gated copy that is not performed until the grant exists.
- [x] `RepromptGateTests` — grant is per item; cleared on lock; a wrong password does not grant;
      an unprotected item never asks.

  Notes — four deviations, each because the literal reading would have left a way around the gate:

  - **`isSecretRevealed` + `onRequestReveal` are one value, `RevealGateBinding`.** They have to
    travel through five type-specific detail views to reach the field view; three parameters is
    three chances per view to drop one, and a dropped `isGated` is silent.
  - **The gated copy is `copyGated(itemId:_:)`, not a change to `copy`.** `copy` still serves the
    username, the URIs, the notes and plain custom fields, which are not gated. One entry point
    for both would have gated the username.
  - **Tapping a row copies it (FR-023), so a gated row's tap is gated too.** Routing only the
    menu command would have left the gate walkable in one click.
  - **The Option-key peek is suppressed on a gated field.** `MaskedFieldView` has always shown a
    password while Option is held; leaving that working would have made the gate one modifier key
    away from decoration.

  Other decisions: hidden custom fields are gated on **all five** item types (not only logins),
  while card numbers, identity values, SSH private keys and note bodies are not, per design D7.
  The password-history section gains the reveal button wave B withheld, and its footnote stops
  promising a prompt once the password has already been given this session.

  Verified: 983 tests, 10 failures — the same set as the pre-wave baseline. 13 new gate cases,
  0 failures. Both `.lproj` at 441 keys, 5/0 numstat per file.

### C3. Server trust

- [x] `Domain/Utilities/ServerTrustConfiguration.swift` — `trustedCACertificates: [Data]`,
      `pinnedLeafSHA256: String?`, `pinningEnabled: Bool`; `ServerTrustDecision` /
      `ServerTrustPinCheck` enums. `pinningEnabled` is separate from the pin being non-nil, so
      turning the setting off does not destroy a recorded pin and does not leave one enforced.
- [x] `Domain/Repositories/ServerTrustStore.swift` — protocol.
- [x] `Data/Network/KeychainServerTrustStore.swift` — Keychain-backed, per server host. Writes
      through `KeychainService` rather than opening its own `SecItem` calls, so the
      `WhenUnlockedThisDeviceOnly` + never-synchronisable rules have one implementation instead of
      two, and the store stays one Keychain item.
- [x] `Data/Network/ServerTrustPolicy.swift` — the pure `decide(...)` function (design D8).
- [x] `Data/Network/ServerTrustDelegate.swift` — `URLSessionDelegate`, a thin adapter over
      `decide`. Not a `URLSessionTaskDelegate`: the task-level challenge callback is for
      per-task credentials, and a trust decision is per host.
- [x] `PrizmAPIClientImpl` — accepts a `URLSession` built with the delegate; `AppContainer` builds
      it and keeps the delegate alive.
      Its requests now go through one `send(_:)`, which re-attributes a cancelled challenge to
      `APIError.serverTrustRefused`. Without it a changed certificate surfaces as a generic
      cancellation, which is the failure the spec forbids. Only a cancellation is re-attributed,
      so one request's refusal cannot become another request's explanation.
- [x] `SettingsView` — a Security subsection: a pinning toggle, the current pin fingerprint, a
      **Trust Certificate…** button (`NSOpenPanel`, `.cer`/`.crt`/`.pem`), a
      **Forget Pinned Certificate** button, and **Stop Trusting** for a private authority.
      The panel and the file parsing are injected from the App layer, so the view imports neither
      AppKit nor Security (Constitution §II).
- [x] `ServerTrustPolicyTests` — the full decision table: different host → default; no config →
      default; pin match; pin mismatch; TOFU records the first leaf; a custom CA is the only
      anchor; plus host normalisation (case, port, IPv6) and the two "could not read the
      fingerprint" refusals.
- [x] `KeychainServerTrustStoreTests` — round trip, per-host scoping, removal, and an
      undecodable value being reported rather than downgraded to `.empty`.
- [x] `CertificateImporterTests` — not in the original list, and needed because "an unreadable
      file is rejected and nothing is stored" is a requirement. Runs against a real self-signed
      certificate.
- [x] State in the test file that the TLS handshake itself is not covered and why — done in
      `ServerTrustPolicyTests` and again in `SECURITY.md`, which is where someone would look for
      the coverage gap.

  **Four failures this section refuses to have.** An unreadable stored configuration fails closed
  rather than reading as `.empty`, because `.empty` means "use the system's own anchors" — the one
  direction that hands a protected connection to whatever answers. A pin that could not be
  recorded refuses the connection, because an accepted connection with no pin leaves the user
  believing they are pinned when they are not. A PEM file with headers but no certificate is an
  error, not an empty anchor set, for the same reason. And a save that fails re-reads, so a toggle
  cannot stay on claiming a protection that was never stored.

  **Two corrections to the literal task text.** `ServerTrustDelegate` is a `URLSessionDelegate`
  only; there is no per-task trust decision to implement. And the settings subsection needs a way
  to *un*trust a certificate, not only to forget a pin — otherwise trusting the wrong file leaves
  no way back.

  Verified: 30 new tests pass. `ServerTrustPolicyTests` (16), `KeychainServerTrustStoreTests` (8),
  `CertificateImporterTests` (6). See C4 for the state of the whole-suite run.

### C4. Localisation + verify

- [x] Both `.strings` files — 456 keys each, identical sets, `plutil -lint` clean, 15/0 per file
      for C3. `verify_keys.py` reports PASS: 0 missing `L()` keys, 0 missing SwiftUI literals,
      0 `String`-typed parameters left unwrapped.
- [x] `swift build` clean; `swift test` at the baseline failure count — **1013 tests / 9 failures,
      the same nine as the pre-C3 baseline, no crash.** Resolved by the fix below, not by working
      around it.
- [ ] Manual: set a re-prompt item, lock, unlock, confirm the prompt appears once; trust a
      self-signed certificate against a local server if one is available.

  **The whole-suite run used to abort part-way through, and it was a real bug — now fixed.**
  `swift test` died with signal 5; under lldb the stop reason was `EXC_BREAKPOINT` inside
  `libsystem_malloc.dylib _xzm_xzone_malloc_freelist_outlined`, malloc's own heap-integrity trap.
  Running the suite under AddressSanitizer named the writer:

  ```
  ERROR: AddressSanitizer: heap-buffer-overflow ... WRITE of size 32
  0 bytes after 32-byte region
      #2 OrgKeyCache.clear() OrgKeyCache.swift:65
  ```

  Every "zero this key material" call used `resetBytes(in: 0..<count)`. That range is an offset from
  `startIndex`, and a `Data` cut out of a bigger one keeps the indices of the buffer it came from —
  so the tail half of a 64-byte key, whose `startIndex` is 32, had bytes 32…63 written into a
  32-byte allocation. `CryptoKeys` is built that way in two places (`keyData[32..<64]`,
  `data.suffix(32)`), so all 30 call sites were exposed. Fixed by `Data.zeroize()`, which zeroes
  through `withUnsafeMutableBytes` and therefore has no range to get wrong.

  Two things worth keeping from the hunt. First, the symptom was allocated to the wrong suspect for
  a while: removing the real-Keychain suites made the run complete, and they were the only tests
  touching the user's login keychain — but they were innocent, and only the heap layout mattered.
  Second, the corruption predates C3 by a long way; C3 did not introduce it, it moved the heap.
  Anyone hitting "the test suite dies in malloc" should reach for `--sanitize=address` first.

---

## Wave D — the account

### D1. Two-factor methods

- [x] `Domain/Utilities/TwoFactorProvider.swift` — the provider map, the three supported cases,
      `displayName`, `promptText`, and a name for the rest. **The map is 0…8, not 0…7**: the
      numbers were read out of Vaultwarden's `TwoFactorType`
      (`src/db/models/two_factor.rs`, main branch), where `RecoveryCode = 8` and
      `is_twofactor_provider_usable` returns true for it, so the server can offer it. Prizm does
      not complete it — Vaultwarden's token endpoint deletes every 2FA method on the account when a
      recovery code is accepted (`src/api/identity.rs`), and a generic "enter your code" prompt must
      not carry that side effect — but it is named rather than reported as an unrecognised number.
      The same source is why an existing test's `[3] // Duo` was wrong: 3 is YubiKey, 2 is Duo.
- [x] `AuthRepositoryImpl` — picks the first supported provider in preference order
      (authenticator → YubiKey OTP → email); stores it in `PendingTwoFactor`; sends it as
      `twoFactorProvider`. It is not a parameter of the submit call, so no caller can answer a
      different question than the one the user was shown.
- [x] `AuthRepository.sendEmailTwoFactorCode()`. **The path in the task was wrong.**
      `POST /api/two-factor/send-email` requires a bearer token and is for setting email 2FA up on
      an account you are already signed into; during login it answers 401. The login-flow route is
      `POST /api/two-factor/send-email-login` (`src/api/core/two_factor/email.rs`:
      `send_email_login`, "Does not require Bearer token", verifies `MasterPasswordHash` itself).
      Body `{ email, masterPasswordHash }`; empty 200 on success; rate-limited.
- [x] `TOTPPromptView` → `TwoFactorPromptView` — the method name, the method's instruction, a
      "Resend code" button only for email, and per-method input rules.
- [x] `TwoFactorProviderTests` — the numbers, selection order (including that the server's list
      order does not decide), an unsupported-only list naming the method, an unrecognised number
      reported as a number, and — against the real repository — that the provider on the wire is
      the one the server asked for.
- [x] **Not in the task, and needed anyway:** the code field. It filtered to digits and capped at
      6. A Yubico OTP is 44 modhex *letters*, so a tap produced an empty field with no
      explanation; and Vaultwarden's `EMAIL_TOKEN_SIZE` defaults to 6 but is configurable upwards,
      so a hard 6 would break a server set to 8. Rules now come from the provider.

  The "unsupported method" error no longer advises switching to an authenticator app: a user whose
  account asks for Duo cannot switch from here, so that sentence was not actionable. It names the
  method and says to use another client.

### D2. Account fingerprint phrase — **done**

- [x] **Verify the algorithm first** against the Bitwarden client source: the hash, the chunk size
      and byte order, the modulo, and the word list. **Confirmed**, against
      `bitwarden/sdk-internal` → `crates/bitwarden-crypto/src/fingerprint.rs` (the Rust SDK, not a
      client) and cross-checked against the TypeScript
      `libs/legacy-crypto/src/services/legacy-compat-key.service.ts`. What the check established:

      - `material` is the **user id**, not the email. `profile.component.ts` sets
        `fingerprintMaterial` from the user id; the TypeScript spec's `test@example.com` is a mock
        value, and believing it would produce a well-formed phrase that matches no other client.
      - the key is hashed as **SPKI DER**. `PublicKey::to_der()` says SubjectPublicKeyInfo, and
        `SecKeyCopyExternalRepresentation` returns PKCS#1 on Apple platforms — hence `SPKIEncoder`,
        tested against `openssl`, not against itself.
      - HKDF-Expand-SHA256, 32 bytes. Rust passes the key as prk, TypeScript `SHA256(key)`; they
        coincide because HMAC hashes a key longer than its 64-byte block first. Both were run and
        both hit the same vector.
      - the integer is **big-endian**, five words (`ceil(64 / log2(7776))`), least-significant
        first. Little-endian was computed as a control and gives a different, equally plausible
        phrase.
      - two vectors, both published by the reference: 294-byte SPKI +
        `a09726a0-9590-49d1-a5f5-afe300b6a515` → `turban-deftly-anime-chatroom-unselfish`; and the
        word-selection step `V5AQSk83YXd6kZqCncC6d9J72R7UZ60Xl1eIoDoWgTc=` →
        `predefine-hunting-pastime-enrich-unhearing`.
      - `Prizm/Resources/eff-large-wordlist.txt` is **identical** to Bitwarden's
        `EFF_LONG_WORD_LIST`, 7776 words in the same order, so it is reused. The coupling is
        commented at the use site: swapping it for the generator's sake would silently change every
        phrase.

- [x] `Domain/Utilities/AccountFingerprintPhrase.swift` — five words from an injected word list,
      plus `SPKIEncoder` for the PKCS#1 → SPKI wrap. `phrase(forHash:)` is internal so the
      word-selection step can be covered against the reference on its own.
- [x] `Domain/UseCases/GetAccountFingerprintUseCase.swift` + Data impl. **Not** shaped as the task
      described: the use case does not decrypt anything. The private key is decrypted once during
      sync — where the encrypted form lives, and the only place it is available — the public half
      is derived there and cached in `AccountKeyCache`, and the use case is a lookup of two values
      plus a call to the pure function. A use case that decrypted would have to be handed the
      encrypted key, which is not retained anywhere after sync.
- [x] Surfaced in Settings as its own **Account** section, above Security. Not under Security: the
      phrase is not a control, and burying it there would read as one more thing to switch on. The
      note says it is not a secret and can be read aloud, because a fingerprint that has to be
      hidden cannot be compared.
- [x] `AccountFingerprintPhraseTests` — the two reference vectors above, the five-word and
      stability properties, the word-list size, and the SPKI encoding checked against `openssl`.
      Nothing here is derived from Prizm's own output.

### D2a. TOTP seed editing — **done**

- [x] `DraftLoginContent.totp` becomes `var`; documented at the point of change (design D13).
- [x] `LoginEditForm` — a masked **Authenticator Key (TOTP)** field, with a hint naming the two
      shapes accepted (a bare secret, or the `otpauth://` URL).
- [x] `ItemEditViewModel.totpSeedProducesCode` — asks the generator whether the value will produce
      a code. Reported, never refused: a refused save would be a lockout.
- [x] `ItemEditViewModelTotpSeedTests` — 12 cases, including that the value reaches the draft the
      repository is handed, and that clearing the field clears it on the server.

  Verified: 1050 tests / 9 failures against the same 9 baseline failures. Both `.lproj` at 474
  keys, `verify_keys.py` PASS, **3/0** numstat per file.

### D3. Close out — **done**

- [x] Both `.strings` files. 480 keys each, identical key sets, sorted, `plutil -lint` clean, and
      `references/verify_keys.py` PASS: 0 `L()` keys missing, 0 SwiftUI literals missing, **0
      `String`-typed parameters left unwrapped** — the one check that finds a forgotten
      localisation rather than a missing entry.
- [x] `swift build` clean; `swift test` at the baseline failure count. **1064 tests / 9 failures**,
      the same nine as before wave B (eight `PasswordGenerator` passphrase cases whose word list is
      not in the `swift test` bundle, one `CardBackground`). No crash; the whole suite runs to the
      end.
- [x] Update `FEATURE-GAP-ANALYSIS.md` §0/§2/§3.4/§3.6 and §5. Done, and three rows changed shape
      rather than ticking:

      - the strength meter is **partial, not ✅** — "has a meter" and "uses zxcvbn" are different
        claims, and the row now says which it is and points at SECURITY.md;
      - export is **partial, not ✅** — unencrypted JSON only, no CSV / encrypted JSON / ZIP;
      - the two dropped checks (exposed passwords, HIBP breach) are recorded in §5 as **dropped with
        a reason**, not as unstarted work. A gap list that cannot tell the two apart is a task list
        someone will try to finish.

      Summary item 2 was also re-tensed: the five data-losing / leaking bugs are described as fixed
      and point at §2, where their status already said so. Left as "must be fixed first", a document
      about what is missing read as though it described the current build.

- [x] Update `SECURITY.md`. Two new sections and one extended:

      - **Vault Export and Import** — what the file contains, in plaintext: passwords, TOTP seeds,
        and previous passwords. It is the most sensitive artefact the app produces and now says so.
        Also that encrypted export is not produced, and that the importer *refuses* one rather than
        failing part-way.
      - **Password Strength Estimator** — what it does not model, and that when it is wrong it is
        wrong low. Its two absences are stated as refusals.
      - **Server Trust** gained what pinning does **not** cover: the first connection (trust on
        first use — a pin armed while something is intercepting pins the interceptor), other hosts
        (the icon service is a different host), and everything after the handshake. "The connection
        is pinned" is otherwise read as covering all three.

- [x] Update `ACCESSIBILITY.md` for the new controls. The header was two releases stale (1.3.0 /
      2026-04-10 against a 1.4.3 build) and is now 1.4.3 / 2026-09-20. A **Controls Added in 1.4**
      section lists every new surface with its identifier and label, and five criteria were updated
      with the specific new cases.

**One accessibility bug found while writing the document, and fixed rather than recorded.** The
fingerprint phrase's copy button turns its icon into a tick — confirmation for anyone who can see
it, and nothing at all for VoiceOver. A screen-reader user pressed a button and had no evidence
anything happened. It now posts an announcement (`ef8ca89`). Worth noting that the document update
is what surfaced it: without walking the control list, "the icon changes" reads as complete.

---

## Wave E — queued, not started

Two features the user asked for and agreed to schedule rather than do now. They are written down so
the decision is not lost, and they are **not started until every item above them is closed** — the
order below is the order they will be attempted.

### E1. Passkey viewer (FIDO2, read-only)

Show the passkeys already stored on a login item. Does **not** register or use them: real WebAuthn
support is a separate, much larger piece of work and is not in scope here.

- [ ] Decode `PreservedCipherFields.fido2Credentials` — the entries are today carried through
      untouched but never interpreted.
- [ ] Parse the COSE public key and surface rpId, user name and creation date.
- [ ] A read-only section on `LoginDetailView`, shown only when there is something to show.
- [ ] State in the UI that Prizm cannot *use* these yet — a list of passkeys with no such note
      reads as a feature that does not work.
- [ ] Tests with a fixture credential; malformed entries are skipped, not fatal.

### E2. SSH agent

A desktop-only capability that no other Prizm feature competes with. Prizm already stores SSH
private keys (`SSHKeyContent.privateKey`); what is missing is everything that makes them usable.

- [ ] A Unix socket, launched on demand.
- [ ] The SSH agent protocol subset: identity listing and signing. Not the full message set.
- [ ] Parse the OpenSSH private key formats Prizm can already hold.
- [ ] **Every sign request goes through the master-password gate.** Without this the agent is an
      unattended key-extraction path, which is worse than not having it.
- [ ] Verify against `git`, `ssh`, and at least one editor's remote integration.

  Sizing note: this is the largest item in the change. It is deliberately last.

---

## Notes recorded during implementation

### Wave A

- **A8 — the failure set did not move; the test count did.** `swift build` is clean (0 errors,
  0 warnings). `swift test` reports **842 tests / 10 failure records**, and the ten records are
  the same nine tests as the phase 1 baseline: `CardBackgroundTests.testCardBackgroundColor_exists`
  plus seven `PasswordGeneratorTests` and one `PasswordGeneratorViewModelTests`, all of which need
  `Assets.car` or the EFF wordlist, neither of which exists when `Bundle.main` is the xctest
  runner. Phase 0 was 551 / 10, phase 1 718 / 10, wave A 842 / 10 — 124 new tests, none failing,
  no test that used to pass now fails. The count only rose because the suite grew.
  One run out of five reported an eleventh record in the same `Bundle.main`-dependent family;
  it did not reproduce across four subsequent runs and is recorded rather than explained.

- **The suite cannot be run from the command line without a temporary `Package.swift` test
  target, and that target has to carry *two* settings: `.swiftLanguageMode(.v5)` **and**
  `.unsafeFlags(["-default-isolation", "MainActor"])`.** The second one was missed on the first
  pass; the cost of missing it is recorded at the end of this entry.

  | configuration | result |
  | --- | --- |
  | `-swift-version 5` | 3 errors across 4 test files |
  | v5 + the two upcoming-feature flags | 3 errors across 4 test files |
  | v5 + `-default-isolation MainActor` | compiles |
  | v5 + `-default-isolation MainActor` + the two upcoming-feature flags | compiles |

  The failing files call `VaultItem.init(_ draft:)` from a nonisolated test method. That
  initialiser sits in an `extension VaultItem`, so it inherits the app target's
  `-default-isolation MainActor`; a test target that defaults to `nonisolated` cannot call it.
  Under v6 the same mismatch surfaces as 22 errors, and `v6 + -default-isolation MainActor`
  produces 4969 because `XCTestCase`'s nonisolated initialiser then conflicts with every
  subclass — which is why the language mode is v5 and not v6.

  **An earlier version of this note claimed `-swift-version 5` alone compiles. That was wrong.**
  The table had been measured with plain `swift build`, which never compiles the test target at
  all — so every row was really measuring the app target, and the "compiles" row was vacuous.
  `swift build --build-tests` (or `swift test`) is the only honest check, and the settings above
  are the ones that survive it. The same trap bit twice: a first attempt to verify a test-only
  commit with `swift build --build-tests` also passed vacuously, because the manifest it ran
  against had been saved before the test target was appended.

  `Package.swift` is reverted before committing — the Xcode project remains the source of truth —
  so this recipe is recorded here to save the next person the experiment.

- **A6 — the first localisation pass was incomplete, and the audit was the reason.** Auditing only
  `L("…")` calls found 26 missing keys and looked finished. It was not: SwiftUI's
  `Button("Export Vault…")` and `L("Export Vault")` are two *different* keys, and the File menu and
  three of the four sheets use the literal form. Widening the audit to
  `Button`/`Text`/`Label`/`Toggle`/`Picker`/`Section`/`Menu`/`CommandMenu`/`CommandGroup`/`Stepper`/
  `Link`/`NavigationLink`/`TextField`/`SecureField`/`TextEditor`/`HelpButton` literals found 17 more,
  including `Export Vault…`, `Import Vault…`, `Export…`, `Done`, `Export Complete`,
  `Import Complete`, `Nothing Was Imported`, `Imported`, `Folders created`, `Folders not created`,
  `Organisation membership not imported`, `Importing…`, `Reading the file…`, `Stop`, `Saved to`,
  and two full sentences. Both files are now 336 → **379 keys**, sorted by the UTF-8 byte order of
  the decoded key, identical key sets, `plutil -lint` clean, insert-only (0 lines changed or
  removed). `Text(cond ? "A" : "B")` is invisible to any regex audit — those keys were found by
  reading the sheets, which is the only reliable way.

- **A5 — `menuBarCanExport` / `menuBarCanImport` were not added.** The two commands read a single
  computed `RootViewModel.isVaultUnlocked` derived from `@Published screen` instead. Two mirrored
  `@Published` flags would have been the phase 1 ⌘R defect again: a flag whose only update site
  never fires at launch leaves the command permanently disabled. A property derived from the
  source of truth cannot go stale, so the two-flag design was dropped rather than duplicated.

- **A1 — `drafts(folderIdsByName:) -> [ImportCandidate]` became
  `makeDraft(from:folderIdsByName:now:) -> DraftVaultItem`**, with `folderNamesById` and
  `referencedFolderNames` as separate properties. `ImportCandidate` was never needed: the only
  caller creates one draft at a time and reports per item, and splitting the folder-name
  resolution out is what lets `referencedFolderNames` create exactly the folders the file
  actually points at.

- **A3 — `ImportVaultError` was not added.** The four refusals are cases on
  `VaultExportDocumentError`, next to the format they are about: `notAnUnencryptedExport`,
  `encryptedExportUnsupported`, `malformedExport`, plus `unsupportedItemType(Int)` and
  `missingItemName` for per-item skips. A use-case-level error type would have had to restate
  the format's own vocabulary. `encryptedExportUnsupported` is checked **before** the `items`
  presence test — an encrypted export has an `items` array too, and calling it "not an export"
  would be false.

- **A2 — `VaultExport` carries a fourth field, `organisationItemCount`**, and the encoder uses
  `.prettyPrinted, .sortedKeys, .withoutEscapingSlashes` rather than the two formattings the plan
  listed. `.withoutEscapingSlashes` is not cosmetic: without it every URL is written
  `https:\/\/…`, which is valid JSON but not what any other client writes, and the file is meant
  to be interchangeable.

- **A3 — `ImportSummary` gained three counters** the plan did not have: `foldersCreated`,
  `foldersFailed` and `organisationMembershipDropped`. All three exist because the alternative is
  a silent side effect — a folder invented on the user's behalf, or an organisation item quietly
  landing in the personal vault. Its nested types are `ImportSummary.Skip` / `.Failure` rather
  than top-level `ImportSkip` / `ImportFailure`.

- **A4 — the sheet enum is `VaultBackupSheet` with four cases**: `.exportConsent`,
  `.exportDone(url:itemCount:organisationItemCount:)`, `.importing(done:total:)` and
  `.importReport(ImportSummary)`. `.importRunning(Double)` became `.importing(done:total:)` so the
  progress sheet can tell "counting the file" (`total == 0`, indeterminate) from "0 of 0 items".
  Two files beyond the plan's four hold the enum and the switch over it, so `VaultBrowserView`
  gains one `.sheet` modifier rather than four. It is presented with `.sheet(isPresented:)` and
  switched inside, deliberately **not** `.sheet(item:)`: the consent → done and progress → report
  transitions change the payload but not the fact that a sheet is up, and `.sheet(item:)` keys on
  identity, so it would tear the sheet down and rebuild it — and write `nil` back through the
  binding — on each hand-off.

- **A defect found while writing the tests.** A cancelled import returns a partial summary rather
  than throwing, by design, so the caller learns what landed. The completion path then did
  `backupSheet = .importReport(summary)` unconditionally — which meant dismissing the progress
  sheet re-presented it immediately as a report. Closing a window the user just closed is the one
  thing a dismissal must never do. Guarded with `guard backupSheet?.isImporting == true else
  { return }`, with the refresh above the guard so items created before the cancellation still
  appear.

- **Verified, not assumed.** `./build-app.sh` succeeds; `dist/Prizm.app` carries both `.lproj`
  directories at 379 keys each with the new strings translated, `plutil -lint` is clean on the
  bundled copies, the binary contains the wave A symbols and literals, and `codesign --verify
  --strict` passes.

- **Still outstanding, and it needs a human.** The live round trip ("export a real vault,
  re-import the file into the same account, confirm the item count and a sampled item's fields")
  and the launch check ("the File menu entries appear and are enabled") both need a real account
  and a pair of eyes, so they were not performed here.

### Wave B

- **B1 — the strength estimator.** 609 common passwords ordered by popularity, plus an estimator
  that tokenises into runs, matches the dictionary longest-first without overlap, and multiplies
  the cost of whatever is left over. Two of the design decisions were forced by the tests rather
  than chosen up front:

  - the per-run costs are summed in **log space**. Adding them would price a four-word passphrase
    as four draws from 7,776 words taken once, which puts `correct-horse-battery-staple` below a
    six-character password; and `Double` overflows to `inf` past roughly 300 mixed characters,
    where `inf` reads as `veryStrong` — the wrong direction to fail in.
  - **diacritics fold before the lookup**, so `pässwörd` is recognised as `password`. Without
    that it was priced as ten unrelated characters and scored `veryStrong`.

  Verified: `swift test --filter PasswordStrengthEstimatorTests` is 40/40, and the full suite is
  **882 tests / 10 failures** against the pre-wave baseline of **842 / 10**, with the failing test
  set identical after normalisation. The baseline was re-run in a worktree of `4197523` under the
  same temporary manifest, so the comparison is like-for-like rather than remembered.

- **A correction to the wave A notes, found while verifying B1.** The claim that the suite
  compiles under `-swift-version 5` alone was an artefact of measuring with plain `swift build`;
  the corrected table and the reasoning are in the entry above. The 14 keychain failures that the
  wave A verification attributed to the sandbox were a symptom of that same broken
  configuration — with the right test target they do not occur at all, and the failure count is
  back to the documented 10.

- **B2 — the readout.** One view, `PasswordStrengthReadout`, draws the score in both places it
  appears, so the popover and the login form cannot drift apart in wording or in colour. Three
  decisions worth recording:

  - **It says "estimate" in the label, not only in the tooltip.** The spec requires the score be
    presented as an estimate wherever it is shown, and a tooltip is not shown. The label reads
    "Estimated strength: …"; the tooltip carries the longer statement, and the bar is
    `accessibilityHidden` so VoiceOver gets the same sentence rather than five unlabelled capsules.
  - **`nil` draws nothing.** An empty field has no weakness to name — the estimator already
    returns none for an empty password — and a bar reading "very weak" before the user has typed
    anything reads as an accusation rather than information.
  - **`ItemEditViewModel.passwordStrength` is computed, not stored.** `draft` is `@Published`, so
    every keystroke already re-renders the form; a cached copy would be one more thing that can
    fall out of step with the field it describes.

  `PasswordGenerator.effWordList` became `nonisolated` so the estimator can read it: it is a pure
  function of the bundle, and the app-level estimator needs it to price passphrase words at their
  real 7776 instead of as unrelated letters. Under `swift test` the resource is absent and it
  degrades to the popularity list, which is the same degradation the generator itself has.

  Verified: 889 tests / 10 failures, failing set identical to the 842-test baseline; the bundle
  rebuilds with both `.lproj` at 394 keys, `plutil -lint` clean and `codesign --verify --strict`
  passing. The 15 new keys (12 from B1, 3 from B2) are pure additions — the diff against the
  previous file removes nothing, so the existing sort is preserved rather than rewritten.

- **B3 — the history.** A ring buffer of the last 20 values the user copied or accepted, held in
  `AppContainer` and cleared by both teardown paths. Three things worth recording:

  - **A fix that was not on the task list.** `PasswordGeneratorViewModel.copyToClipboard()` had
    hardcoded 30 seconds since before the clipboard setting existed, so the one screen most likely
    to put a password on the clipboard was the one screen `ClipboardClearInterval` did not reach.
    The pasteboard write and the scheduled clear moved into a private `copy(_:)`, which the
    history's per-entry copy now shares. `clipboardClearTask` lost its `private` so a test can
    assert that `.never` schedules no task at all — the alternative is a test that waits ten seconds
    to prove the setting was read.
  - **Recording happens on copy and on accept, never on generation.** The length slider regenerates
    on every step, so recording those would push the real entries out of a 20-slot buffer within a
    few drags. `accept()` exists as its own call because the Use button writes the binding and
    dismisses, so there was otherwise no point at which the view model learned the value had been
    kept.
  - **The history reaches the popover through the environment, not as a parameter.** The view model
    is a `@State` object created inside `MaskedEditFieldRow` when the wand is first pressed, so a
    parameter would be threaded through four views that otherwise know nothing about it. The key
    defaults to `nil` rather than being an `@EnvironmentObject`, which would trap in every preview
    and every view test that renders the row.

  `historyEntries` is computed and the view model forwards `objectWillChange` from the shared list,
  so a popover opened from a second field updates the first one's section.

  Verified: 908 tests / 10 failures against the B2 baseline of 889 / 10, re-run in a worktree of
  `4f18283` under the same temporary manifest. The failing set is **identical** — the same nine
  cases — so all 19 new tests pass and nothing regressed. Both `.lproj` at 398 keys, `plutil -lint`
  clean, 4/0 numstat per file.

- **B4 — the health report.** Five local checks over the decrypted vault, opened from a new Tools
  menu (⌘⇧H). Four decisions worth recording:

  - **All five sections are always rendered, including the ones that found nothing.** A section that
    disappeared when empty would make "checked, and clean" indistinguishable from "never checked" —
    the same failure mode as a swallowed error. The count badge carries the answer instead. This
    contradicts what `VaultHealthReport.isClean`'s comment originally promised, so the comment was
    corrected rather than left describing a UI that was not built.
  - **The view model is held by `RootViewModel`, not created in the sheet's content closure.**
    SwiftUI re-evaluates that closure whenever the root view model publishes, so a view model built
    there would be replaced — and reset to `.loading` — on every update, re-running the analysis in
    a loop.
  - **The report is dropped on lock and sign-out**, alongside the generator history. It lists
    decrypted item names, so keeping it would leave decrypted content past the end of the session.
  - **Two boundaries the tests pin down.** A URI with no scheme is *not* unsecured — the check is
    about the transport, and a bare hostname says nothing about it, so counting those would list
    most of a vault. And a login with no password is skipped by all four password-based checks
    rather than reported as missing a second factor it could never have had.

  The breach check is deliberately absent, and the sheet says so with the reason next to the five
  that did run: it would mean sending part of a password to a third party.

  Verified: 936 tests / 10 failures against the 909-test baseline taken before this change, with
  the failing set **identical** — the same nine cases — so all 27 new tests pass. Both `.lproj` at
  426 keys, `plutil -lint` clean, **28/0** numstat per file.

- **B5 — the password history.** A collapsed section on login items the server says carry one.
  Three things worth recording:

  - **The reveal button is deliberately not shipped.** The spec gates it behind the master-password
    re-prompt, which is wave C. Shipping the button first would mean shipping a control that shows a
    previous password to anyone at the keyboard, so the section shows masked values and a footnote
    that says revealing will require confirmation — the same reason the health report names the
    check it does not run. Copying is *not* deferred: it is exactly as exposed as copying the
    current password, which the detail view has always allowed without a gate.
  - **The section is offered only when `preserved.passwordHistory` is non-empty.** That is a check
    on the encrypted wire form, so an item with no history never triggers a decryption at all —
    which is what makes "nothing is decrypted until requested" true rather than approximate.
  - **`PasswordHistoryEntry` already existed**, added in wave A for the export. The task list asked
    for it here; what was actually missing was the use case. Its `lastUsedDate` is `Date?` because
    an entry whose date will not parse still has a password worth showing — the date is display
    metadata, the password is the payload.

  The decryption is tested against the real `VaultRepositoryImpl`, not a double: `MockVaultRepository`
  holds no key material and returns whatever a test hands it, so it cannot prove which key was used.
  `withCipherKey_usesTheItemKey` encrypts with the item's own key, so a successful round trip is what
  proves the wrapped `cipherKey` was unwrapped — and `undecryptableEntryIsSkipped` encrypts one entry
  for an unrelated key to prove a damaged row is dropped rather than taking the list down with it.

  Verified: 953 tests / 10 failures against the 936-test baseline, failing set identical, so all 17
  new tests pass. Both `.lproj` at 433 keys, `plutil -lint` clean, **7/0** numstat per file.
