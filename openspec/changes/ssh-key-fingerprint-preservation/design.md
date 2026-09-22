# SSH key fingerprint preservation — Design

## Context

The write path for an SSH key is `CipherMapper.toRawSSHKey(_:keys:)`
(`Prizm/Data/Mappers/CipherMapper.swift:552-559`). It builds a `RawSSHKeyData` from a
`DraftSSHKeyContent`, encrypting each string field with the vault keys. Two of the three fields are
handled that way; the third is hardcoded to `nil`.

`DraftSSHKeyContent` (`Prizm/Domain/Entities/DraftVaultItem.swift:209-224`) already carries the
value: it is a `let`, copied from the source `SSHKeyContent` in `init(_:)` (`:220`) and passed
through when the draft is converted back (`:512`). Nothing is missing for the encoder to use it —
it was simply never wired up, on the strength of the comment beside it.

## Decision 1 — round-trip the value; do not derive it

The fingerprint is produced client-side by whichever Bitwarden client created the item, encrypted
with the vault key, and stored by the server as an opaque `EncString`. Vitrine's job on an update is
therefore the same as for every other field: decrypt it on the way in, encrypt whatever it holds on
the way out.

Deriving it instead would be the better fix — it is the only one that survives the user replacing
the key — and it is a different piece of work: it needs the SSH public-key wire format parsed
(`ssh-ed25519`/`ssh-rsa`/`ecdsa-…` prefix, base64 blob), hashed, and encoded as `SHA256:<base64>`
without padding to match what `ssh-keygen -l` prints; and a fallback that derives the public key
from the private key for items that store only the former. Deferring it is a scope decision, not an
oversight, and it is recorded in the proposal's accepted limitation.

## Decision 2 — the stale-fingerprint case is accepted, not silently ignored

Both key fields are editable, so "the user replaced the key but the fingerprint still describes the
old one" is reachable. Clearing it in that case was considered and rejected:

- **Rejected: clear it when the key material changed.** It is not obviously better — the user ends
  up without a fingerprint either way — and it costs a comparison of the private and public keys on
  every save, plus a rule about what "changed" means (a re-typed byte, a re-ordered PEM header?).
  More machinery for a case that still ends in a loss.
- **Rejected: keep the old value silently.** That is what the round-trip does by default, and it is
  only acceptable because it is *stated*. The code comment, `design.md` and the proposal all name it.

The reason this is acceptable at all is the direction of the failure. A stale fingerprint is a
verification aid that does not verify; it does not corrupt the key, does not prevent the key from
working, and is corrected the moment any client that does derive it saves the item. Losing the value
on every unrelated edit, which is today's behaviour, is the worse of the two and happens far more
often.

## Decision 3 — invert the test, do not delete it

`CipherMapperReverseTests.test_reverseMapper_sshKeyRoundTrip` (`:184-204`) asserts
`XCTAssertNil(res.keyFingerprint)` with a comment explaining that the server will supply it. It is
the clearest evidence that the premise was believed rather than overlooked.

It becomes an equality assertion on the fingerprint, alongside the existing assertions for
`privateKey` and `publicKey`. Deleting it would drop the only round-trip coverage for this type;
leaving it would keep the bug pinned.

The round-trip harness in that file (`VaultItem → raw → VaultItem`) is otherwise already correct and
needs no change — which is worth noting, because the harness existing and still pinning the loss is
exactly the situation the broader "encoder output ⊇ decoder input" gap describes.

## Verification

One test settles the behaviour: the fingerprint survives `VaultItem → RawCipher → VaultItem`. It
fails before the change and passes after, which is the whole of the claim.

The manual check, which no unit test can make, is that the item's fingerprint **and its ciphertext**
change together — i.e. that a value is not merely being carried in memory but actually re-encrypted
into the outgoing payload. The unit test covers this implicitly by going through the real mapper
with real keys, so it is a cross-check rather than the primary evidence.
