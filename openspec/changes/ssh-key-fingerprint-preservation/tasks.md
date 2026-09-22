# SSH key fingerprint preservation — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`. Until the test target compiles,
> none of the tests below can run.

## 1. The failing test

- [x] 1.1 Invert `CipherMapperReverseTests.test_reverseMapper_sshKeyRoundTrip`: assert the fingerprint
      survives the round trip, beside the existing `privateKey` / `publicKey` assertions, and delete
      the comment that says the server will supply it.
- [x] 1.2 Run it and confirm it fails on the fingerprint assertion alone — the other fields must
      already pass, or the failure is not evidence of this bug.

## 2. The fix

- [x] 2.1 `toRawSSHKey`: encrypt `c.keyFingerprint` instead of sending `nil`.
- [x] 2.2 Correct the comment above it. It currently states that the value is server-derived, which
      is structurally impossible — the server holds an `EncString` it has no key to read. State that
      the value is client-derived and must be round-tripped, **and** record the accepted
      stale-fingerprint limitation where a reader of that function will see it.

## 3. The other copies of the false premise

- [x] 3.1 `DraftSSHKeyContent`'s type comment and its `keyFingerprint` property comment
      (`Prizm/Domain/Entities/DraftVaultItem.swift:207-208,212`) both say the value is never sent.
      Correct them to say what is true: read-only in the form, but round-tripped to the server.
- [x] 3.2 `SSHKeyEditForm`'s type comment (`:8-10`) repeats it. Correct it, keeping the accurate half
      (the field is read-only because it is derived, not because it is unsent).
- [x] 3.3 Grep for any remaining statement that the fingerprint is server-derived or unsent, and
      correct or remove it. A false comment beside a write path is how this bug got written.

## 4. Verification

- [x] 4.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
      → **1308 passed / 0 failures.**
- [x] 4.2 Confirm no other SSH key field changed behaviour — the round-trip test covers all of them,
      and the cipher wire-integrity tests must be unaffected.
