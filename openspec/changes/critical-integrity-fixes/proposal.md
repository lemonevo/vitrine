## Why

`FEATURE-GAP-ANALYSIS.md` §2 lists five problems that are not missing features but live defects: one leaks a long-lived 2FA secret to the clipboard, three silently destroy data written by other Bitwarden clients, and one hands every vault item's domain to a third-party server. They decide whether Vitrine can be trusted with a real vault, so they are fixed before any new capability is added.

The three data-loss defects share one root cause. `PUT /api/ciphers/{id}` replaces the whole cipher object, and `CipherMapper.toRawCipher` rebuilds the request body from the domain model. Every wire field the domain model does not carry is therefore deleted server-side on save. Verified against the Vaultwarden server source (`update_cipher_from_data` in `src/api/core/ciphers.rs`):

| Field | Server behaviour when omitted from the PUT body |
|---|---|
| `key` (per-item cipher key) | `cipher.key = data.key` — **cleared** |
| `passwordHistory` | `cipher.password_history = data.password_history.map(..)` — **cleared** |
| `archivedDate` | `None => cipher.unarchive(..)` — **actively un-archives** |
| `login.fido2Credentials` | stored verbatim inside `login` — **cleared** |
| `login.passwordRevisionDate`, `login.autofillOnPageLoad` | stored verbatim inside `login` — **cleared** |
| `attachments` | `if let Some(..)` — untouched (safe as-is) |

## What Changes

- **Stop the TOTP seed leak.** `Item ▸ Copy Code` (⌃⌘C) currently copies `LoginContent.totp`, which is the long-lived shared secret, not a one-time code. Implement real TOTP generation (parse `otpauth://` or a bare Base32 secret; HMAC-SHA1/256/512; per-secret period and digit count) and make the command copy the current 6-digit code. No command copies the seed afterwards.
- **Make the write path lossless.** Carry every unmodelled wire field through the domain model verbatim and send it back on PUT: `passwordHistory`, `archivedDate`, `key`, `login.fido2Credentials`, `login.passwordRevisionDate`, `login.autofillOnPageLoad`.
- **Re-encrypt with the per-item key when one exists.** Items that carry `key` must keep it: their fields are encrypted with that key, not with the vault/org key. Today Vitrine encrypts with the vault key *and* nulls `key`, which orphans every attachment whose key was wrapped with the old cipher key.
- **Refuse to write an org item without its org key.** `VaultRepositoryImpl.update` currently falls back to the personal vault key when the org key is missing, which re-encrypts an org cipher under the wrong key. Throw instead.
- **Preserve org membership in cache patches.** `deleteFolder`, `moveItemToFolder` and `moveItemsToFolder` rebuild `VaultItem` without `organizationId` / `collectionIds`, so an org item silently becomes a personal one locally — and a later save then writes it back as personal.
- **Stop sending domains to `icons.bitwarden.net`.** Default the favicon source to the account's own server (`{base}/icons`) and add a Settings toggle to disable website icons entirely.

## Capabilities

### New Capabilities

- `cipher-wire-integrity`: the write path must round-trip every wire field it does not interpret, and must use the correct encryption key for per-item-key ciphers.
- `totp-code-generation`: deriving the current one-time code from a stored TOTP secret.
- `website-icons`: where favicons are fetched from, and whether they are fetched at all.

### Modified Capabilities

- `copy-menu-commands`: `Copy Code` copies the generated one-time code, not the stored seed.
- `org-vault-items`: cache-patch operations preserve `organizationId` / `collectionIds`.
- `settings-screen`: a General-section toggle controls website icons.

## Impact

- `Prizm/Domain/Entities/VaultItem.swift` — new `PreservedCipherFields` value carried on `VaultItem`; new `with(…)` field-wise copy helper
- `Prizm/Domain/Entities/DraftVaultItem.swift` — carry the same field through the edit draft
- `Prizm/Domain/Utilities/JSONValue.swift` — new; opaque JSON subtree that survives a decode/encode round trip
- `Prizm/Data/Network/Models/RawCipher.swift` — model the previously-dropped fields
- `Prizm/Data/Mappers/CipherMapper.swift` — populate the fields on read, merge them on write, resolve the per-item key
- `Prizm/Data/Repositories/VaultRepositoryImpl.swift` — use `VaultItem.with(…)` at all seven cache-patch sites; throw when an org key is missing
- `Prizm/Domain/Repositories/TOTPGenerator.swift` + `Prizm/Data/Crypto/TOTPGeneratorImpl.swift` — new
- `Prizm/App/PrizmApp.swift` — `Copy Code` uses the generator; `RootViewModel` gains the dependency
- `Prizm/Data/Network/FaviconLoader.swift` — no hardcoded default; configurable base, disableable
- `Prizm/App/AppContainer.swift`, `Prizm/Presentation/Settings/SettingsView.swift` — wiring and the new toggle
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — new strings
- Tests: `CipherMapperTests`, `VaultRepositoryImplTests`, new `TOTPGeneratorTests`, `FaviconLoaderTests`
