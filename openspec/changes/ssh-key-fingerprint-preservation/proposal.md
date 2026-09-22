# SSH key fingerprint preservation — Proposal

## Why

`CipherMapper.toRawSSHKey` sends `keyFingerprint: nil` on every write
(`Prizm/Data/Mappers/CipherMapper.swift:558`). The read path is correct — the fingerprint is
decrypted like any other field (`:312`) — so an SSH key item displays its fingerprint right up until
the user saves it, at which point it is gone.

The code explains itself with a belief that cannot be true:

> `keyFingerprint is auto-derived and not sent to the API — it is server-authoritative.`

The server has no vault key. It cannot derive anything about the contents of a cipher. The value it
stores is an `EncString` (`Prizm/Data/Network/Models/RawCipher.swift:206`) — an opaque blob it can
only keep or drop. So `nil` here does not mean "let the server recompute it"; it means **clear the
field**.

The same belief is repeated in `DraftSSHKeyContent` ("never sent to the API",
`Prizm/Domain/Entities/DraftVaultItem.swift:207-208,212`), in `SSHKeyEditForm`'s type comment
(`Prizm/Presentation/Vault/Edit/SSHKeyEditForm.swift:8-10`), and — most tellingly — as an assertion
in the test suite, which pins the loss as correct behaviour:

```swift
// keyFingerprint is not sent to the API; the forward-mapped result will have nil.
XCTAssertNil(res.keyFingerprint)
```

That is the shape of a data-loss bug that has been tested into place: nothing looks broken, because
the test agrees with the code.

The concrete harm is small and permanent. A user edits the note on an SSH key item and saves; the
fingerprint is erased. The fingerprint is what they compare against `ssh-keygen -lf` to confirm a
public key is the one they think it is, so the loss is not cosmetic — it removes the only field that
lets them check the key. And it is silent: the next sync shows `[No fingerprint]`
(`Prizm/Presentation/Vault/Detail/SSHKeyDetailView.swift:37-38`) with no indication that it used to
be there.

## What Changes

- `toRawSSHKey` encrypts and returns `DraftSSHKeyContent.keyFingerprint` instead of dropping it —
  the same treatment every other field in that struct already gets.
- The three comments that state the false premise are corrected to say what is actually true: the
  fingerprint is client-derived, stored by the server opaquely, and must be round-tripped.
- The test that asserts the loss is inverted into a test that asserts preservation, with the
  round-trip extended to cover it.

## Non-goals

- **Deriving or recomputing the fingerprint.** Doing it properly means parsing the SSH public-key
  wire format and hashing it (`SHA256:` base64, as `ssh-keygen -l` reports), plus a fallback to
  deriving from the private key when no public key is stored. That is a real feature with real
  parsing, and it is not needed to stop the data loss. See the accepted limitation below.
- **Making the fingerprint editable.** It is a derived value; a text field for it would invite
  entries that disagree with the key.
- **Touching any other SSH key field.** `privateKey`, `publicKey`, `notes` and custom fields already
  round-trip correctly.

## Accepted limitation

**If the user changes the key material, the stored fingerprint becomes stale.** Both `privateKey`
and `publicKey` are editable (`SSHKeyEditForm.swift:24-26`), so a user can replace the key and save
without the fingerprint being recomputed. The stored value then describes a key that is no longer
there — which is arguably worse than no fingerprint at all, because it looks like a verification
aid.

This is taken deliberately, in preference to clearing the fingerprint whenever the key material
changed, because it is the smaller change and because the alternative still ends in a loss (the
fingerprint is gone either way once the key is replaced). Recomputing is the only fix that does not
lose information, and it is deferred rather than pretended away. Recorded here, in `design.md`, and
in the code comment so a later reader does not have to rediscover it.

## Impact

- `Prizm/Data/Mappers/CipherMapper.swift` — `toRawSSHKey`
- `Prizm/Domain/Entities/DraftVaultItem.swift` — the `DraftSSHKeyContent` doc comments
- `Prizm/Presentation/Vault/Edit/SSHKeyEditForm.swift` — the type doc comment
- `Prizm/PrizmTests/Data/CipherMapperReverseTests.swift` — the assertion that pins the loss
