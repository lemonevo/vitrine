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

- [ ] `Domain/Utilities/VaultHealthReport.swift` — `HealthCheck` (five cases), `HealthFinding`
      (`itemId`, `itemName`, `detail`), `VaultHealthReport` (`findings(for:)`, counts).
- [ ] `Domain/UseCases/GenerateVaultHealthReportUseCase.swift` + Data impl.
- [ ] Checks per design D6. Reuse and staleness compare **decrypted** values; nothing leaves the
      process.
- [ ] `Presentation/Vault/Health/HealthReportView.swift` — grouped by check, count per group, an
      empty-state per group, the item rows selectable, and the explicit note that compromised
      passwords are not checked and why.
- [ ] `PrizmApp` — `CommandMenu("Tools")` with **Vault Health Report…** (⌘⇧H).
- [ ] `VaultHealthReportTests` — one test per check, plus a clean vault producing zero findings and
      a vault where one item fails several checks appearing in each.

### B5. Password history

- [ ] `Domain/UseCases/GetPasswordHistoryUseCase.swift` — `PasswordHistoryEntry`
      (`lastUsedDate: Date`, `password: String`).
- [ ] `Data/UseCases/GetPasswordHistoryUseCaseImpl.swift` — decrypts on demand with the item's own
      key resolution; returns newest first; empty when there is none.
- [ ] `VaultItem.swift` — rewrite the `PreservedCipherFields` doc comment (design D10).
- [ ] `LoginDetailView` — a collapsed "Password history" section: date, masked password, reveal,
      copy. Gated by the re-prompt grant (Wave C).
- [ ] `GetPasswordHistoryUseCaseTests` — a fixture with two history entries; malformed entries are
      skipped rather than failing the whole list; no `cipherKey` falls back to the vault key.

### B6. Localisation + tests + verify

- [ ] Both `.strings` files, sorted, identical key sets.
- [ ] `swift build` clean; `swift test` at the baseline failure count.
- [ ] Rebuild and launch; run the health report against the real vault and sanity-check the counts.

---

## Wave C — access control and transport

### C1. Re-prompt: the model

- [ ] `DraftVaultItem.reprompt` becomes `var`; `ItemEditViewModel` exposes it; the login edit form
      gains a **Master password re-prompt** toggle. Documented as newly mutable (design D13).
- [ ] `Domain/UseCases/VerifyMasterPasswordUseCase.swift` + Data impl over
      `AuthRepository.verifyMasterPassword(_:)`.
- [ ] `AuthRepositoryImpl.verifyMasterPassword(_:)` — derive and compare, no session mutation
      (design D7).

### C2. Re-prompt: the gate

- [ ] `RootViewModel` — `repromptGrants: Set<String>`, `needsReprompt(for:)`,
      `grantReprompt(for:)`, cleared in `lockVault()` and `signOut()`.
- [ ] `VaultBrowserViewModel` — `revealedItemIds`, `pendingReprompt: (itemId, itemName)?`,
      `requestReveal(itemId:)`, `submitReprompt(_:)`, `cancelReprompt()`.
- [ ] `Presentation/Vault/Reprompt/RepromptSheet.swift` — a `SecureField`, the item name, an error
      on a wrong password, and no dismissal without an explicit cancel.
- [ ] `LoginDetailView` / `ItemDetailView` — `isSecretRevealed` + `onRequestReveal` parameters.
- [ ] `RootViewModel.copySelectedField` — copy password, copy TOTP and copy username-with-reprompt
      route through the gate.
- [ ] `VaultBrowserViewModel.copy` — a gated copy that is not performed until the grant exists.
- [ ] `RepromptGateTests` — grant is per item; cleared on lock; a wrong password does not grant;
      an unprotected item never asks.

### C3. Server trust

- [ ] `Domain/Utilities/ServerTrustConfiguration.swift` — `trustedCACertificates: [Data]`,
      `pinnedLeafSHA256: String?`, `pinningEnabled: Bool`; `ServerTrustDecision` enum.
- [ ] `Domain/Repositories/ServerTrustStore.swift` — protocol.
- [ ] `Data/Network/KeychainServerTrustStore.swift` — Keychain-backed, per server host,
      `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never synchronisable.
- [ ] `Data/Network/ServerTrustPolicy.swift` — the pure `decide(...)` function (design D8).
- [ ] `Data/Network/ServerTrustDelegate.swift` — `URLSessionDelegate` + `URLSessionTaskDelegate`,
      a thin adapter over `decide`.
- [ ] `PrizmAPIClientImpl` — accept a `URLSession` built with the delegate; `AppContainer` builds
      it and keeps the delegate alive.
- [ ] `SettingsView` — a Security subsection: a pinning toggle, the current pin fingerprint, a
      **Trust a certificate…** button (`NSOpenPanel` for `.cer`/`.crt`/`.pem`), and a
      **Forget pinned certificate** button.
- [ ] `ServerTrustPolicyTests` — the full decision table: different host → default; no config →
      default; pin match; pin mismatch; TOFU records the first leaf; a custom CA is the only
      anchor.
- [ ] `KeychainServerTrustStoreTests` — round trip, per-host scoping, removal.
- [ ] State in the test file that the TLS handshake itself is not covered and why.

### C4. Localisation + verify

- [ ] Both `.strings` files.
- [ ] `swift build` clean; `swift test` at the baseline failure count.
- [ ] Manual: set a re-prompt item, lock, unlock, confirm the prompt appears once; trust a
      self-signed certificate against a local server if one is available.

---

## Wave D — the account

### D1. Two-factor methods

- [ ] `Domain/Utilities/TwoFactorProvider.swift` — the provider map (0, 1, 2, 3, 4, 5, 6, 7), the
      three supported cases, `displayName`, `promptText`, and `unsupportedName` for the rest.
- [ ] `AuthRepositoryImpl` — pick the first supported provider in preference order
      (TOTP → YubiKey OTP → Email); store it in `PendingTwoFactor`; send it as
      `twoFactorProvider` on the second request.
- [ ] `AuthRepository.sendEmailTwoFactorCode()` — `POST /api/two-factor/send-email`, with the
      exact path confirmed against Vaultwarden before writing it.
- [ ] `TOTPPromptView` → `TwoFactorPromptView` — the method-specific label, a "Resend code" button
      only for Email, and a correct name for an unsupported method.
- [ ] `TwoFactorProviderTests` — selection order; an unsupported-only list names the method;
      `twoFactorProvider` matches the code that was entered.

### D2. Account fingerprint phrase

- [ ] **Verify the algorithm first** against the Bitwarden client source: the hash, the chunk size
      and byte order, the modulo, and the word list. If it cannot be confirmed, stop here and
      record why in `FEATURE-GAP-ANALYSIS.md` (design D12).
- [ ] `Domain/Utilities/AccountFingerprintPhrase.swift` — `[UInt8]` → five words, from an injected
      word list.
- [ ] `Domain/UseCases/GetAccountFingerprintPhraseUseCase.swift` + Data impl — decrypt the private
      key, derive the public key, hash, map.
- [ ] Surface it in Settings ▸ Security with the explanation that it must match the other client's.
- [ ] `AccountFingerprintPhraseTests` — a known-answer vector taken from the reference
      implementation, not from Prizm's own output.

### D3. Close out

- [ ] Both `.strings` files.
- [ ] `swift build` clean; `swift test` at the baseline failure count.
- [ ] Update `FEATURE-GAP-ANALYSIS.md` §3.4/§3.6 and §5: phase 2 complete, with anything dropped
      and the reason.
- [ ] Update `SECURITY.md`: what the export contains, what pinning does and does not cover, and
      the strength estimator's limits.
- [ ] Update `ACCESSIBILITY.md` for the new controls.

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
