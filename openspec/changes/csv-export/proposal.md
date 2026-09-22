# CSV export — Proposal

## Why

Vitrine exports one format: unencrypted Bitwarden JSON. Bitwarden offers `.json` (plaintext), `.csv`
(plaintext), `.json (Encrypted)` and `.zip (with attachments)`.

CSV is the format a user needs to **leave**. Every other manager reads it, and the official docs
describe it precisely enough to reproduce faithfully — which is the property that decides whether it is
worth building at all.

## What Changes

- `ExportVaultUseCase` takes a format, defaulting to the existing JSON so no call site changes.
- A CSV serializer producing Bitwarden's documented shape:

  ```
  folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
  ```

  with the encodings the official documentation pins down, including its example row
  (`Social,1,login,Twitter,,,0,twitter.com,me@example.com,password123,`), which is reproduced verbatim
  in the tests.
- The backup sheet offers the choice, and the done sheet says what was written.

## The one thing this deliberately does not carry, and says so

**Only login rows are exported.** The columns are login-shaped, and the documentation's example pins
the `type` token for a login and nothing else — so the token for any other type would be a guess. A
CSV that the official client refuses to import is worse than no CSV, because the user discovers it at
the moment they were relying on it.

**Every omitted item is counted and reported.** The official docs say the unencrypted formats exclude
cards, identities, passkeys and SSH keys — so omitting them is the official behaviour, not a Vitrine
shortfall. Doing it *silently* would not be: a user who exports 400 items and gets 300 rows has to be
told. `VaultExport` carries the count and the done sheet shows it.

## Non-goals

- **Encrypted export (`.json (Encrypted)`).** Bitwarden documents its top-level keys
  (`encrypted`, `passwordProtected`, `salt`, `kdfType`, `kdfIterations`,
  `encKeyValidation_DO_NOT_EDIT`, `data`) and **nothing about how the data is derived or what the
  validation field holds**. An encrypted backup is only ever exercised in an emergency, so shipping one
  whose format was guessed is worse than not shipping one: the failure would surface on the day the
  user needed it. Recorded as blocked on the format details, not as an oversight.
- **`.zip` with attachments.** Needs archiving plus the attachment blobs, which are downloaded on
  demand and not part of the vault.
- **Encrypted import.** Rejected today with a named error; accepting it needs the same undocumented
  details as encrypted export.
- **Changing what the JSON export contains.** It already carries all five item types, which is *more*
  than the official unencrypted format does.

## Impact

- `Prizm/Domain/UseCases/ExportVaultUseCase.swift` — the format
- `Prizm/Domain/Utilities/VaultExportCSV.swift` — **new**, a pure serializer
- `Prizm/Data/UseCases/ExportVaultUseCaseImpl.swift` — build either format
- `Prizm/Presentation/Vault/Backup/*` — the format choice and the omitted count
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings`
