## ADDED Requirements

### Requirement: Passkeys stored on an item are listed

For a login item whose `login.fido2Credentials` is non-empty, the detail view SHALL offer a
**read-only** passkey section listing, for each credential: the relying party id, the relying party
name when present, the user name when present, and the creation date.

The section SHALL NOT offer any action that uses the credential. Registering a passkey, asserting
one, deleting one, or exporting one are all out of scope.

#### Scenario: The section appears only when there is something to show
- **GIVEN** a login item with no `fido2Credentials`
- **WHEN** its detail view renders
- **THEN** no passkey section SHALL be shown

#### Scenario: The section appears when there is at least one credential
- **GIVEN** a login item with one passkey for `example.com` created on 2026-01-15
- **WHEN** its detail view renders
- **THEN** a passkey section SHALL show `example.com` and the creation date

#### Scenario: A credential with no user name is still listed
- **GIVEN** a passkey whose `userName` is absent
- **WHEN** it is listed
- **THEN** it SHALL appear with the fields that are present
- **AND** the absent field SHALL be omitted rather than rendered as empty

#### Scenario: A malformed entry does not hide the rest
- **GIVEN** a login item with three credentials, one of which cannot be decrypted
- **WHEN** the section renders
- **THEN** the other two SHALL be listed
- **AND** the undecryptable one SHALL be omitted

#### Scenario: An entry that is not an object is skipped
- **GIVEN** an entry in `fido2Credentials` that is not a JSON object
- **WHEN** the section renders
- **THEN** it SHALL be skipped
- **AND** the remaining entries SHALL be listed

---

### Requirement: The private key is never read

`keyValue` holds the credential's **private key**, not its public one — Bitwarden's authenticator
stores `crypto.subtle.exportKey("pkcs8", keyPair.privateKey)` and later imports it to sign. It is
the most sensitive value on the item, and this feature has no use for it.

The implementation SHALL NOT decrypt, store, display, copy, or log `keyValue` on any path.

#### Scenario: The private key is not decrypted
- **GIVEN** a credential whose other fields decrypt successfully
- **WHEN** it is prepared for display
- **THEN** `keyValue` SHALL NOT be passed to the decryption routine

#### Scenario: The private key is not displayed
- **GIVEN** a credential is listed
- **WHEN** the row renders
- **THEN** no representation of `keyValue` SHALL appear in the interface
- **AND** no control SHALL offer to copy it

#### Scenario: The private key is not logged
- **GIVEN** a credential fails to decrypt
- **WHEN** the failure is logged
- **THEN** the log line SHALL identify the cipher, not the value

---

### Requirement: Passkey data is decrypted on demand and never cached

The credential fields are individual EncStrings encrypted with the cipher's key — the same key that
encrypts the item's password. They SHALL be decrypted only when the section is rendered, and the
decrypted values SHALL NOT be retained in the domain model or in any cache.

#### Scenario: Nothing is decrypted until the item is displayed
- **GIVEN** a login item with passkeys that is not open
- **WHEN** a sync completes
- **THEN** no passkey field SHALL have been decrypted

#### Scenario: The values are not retained
- **GIVEN** the section has rendered
- **WHEN** the user selects a different item
- **THEN** the previously decrypted values SHALL be discarded

---

### Requirement: The interface states that these cannot be used here

A list of passkeys with no such note reads as a feature that does not work.

#### Scenario: The limitation is stated in the section
- **GIVEN** a passkey section is shown
- **WHEN** the user reads it
- **THEN** it SHALL state that Vitrine cannot use these credentials to sign in
- **AND** the statement SHALL name what is possible elsewhere rather than only what is not
