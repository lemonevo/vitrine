# Encoder invariant tests — Proposal

## Why

Four separate defects have had the same shape: the decoder reads a wire field, the model has no place
for it, and the encoder therefore does not write it back. Because Vaultwarden stores the cipher object
verbatim and `PUT /ciphers/{id}` replaces the whole thing, a field missing from the request body is not
left alone — it is deleted.

SSH key fingerprint, secure-note subtype, offline re-encode, collection permissions. Each was found
individually and each was fixed individually. What did not exist was anything that would make the
*fifth* one expensive.

`CipherMapperReverseTests` was the obvious candidate and it cannot do the job. It goes
`VaultItem` → `RawCipher` → `VaultItem` and compares the two items — every assertion is about a field
the model already has, and a field with no place in `VaultItem` cannot appear in an assertion about
`VaultItem`. It is structurally blind to exactly this class. Worse, it once had one of the losses
written into it as an expected assertion, so the test suite was actively recording the bug as correct.

## What changes

A new test file, `CipherEncoderInvariantTests`, that goes the other way: **wire → model → wire**, then
compares the two wire forms. Every path that arrived with a value must leave with a value, and every
path whose value is not a re-encrypted secret must leave unchanged.

It covers all five item types, with the login fixture carrying every field the decoder reads —
`fido2Credentials`, `passwordRevisionDate`, `autofillOnPageLoad`, `passwordHistory`, `archivedDate`,
`reprompt`, `folderId`, per-item `key` aside.

It also checks itself, because an invariant test that cannot fail is worse than none: three tests plant
a loss, a value change and a dropped EncString by hand and require the comparison to name them; one
test requires that every entry in the tolerated-omission list still corresponds to something the
encoder actually drops.

**Verified by mutation, not by argument.** Reintroducing the original `keyFingerprint: nil` makes
exactly one test fail — `test_sshKey_preservesTheFingerprint`. Reintroducing the hardcoded
`RawSecureNoteData(type: 0)` makes exactly one fail — `test_secureNote_preservesTheSubtypeInteger`.
Neither change trips any other test, so neither is being caught incidentally.

## What this does not do

It does not catch a field the **decoder** also ignores — that never reaches the model, so it is
invisible from here too. That half is a different guard, and pretending otherwise would oversell this
one.

## Non-goals

- **A general "encoder ⊇ decoder" checker generated from the types.** Swift reflection over `Codable`
  would not know which paths are EncStrings, and that distinction is the whole difficulty.
- **Fixing anything.** All six invariant tests pass against the current encoder; the four known
  instances are already repaired. This change exists to keep them repaired.
