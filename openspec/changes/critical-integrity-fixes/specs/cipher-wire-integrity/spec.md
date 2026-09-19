## ADDED Requirements

### Requirement: Saving an item preserves wire fields Prizm does not model

`PUT /api/ciphers/{id}` replaces the whole cipher: any field absent from the request body is
deleted server-side (Vaultwarden `update_cipher_from_data` assigns `key`, `password_history` and
`archived_date` unconditionally and stores `login` verbatim). `VaultItem` SHALL therefore carry
every unmodelled wire field it received, and `CipherMapper.toRawCipher` SHALL merge them back into
the outgoing request unchanged. The preserved set SHALL be `passwordHistory`, `archivedDate`, `key`,
`login.fido2Credentials`, `login.passwordRevisionDate` and `login.autofillOnPageLoad`.

Preserved values SHALL remain in their wire (EncString / opaque JSON) form. The system SHALL NOT
decrypt passkey material or historical passwords, because no screen displays them.

#### Scenario: Passkeys survive an unrelated edit
- **GIVEN** a login item whose `login.fido2Credentials` array is non-empty
- **WHEN** the user edits the item's notes and saves
- **THEN** the outgoing request body SHALL contain the original `login.fido2Credentials` array unchanged
- **AND** the server SHALL still hold the passkey after the request completes

#### Scenario: Password history survives an unrelated edit
- **GIVEN** a login item with a non-empty `passwordHistory` array
- **WHEN** the user edits any field and saves
- **THEN** the outgoing request body SHALL contain the original `passwordHistory` array unchanged

#### Scenario: Archived items are not un-archived by an edit
- **GIVEN** an item with a non-nil `archivedDate`
- **WHEN** the user edits any field and saves
- **THEN** the outgoing request body SHALL contain the original `archivedDate`
- **AND** the server SHALL NOT run its un-archive path

#### Scenario: Per-login fields survive an edit
- **GIVEN** a login item with a non-nil `login.passwordRevisionDate` and a non-nil `login.autofillOnPageLoad`
- **WHEN** the user edits the item's password and saves
- **THEN** both values SHALL be present in the outgoing `login` object

#### Scenario: Toggling favourite does not destroy unmodelled fields
- **GIVEN** an item carrying any preserved field
- **WHEN** the user toggles its favourite status
- **THEN** the preserved fields SHALL be included in the outgoing request body

#### Scenario: Preserved values are never decrypted
- **WHEN** an item is mapped from the wire format
- **THEN** `VaultItem.preserved` SHALL contain the original EncString / opaque JSON values
- **AND** no decryption SHALL be attempted on them

---

### Requirement: Items with a per-item cipher key keep it

When a cipher carries a per-item key (`raw.key`), its fields and its attachments are encrypted with
that key rather than with the vault or organisation key. The vault/org key is used only to unwrap
it. `CipherMapper.map` SHALL therefore resolve the effective key before decrypting anything, and
SHALL decrypt the cipher's name, notes, custom fields, type-specific payload and attachments with
that resolved key — decrypting with the vault/org key fails MAC verification and makes the item
unreadable, and an unreadable item cannot be edited either, so the write-side rule below would
never get a chance to run. `CipherMapper.toRawCipher` SHALL resolve the key the same way, SHALL
encrypt every field with it, and SHALL return the original per-item key EncString as `key` in the
outgoing request.

#### Scenario: Per-item key is reused for encryption
- **GIVEN** an item whose `key` is a per-item key EncString and whose fields are encrypted with it
- **WHEN** the item is saved
- **THEN** the outgoing fields SHALL be encrypted with the per-item key, not with the vault key
- **AND** the outgoing `key` SHALL be the original per-item key EncString

#### Scenario: Fields are decrypted with the per-item key
- **GIVEN** a cipher whose `key` is a per-item key EncString and whose fields are encrypted with it
- **WHEN** the cipher is mapped from the wire format
- **THEN** its name, notes and type-specific payload SHALL be decrypted with the per-item key
- **AND** the item SHALL NOT report a decryption failure

#### Scenario: An unwrappable per-item key is not guessed at
- **GIVEN** a cipher whose `key` cannot be decrypted with the vault or org key
- **WHEN** the item is saved
- **THEN** the save SHALL fail with a decryption error
- **AND** the fields SHALL NOT be re-encrypted with the wrapping key

#### Scenario: Attachment keys stay usable after an edit
- **GIVEN** an item with a per-item key and at least one attachment whose key is wrapped with it
- **WHEN** the user edits the item and saves
- **THEN** the item's `key` SHALL be unchanged
- **AND** the existing attachment SHALL remain downloadable

#### Scenario: Item without a per-item key is unaffected
- **GIVEN** an item whose `key` is nil
- **WHEN** the item is saved
- **THEN** fields SHALL be encrypted with the vault (or org) key
- **AND** the outgoing `key` SHALL be nil

---

### Requirement: An org item is never written without its org key

`VaultRepositoryImpl.update` and `create` SHALL throw `VaultError.decryptionFailed` when
`draft.organizationId` is non-nil and no matching key exists in `OrgKeyCache`. Falling back to the
personal vault key would encrypt the cipher under a key the organisation cannot use.

#### Scenario: Org item with a missing org key refuses to save
- **GIVEN** a draft whose `organizationId` is set and whose org key is absent from `OrgKeyCache`
- **WHEN** the draft is saved
- **THEN** the call SHALL throw `VaultError.decryptionFailed`
- **AND** no network request SHALL be made

#### Scenario: Personal item still uses the vault key
- **GIVEN** a draft whose `organizationId` is nil
- **WHEN** the draft is saved
- **THEN** the fields SHALL be encrypted with the personal vault key
