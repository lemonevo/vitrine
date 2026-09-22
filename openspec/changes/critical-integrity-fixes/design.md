## Context

`PUT /api/ciphers/{id}` on Bitwarden/Vaultwarden replaces the entire cipher. The request body is produced by `CipherMapper.toRawCipher(_:encryptedWith:)`, which builds a fresh `RawCipher` from a `DraftVaultItem`. Any wire field the domain model does not carry is therefore absent from the body and deleted server-side. This is the shared root cause of 2.2, 2.3 and the per-item-key defect.

The fix must not depend on the caller remembering to do something. `DraftVaultItem` is constructed in four places today (`ItemEditViewModel` ×2, `VaultBrowserViewModel.toggleFavorite`, `DraftVaultItem.blank`), and toggling a favourite goes through the same full `PUT` — so a favourite toggle on a passkey-bearing item destroys the passkey just as an edit does.

## Goals / Non-Goals

**Goals**

- Editing an item in Vitrine can never delete data written by another Bitwarden client.
- The per-item cipher key, when present, is used for encryption and returned unchanged.
- Cache-patch operations cannot silently drop domain fields.
- `Copy Code` never puts a long-lived secret on the clipboard.
- No vault domain leaves the device for a third party by default.

**Non-Goals**

- Displaying passkeys or password history. Phase 0 only stops destroying them; the UI is Phase 1/3 work.
- Implementing Archive in the UI. `archivedDate` is preserved, not surfaced.
- Per-item autofill overrides (`autofillOnPageLoad`) as a user-facing setting.
- Export/import, reports, Send, multi-account, offline writes.

## Decisions

### D1 — Carry unmodelled fields on the domain entity, not in a raw-cipher cache

*Alternative considered:* keep a `[String: RawCipher]` cache inside `VaultRepositoryImpl` populated at sync time and merge on write. It keeps the Domain layer free of wire concepts, but it has a silent failure mode: any item missing from the cache (created this session, partial sync, a future code path that appends without recording a raw) silently reverts to today's data-losing behaviour. That is exactly the bug being fixed.

*Decision:* the domain entity carries the fields. `VaultItem.preserved: PreservedCipherFields` is populated by `CipherMapper.map` and consumed by `toRawCipher`. Because every write path builds a `DraftVaultItem` from a `VaultItem`, preservation is automatic — there is no code path that can forget.

The Domain layer stays Foundation-only: `PreservedCipherFields` holds strings, booleans and one `JSONValue` subtree. It names no crypto type and no passkey concept.

### D2 — `JSONValue` for the subtrees Vitrine does not interpret

`login.fido2Credentials` and `passwordHistory` are structured data with mixed value types (`counter` is a string, `discoverable` is a bool). Typing them as Swift structs would mean modelling a feature that is out of scope, and any field added by a future Bitwarden release would be dropped again.

*Decision:* a small `JSONValue` enum (`null`/`bool`/`number`/`string`/`array`/`object`) in `Prizm/Domain/Utilities/`, `Codable` + `Equatable` + `Hashable` + `Sendable`, with hand-written `init(from:)`/`encode(to:)` that preserve the value exactly. Numbers are held as `Double`; every field in these two subtrees is a string or a bool, so no precision is at risk. Key order inside objects is not preserved — JSON object order is not significant.

### D3 — Per-item key: decrypt it, encrypt with it, echo it back

When `raw.key` is present the cipher's fields and its attachments are encrypted with that per-item key, not with the vault/org key. Today `toRawCipher` encrypts with the vault key and sends `key: nil`; the server clears `key`, and every attachment whose key was wrapped with the old cipher key becomes undecryptable.

*Decision:* `toRawCipher` resolves the effective field key first — decrypt `preserved.cipherKey` with the wrapping key (vault or org), fall back to the wrapping key when absent — and returns `key: preserved.cipherKey` unchanged. The wrapping EncString is already correct for the vault/org key, so re-wrapping is unnecessary. This mirrors the read path, which already derives `cipherKey` the same way.

### D4 — Missing org key on write is an error, not a fallback

`VaultRepositoryImpl.update`/`create` select `encryptionKeys = orgKeysSnapshot[orgId] ?? vaultKeys`. For an org item whose org key is unavailable this encrypts the cipher under the personal vault key and sends `organizationId` unchanged — the org cannot read the item and the local client cannot read it after the next sync. Since `CipherMapper.map` refuses to show an org cipher without its org key, no user can reach this state through the UI; the fallback only hides a real failure.

*Decision:* throw `VaultError.decryptionFailed("org key not found for org: …")`, matching the existing behaviour of `encryptCollectionName`.

### D5 — `VaultItem.with(…)` instead of hand-written memberwise rebuilds

`VaultItem` has 11 stored properties. Seven call sites rebuild it to patch one or two fields, and three of them (`deleteFolder`, `moveItemToFolder`, `moveItemsToFolder`) forgot `organizationId` and `collectionIds`. The memberwise init cannot express "keep everything else".

*Decision:* add a field-wise copy helper:

```swift
func with(
    name: String? = nil, isFavorite: Bool? = nil, isDeleted: Bool? = nil,
    revisionDate: Date? = nil, content: ItemContent? = nil, reprompt: Int? = nil,
    attachments: [Attachment]? = nil,
    folderId: String?? = nil,            // .some(nil) clears the folder; nil keeps it
    organizationId: String?? = nil,
    collectionIds: [String]? = nil
) -> VaultItem
```

`nil` means "unchanged"; only `folderId` and `organizationId` need the nested optional because "clear it" and "leave it" are both meaningful. Every cache-patch site is rewritten to use it, so a future field addition cannot be dropped by an old call site.

### D6 — TOTP generation lives in Data, behind a Domain protocol

HMAC needs CryptoKit, which the Domain layer must not import (Constitution §II). `TOTPGenerator` is a Domain protocol returning the current code; `TOTPGeneratorImpl` in `Prizm/Data/Crypto/` uses CryptoKit. `RootViewModel` receives it through `RootViewModelDependencies`, so `Copy Code` can generate the code on the main actor without the Presentation layer importing crypto.

Secrets come in two shapes: a full `otpauth://` URI or a bare Base32 string. Parameters default per RFC 6238 / the Key URI Format (SHA-1, 6 digits, 30 s) and are overridden by the URI query. Base32 decoding is case-insensitive and ignores padding and spaces. An unparseable secret yields `nil`, which disables the menu command rather than copying something wrong.

### D7 — Favicons come from the account's own server by default

`FaviconLoader`'s initialiser default (`https://icons.bitwarden.net`) is removed; the base becomes `nil` (= disabled) until configured. `AppContainer` configures it from `authRepository.serverEnvironment?.iconsURL` — already `{base}/icons` per `ServerEnvironment`, which is the endpoint both Bitwarden and Vaultwarden serve (`/icons/{domain}/icon.png`). A self-hosted user's item domains therefore never leave their own infrastructure.

A `showWebsiteIcons` preference (default on) in `UserDefaults` disables fetching entirely; when off, `favicon(for:)` returns `nil` and callers fall back to the existing SF Symbol, which is the documented failure path. The loader is reconfigured at vault transition and when the toggle changes.

## Risks / Trade-offs

- **`PreservedCipherFields` grows the `VaultItem` value.** It holds two small arrays and three scalars per item, in memory only. Acceptable; the vault is already fully decrypted in memory.
- **`JSONValue` is an untyped escape hatch.** Contained to one struct with a documented purpose; it is never read by the Presentation layer and never rendered.
- **Preserved fields are not merged with concurrent edits.** The write path remains last-write-wins. Preserving is strictly better than deleting, but it does not make Vitrine concurrency-safe — that is the offline/conflict work in Phase 3.
- **Old items synced before this change carry empty `preserved`.** The first sync after upgrading repopulates it; until then a write is no worse than today.
- **TOTP is generated on demand, not on a timer.** Phase 0 only needs the code at the moment ⌃⌘C is pressed; a countdown UI is Phase 1.
