# Encoder invariant tests — Design

## D1 — Compare the wire forms, not the models

The invariant is "nothing the server had is missing from what we send back", which is a statement
about two JSON documents. Comparing `VaultItem`s cannot express it, because the type is precisely the
set of things Prizm kept.

So the test flattens both wire forms into dot-separated paths (`login.uris.0.match`) and compares
those. A new field the decoder learns to read but the encoder does not write shows up as a path in the
input with no counterpart in the output — no test edit required.

## D2 — EncStrings waive equality, never presence

Re-encryption uses a fresh IV and HMAC, so a password that round-trips perfectly comes out as
different bytes. Comparing values there would fail on correct code.

But waiving *equality* must not silently waive *presence*, or the encrypted-path list becomes another
way to hide a loss — and the SSH fingerprint, the original instance, is an EncString. So the two
halves are separate assertions: an encrypted path must still go out non-null, and
`test_encryptedFieldsAreStillCheckedForPresence` locks that in by dropping one by hand.

The set of encrypted paths is recorded by `enc(_:at:)` as each fixture is built, rather than detected
by pattern-matching the string shape. A regex for "looks like an EncString" would be a guess, and a
guess that starts skipping a field which stopped being encrypted is precisely the quiet failure this
file exists to prevent.

## D3 — Every exception carries a reason, and is checked for going stale

Four paths are allowed to arrive and not go back out: `attachments`, `creationDate`, `revisionDate`,
`deletedDate`. Each is a hole in the invariant, so each has an inline comment saying why it is safe
rather than merely unfixed.

A tolerated list is where invariant tests go to become decorative, so
`test_toleratedOmissionsAreAllStillTrue` asserts the opposite direction: each entry must still
correspond to something the encoder actually drops. If someone later makes the encoder send
attachments, the entry becomes stale and the test fails — because a stale exception would excuse the
next field that lost its value for real.

## D4 — The test checks itself

Three tests manufacture a failure without touching production code: drop a preserved field from the
outgoing form, change a value, remove an EncString. Each requires the comparison to name the specific
path.

This is what makes D1–D3 worth having. A guard that cannot fail is not a guard, and the only evidence
that it can is a planted loss.

Beyond that, the change was verified by mutation against the real code: reintroducing
`keyFingerprint: nil` and `RawSecureNoteData(type: 0)` — the two original defects — each made exactly
one test fail, and each the one named for it. Both were reverted, and `git diff --stat` on
`CipherMapper.swift` was checked afterwards.

## D5 — `Data.zeroize()` is tested up to what safe Swift can promise

The obvious test — "after `clear()`, the bytes are zero" — is not writable honestly. `Data` is
copy-on-write; zeroing one value reaches its storage, and any other live reference keeps the original
bytes. `OrgKeyCache`'s own comment says so.

So `KeyCacheClearingTests` asserts reachability (after `clear()` nothing can be read back, and storing
again still works) and pins the CoW boundary with `test_zeroize_doesNotReachAnotherCopy`. That test
documents a limitation rather than a guarantee, which is the point: the next person to read a green
suite should not conclude that memory is being erased.

One test is a genuine regression guard for a real past bug: `resetBytes(in: 0..<count)` treated the
range as an offset from `startIndex`, and a slice keeps its source's indices — so zeroing the tail of a
64-byte key wrote 32 bytes past the allocation, which AddressSanitizer caught in
`OrgKeyCache.clear()`. The test asserts the slice still has `startIndex == 32` before zeroizing it, so
if that ever stops being true the test says so rather than quietly degrading into a test of the easy
case.
