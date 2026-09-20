## Why

`FEATURE-GAP-ANALYSIS.md` §5 phase 2 is "数据主权与安全工具". Phase 0 made the client safe to
trust with a real vault; phase 1 made it stop feeling like a demo to use every day. Phase 2 is
about the two things that follow: **the vault has to be gettable-out**, and **the protections the
data already claims to have have to actually work**.

The complaints, in the order a user meets them:

1. **The vault cannot be exported.** There is no escape hatch and no backup. A user who wants to
   leave, or who wants a copy before a risky operation, has to open the official client to get
   their own data out of their own server. This is the single largest remaining gap.
2. **The vault cannot be imported.** Moving in means re-typing every item, so nobody moves in.
3. **You cannot see what is weak.** 86 items and no answer to "which of these is the problem?".
   Reused passwords, `http://` sites and passwords that have not changed in five years are all
   invisible.
4. **There is no strength meter.** The generator can produce a password but cannot say whether the
   one you typed is any good, and the edit form cannot either.
5. **`reprompt` is carried through every save and honoured by nothing.** Phase 0 made the field
   round-trip so an edit cannot delete it. The data therefore *looks* protected — and the app
   never asks for the master password. A protection that exists only in the wire format is worse
   than one that is absent, because the user cannot tell.
6. **Self-signed servers cannot be used.** `FEATURE-GAP-ANALYSIS.md` §3.6: a self-hosted deployment
   with a private CA is the common case for the users this client is for, and there is no way to
   trust one.
7. **Generator output is lost.** Generate, copy, close the sheet by accident — start again.
8. **Password history is carried through every save and shown by nothing.** Same shape as
   re-prompt: the data survives, the feature does not exist.
9. **Only TOTP two-factor is supported.** Email and YubiKey are named "unsupported" generically
   rather than being offered, and the message does not even say which method the server wanted.
10. **There is no way to check the server's identity.** Two devices, same account, no way to
    confirm they are talking to the same server.

## What Changes

- **Export.** File ▸ Export Vault… (⌘⇧E) writes the whole vault — every item type, folders, custom
  fields, notes, TOTP seeds — to Bitwarden's own **unencrypted JSON** format. A mandatory consent
  sheet states that the file is plaintext. The file is written `0600`.
- **Import.** File ▸ Import Vault… (⌘⇧I) reads that same format back. Additive only: nothing is
  deleted or overwritten. Folders are matched by name and created when missing. The result is
  reported per outcome (imported / skipped / failed) rather than aborting on the first error.
- **Vault health report.** Tools ▸ Vault Health Report… (⌘⇧H) runs five purely-local checks —
  weak, reused, stale, unsecured-site and missing-TOTP — and lists the offending items, each one
  selectable so the user can go and fix it. No network, no third party.
- **Password strength.** A local, pattern-aware estimator scores any password 0–4 and names the
  single biggest weakness. Used by the generator and by the edit form.
- **Master password re-prompt.** `reprompt` becomes editable per item and is **enforced**: revealing
  or copying a protected secret asks for the master password first, once per unlock session.
- **Server certificate trust.** A custom CA can be trusted for the user's own server, and the
  server's certificate can be pinned, so a changed certificate is refused instead of silently
  accepted.
- **Generator history.** The last 20 generated values, in memory only, cleared on lock and
  sign-out.
- **Password history.** The previous passwords the server has been keeping are finally displayed,
  behind the same gate as the current one.
- **Two-factor methods.** Email and YubiKey OTP join TOTP; the remaining methods are named
  correctly instead of being reported as a generic "unsupported".
- **Account fingerprint phrase.** The five-word phrase derived from the account's public key, so
  the user can confirm two clients are talking to the same account.

## Capabilities

### New Capabilities

- `vault-export`: writing the vault to a portable file, and the consent it requires.
- `vault-import`: reading such a file back, and reporting what happened to each item.
- `vault-health-report`: the local checks that find weak, reused, stale, unsecured and
  TOTP-less items.
- `password-strength`: scoring a password and naming its dominant weakness.
- `generator-history`: the session-local list of recently generated values.
- `password-history-view`: displaying the server-maintained previous passwords.
- `master-password-reprompt`: gating secret disclosure on the master password.
- `server-trust`: trusting a custom certificate authority and pinning the server certificate.
- `two-factor-methods`: which second factors can be completed, and how the prompt names them.
- `account-fingerprint`: the five-word phrase derived from the account's public key.

### Modified Capabilities

- `settings-screen`: a certificate section in Security, and a re-prompt enforcement toggle.
- `vault-browser-ui`: a Tools/File menu entry for each new vault-wide operation.
- `detail-card-view`: a password-history section, and gating on reveal.
- `password-generator`: a strength readout and the history list.
- `vault-item-edit`: an editable re-prompt toggle, and a strength readout beside the password.
- `copy-menu-commands`: copy actions honour re-prompt.
- `vault-lock`: locking clears the re-prompt grants and the generator history.

## Impact

- `Prizm/Domain/Utilities/VaultExportDocument.swift` — new; the interchange format, pure `Codable`
- `Prizm/Domain/Utilities/PasswordStrength.swift` — new; the estimator and its score
- `Prizm/Domain/Utilities/PasswordStrengthDictionaries.swift` — new; the embedded common-password list
- `Prizm/Domain/Utilities/VaultHealthReport.swift` — new; the report model and the five checks
- `Prizm/Domain/Utilities/GeneratorHistory.swift` — new; the in-memory ring buffer
- `Prizm/Domain/Utilities/ServerTrustConfiguration.swift` — new; trusted CA + pinned fingerprint
- `Prizm/Domain/Utilities/TwoFactorProvider.swift` — new; the provider map
- `Prizm/Domain/Utilities/AccountFingerprintPhrase.swift` — new; the wordlist mapping
- `Prizm/Domain/UseCases/{ExportVault,ImportVault,GenerateVaultHealthReport,GetPasswordHistory,VerifyMasterPassword,GetAccountFingerprintPhrase}UseCase.swift` — new
- `Prizm/Data/UseCases/` — their implementations
- `Prizm/Data/Network/ServerTrustDelegate.swift` — new; the `URLSessionDelegate` trust decision
- `Prizm/Data/Network/KeychainServerTrustStore.swift` — new; persistence for the trust material
- `Prizm/Data/Network/PrizmAPIClient.swift` — a session built with the trust delegate
- `Prizm/Data/Repositories/AuthRepositoryImpl.swift` — `verifyMasterPassword`, the provider map,
  and the pending-2FA provider
- `Prizm/Domain/Entities/DraftVaultItem.swift` — `reprompt` becomes mutable, and a memberwise
  init for the content types so an import can build a draft from parsed JSON
- `Prizm/Domain/Entities/VaultItem.swift` — `PreservedCipherFields` gains a documented exception
  for the decrypted password history
- `Prizm/App/AppContainer.swift` — wiring for all of the above
- `Prizm/App/PrizmApp.swift` — the File and Tools menu entries, and the re-prompt gate
- `Prizm/Presentation/Vault/Backup/` — the export consent sheet and the import report
- `Prizm/Presentation/Vault/Health/` — the health report sheet
- `Prizm/Presentation/Vault/Reprompt/RepromptSheet.swift` — new
- `Prizm/Presentation/Vault/Edit/PasswordGeneratorView.swift` — strength + history
- `Prizm/Presentation/Vault/Detail/LoginDetailView.swift` — history section, gated reveal
- `Prizm/Presentation/Settings/SettingsView.swift` — the certificate section
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — new strings
- Tests: new suites for every new utility and use case, plus the ViewModel and repository paths
