# Encoder invariant tests — Tasks

## 1. The invariant

- 1.1 `CipherEncoderInvariantTests` — wire → model → wire, flattened path comparison (D1).
- 1.2 EncStrings waive equality but not presence; paths recorded at fixture-build time (D2).
- 1.3 Tolerated omissions, each with an inline reason: `attachments`, `creationDate`, `revisionDate`,
      `deletedDate` (D3).
- 1.4 Fixtures for all five item types. The login fixture carries every field the decoder reads.

## 2. The guard on the guard

- 2.1 `test_theComparisonDetectsALostField` — a preserved field removed by hand must be named.
- 2.2 `test_theComparisonDetectsAChangedValue` — same for a value rewritten rather than dropped.
- 2.3 `test_encryptedFieldsAreStillCheckedForPresence` — the equality waiver must not become a
      presence waiver.
- 2.4 `test_toleratedOmissionsAreAllStillTrue` — a stale exception is a hole with no purpose.

## 3. Mutation verification against production code

- 3.1 Reintroduce `keyFingerprint: nil` → exactly `test_sshKey_preservesTheFingerprint` fails. ✅
- 3.2 Reintroduce `RawSecureNoteData(type: 0)` → exactly
      `test_secureNote_preservesTheSubtypeInteger` fails. ✅
- 3.3 Both reverted; `git diff --stat` on `CipherMapper.swift` checked afterwards. ✅
      (First attempt at 3.2 failed to compile — a trailing `//` comment swallowed the rest of a
      multi-element tuple line. Noted because it is the kind of thing that would have looked like a
      passing verification.)

## 4. Key caches

- 4.1 `KeyCacheClearingTests` — `OrgKeyCache` and `AccountKeyCache` had no test files at all.
- 4.2 `Data.zeroize` — owned buffer, empty buffer, and the sliced-buffer case that AddressSanitizer
      once caught as a 32-byte heap overflow in `OrgKeyCache.clear()` (D5).
- 4.3 The CoW boundary pinned as a test, so a green suite is not read as proof of memory erasure.

## 5. Result

- 5.1 Full suite: **1472 passed, 0 failed** (from 1453; 19 tests added across the two files).
- 5.2 No production code changed by this work.
