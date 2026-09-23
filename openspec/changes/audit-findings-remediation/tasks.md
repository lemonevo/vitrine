# Audit findings remediation — Tasks

## 1. Data safety (P0)

- [x] 1.1 `VaultRepositoryImpl.update` no longer calls `updateCipherCollections`; the reasoning and
      the requirement for any future membership editor are recorded at the call site.
- [x] 1.2 Two regression tests in `VaultRepositoryImplOrgIntegrityTests`: a known membership and an
      empty (never-learned) membership both assert `updateCipherCollectionsCallCount == 0`.
- [x] 1.3 Both tests confirmed to fail against the pre-change implementation before it was removed.
- [x] 1.4 `reset-keychain.sh` covers `dev.lemonevo.vitrine`, `com.prizm.biometric` and the
      pre-rename `com.prizm`; `--list` prints service/account per item. Verified by running
      `./reset-keychain.sh --list`, which now finds three items where the old script found one.

## 2. Outward-facing (P0)

- [x] 2.1 The `Update Homebrew cask` step is removed from `.github/workflows/release.yml`, with the
      reason where the step was. No other step reads `TAP_GITHUB_TOKEN`.
- [x] 2.2 **Withdrawn — there was no secret to delete.** `gh secret list` exits 0 with no rows on
      this repository, so `TAP_GITHUB_TOKEN` was never configured and the step's own guard would
      have stopped it. The audit's first report called this "the one thing that would break someone
      else's install"; that was an inference from the code presented as a fact, and it is corrected
      here and in `design.md`. The step is still removed — it asserts an ownership this project does
      not have, and a token added later would arm it — but the change is precautionary, not urgent.

## 3. Documentation that contradicted the code

- [x] 3.1 `SECURITY.md`: CSV export is described, including that `login_totp` writes the seed, and
      "No ZIP" is separated from "No CSV".
- [x] 3.2 `SECURITY.md`: the threat-model bullet on TLS interception now says pinning is opt-in and
      off by default instead of "not implemented".
- [x] 3.3 `SECURITY.md`: the clipboard bullet describes the setting and its ranges, including Never.
- [x] 3.4 `SECURITY.md`: vault cache path corrected to `Application Support/Vitrine/` (three
      occurrences), and the same stale path in `VaultCacheStoreImpl`'s own doc comment.
- [x] 3.5 `README.md`: "repository is private" removed; `cd prizm` → `cd vitrine` in the
      build-from-source block.

## 4. Verification for this batch

- [x] 4.1 Full suite run: see the result recorded against task 4.3.
- [x] 4.2 `VaultRepositoryImplOrgIntegrityTests` run alone: 16 tests, 0 failures.
- [x] 4.3 Full suite after the batch: **1552 tests, 0 failures** (`** TEST SUCCEEDED **`), against
      1550 before — the two new regression tests, nothing else changed count.

## 5. Silent overwrite and export honesty (P0)

- [x] 5.1 Update sends `lastKnownRevisionDate`, so Vaultwarden's stale-copy check is no longer
      disabled. Carried as the server's **own string**, verbatim, in `PreservedCipherFields` —
      reformatting the parsed `Date` would send an approximation of an instant the server compares
      exactly. Omitted when the revision is unknown, so create is unchanged.
- [x] 5.2 The refusal becomes `APIError.staleCopy`, with copy that names the remedy. It is a 400 on
      Vaultwarden and a 409 on Bitwarden's own server, so both map; a 400 about anything else stays
      a generic error (asserted). The local cache is untouched, because the throw happens before the
      patch, and the edit sheet keeps the draft and shows the message.
- [x] 5.3 Changing a password appends the previous one to `passwordHistory`, encrypted, with
      `lastUsedDate` set to the moment of replacement. Added only when the password changed to a
      non-empty value — clearing a field is a removal, not a replacement.
- [x] 5.4 The export's done sheet reports how many items could not be read and were therefore not in
      the file. The count comes from the sync result, because an unreadable item never becomes a
      `VaultItem` and so is invisible to every count the export can derive.
- [x] 5.5 `SyncRepositoryImpl`'s `APIError` switch gained `.staleCopy`, in the group that refuses to
      substitute cached data for a server answer. A sync request carries no revision, so the case
      cannot arise there; it is listed so the switch could not have started deciding by accident.
- [ ] 5.6 **Not done, and worth deciding:** a password change does not update
      `login.passwordRevisionDate`. Bitwarden's clients appear to, and the field currently round
      trips unchanged. Left alone because the server's handling of that field was not established
      from a first-party source and guessing at a revision timestamp is how the health report would
      start lying.
- [ ] 5.7 **Unverified convention:** `lastUsedDate` is set to the moment of replacement. Bitwarden's
      export model falls back to `new Date()` when the field is absent, which is what this follows;
      what its clients write on a password change was not confirmed.

## 5a. Verification for section 5

- [x] 5a.1 Full suite: **1565 tests, 0 failures** (`** TEST SUCCEEDED **`), against 1552 after
      section 1 — the 13 new tests are 3 revision, 3 password-history, 3 stale-copy and 4 export.
- [x] 5a.2 Localisation key sets re-compared after the four new strings: 602 keys in `en` and 602 in
      `zh-Hans`, no key on one side only.
- [x] 5a.3 The 400-versus-409 mapping has a control test: a 400 about something else stays a generic
      `httpError`, so a malformed request is not reported to the user as somebody else's edit.
- [x] 5a.4 Adding the `APIError` case made `SyncRepositoryImpl`'s switch non-exhaustive, and the
      four existing `.exportDone` construction sites fail to compile without the new count. Both
      were left non-exhaustive on purpose — the compiler found every site that had to decide.

## 6. Interface responsiveness (P1)

- [x] 6.1 Export encoding leaves the caller's actor — both the CSV render and the JSON encode, via
      the existing `offMain` helper. `jsonExport` became `async` to be able to await it.
- [x] 6.2 Import's document parse leaves the caller's actor. The per-item loop was left alone: it
      awaits a network call per item, so it already yields, and the parse was the bulk.
- [x] 6.3 The health report's full-vault strength scan leaves the caller's actor. The clock is still
      read at the call site, so the report's timestamp is when it was asked for rather than
      whenever the executor reached it.
- [x] 6.4 The temp-file zero-overwrite allocates a fixed 1 MiB buffer instead of a second copy of
      the file. For the 500 MB this app permits that removes a several-hundred-megabyte allocation
      made on the main thread — from `willTerminate` as well as the sweep.
- [ ] 6.5 **Deliberately not changed:** the zero-overwrite is still synchronous. Moving it off the
      main thread would let the quit path return before the overwrite finished, trading the
      guarantee the type exists to make — on the one path where nothing can be retried — for
      responsiveness. The remaining cost is writing `size` bytes; the allocation was the part that
      made it dangerous.
- [ ] 6.6 **What is not proven.** 6.1–6.3 are refactors with no observable behaviour change, and the
      existing suites (which pass) assert that equivalence. **No test asserts that the work now
      runs off the main actor**: the estimator and the vault lookups are concrete types with no seam
      to observe the executing thread from, and adding a protocol purely to spy on it is the kind of
      test-only abstraction this repository has already declined. So "this is off the main thread"
      rests on reading the code and on `offMain`'s `@concurrent` attribute, not on a test.
- [x] 6.7 6.4 *is* tested, and the test does not name more than it asserts: it makes the unlink fail
      (read-only parent directory) so the zeroed file survives to be read, and it uses a file larger
      than one chunk so a loop that stopped early would leave readable bytes.

## 7. Verification for section 6

- [x] 7.1 Full suite after the batch: **1566 tests, 0 failures** (`** TEST SUCCEEDED **`).
- [x] 7.2 `AttachmentTempFileManagerTests` alone: 10 tests, 0 failures, including the new one.
- [x] 7.3 App target builds with no `Sendable` or concurrency diagnostics — `VaultExportDocument`
      and the CSV result satisfy `Sendable` implicitly, so no conformance had to be added and
      nothing had to change shape to cross the boundary.

## 8. The spec corpus and the gap analysis

Work the audit turned up and the sections above did not cover. Both are cases of a document
asserting something the code does not do.

- [x] 8.1 `specs/homebrew-cask/` delta added: the capability's requirements described a tap this
      project does not own, and the release workflow was written to satisfy them. The main
      requirement is replaced with the true one; the three about cask metadata, minimum macOS and
      the declared artifact are removed, because each constrains upstream's formula.
- [x] 8.2 `FEATURE-GAP-ANALYSIS.md` corrected on the three ❓ items the audit resolved from
      `bitwarden/clients` source: archive and item types 6/7/8 are **confirmed gaps**; favourite
      pinning is **confirmed aligned**. The "verify before scheduling" list and the document's own
      error table are updated, and the footer records the re-verification and the test baseline
      measured here.
- [x] 8.3 `FEATURE-GAP-ANALYSIS.md` §1.2 corrected on the two rows the audit found to be wrong in
      the other direction: official **macOS desktop provides system-level autofill and is a passkey
      provider**, so "desktop ❌, no counterpart" was not true.
- [ ] 8.4 **Not done on purpose, and it needs a decision rather than an edit:**
      `openspec/specs/release-infrastructure/spec.md` requires a release workflow that produces a
      "signed, notarized, stapled `.dmg`", with a `CERT_P12` fast-fail and the Developer ID
      certificate imported. `.github/workflows/release.yml` does none of it — it builds unsigned
      (`CODE_SIGNING_ALLOWED=NO`), packages with `hdiutil`, and uploads a draft. So either the spec
      states a goal this project cannot reach without an Apple Developer account, or it is wrong and
      should be rewritten to describe what the workflow actually does. Which of the two it is, is
      the owner's call; rewriting it either way would be inventing an answer. The same question
      covers `ENABLE_HARDENED_RUNTIME` and `ExportOptions.plist`, which the spec requires and the
      project does not set up.
- [ ] 8.5 **Left alone:** `openspec/specs/**` is the merged corpus and is only updated when a change
      is archived. The canonical `homebrew-cask` and `project-documentation` specs still describe the
      old state; the deltas here and in `rename-product-vitrine` / `repository-links-at-this-fork`
      supersede them at archive time. Editing the merged specs directly would skip that step and
      make the process record lie.
- [ ] 8.6 **Overlaps another change:** `remove-dead-code-and-doc-drift/tasks.md` 6.4 is an unchecked
      "not verified" note about this same Homebrew tap. This change resolves it; that change's task
      list is left for its own archive step to tick.
