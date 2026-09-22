# Tasks — attachment bytes never meet the main thread

## 1. The hop

- [x] 1.1 `offMain(_:…)` in `Domain/Utilities/OffMain.swift` — two `@concurrent` functions, one for a
      single input and one for the file-plus-key pair of the crypto calls. Registered in
      `project.pbxproj` (build file, file reference, group child, Sources phase).
- [x] 1.2 The file's comment states the mechanism it fixes — `-default-isolation MainActor` plus
      `nonisolated` meaning "who may call", not "where it runs" — so the next caller does not have to
      re-derive it.
- [x] 1.3 And the trap it avoids: buffers arrive as **arguments**, never as captures, because a capture
      is a second reference to a `Data` whose owner calls `zeroize()` — which then copies and erases
      the copy. `Task.detached` with captured locals was the first version of every one of these call
      sites and is the shape this item exists to reject.
- [x] 1.4 The same comment states what it does **not** do: it does not make the work interruptible.
      Being an ordinary `await` rather than a detached task, the hop at least keeps the caller's
      priority and cancellation.

## 2. Sites moved

- [x] 2.1 Encrypt the blob on upload — `AttachmentRepositoryImpl.upload` step 3.
- [x] 2.2 Decrypt the blob on download — `AttachmentRepositoryImpl.download`.
- [x] 2.3 Read the picked file: single-file sheet (`AttachmentAddViewModel.confirm`), batch sheet
      (`AttachmentBatchViewModel`), retry-upload (`AttachmentRowViewModel.retryUpload`).
- [x] 2.4 Write decrypted bytes: save-to-disk and the temp file behind "Open"
      (`AttachmentRowViewModel`, `writeTempFile(data:)` became `async`).
- [x] 2.5 The small crypto deliberately stayed synchronous: `encryptFileName`,
      `encryptAttachmentKey`, `decryptAttachmentKey`, `generateAttachmentKey`.
- [x] 2.6 `AttachmentRowViewModel.saveToDisk` passes the decrypted buffer straight into the hop and
      keeps no second binding of it. The first version held `let plaintext = data` beside the hop,
      which looked equivalent and quietly made the `data.zeroize()` below it erase a copy.
- [x] 2.7 `writeTempFile(data:)` only had to become `async`. It already received the buffer as a
      parameter of a function call, which is the lifetime the rule above needs.

## 3. The measured proof

- [x] 3.1 `MockBulkWork.nanoseconds` — a file-scope knob the mock crypto sleeps for inside
      `encryptData` / `decryptData`. File scope because an actor's `static` is actor-isolated and a
      `nonisolated` method cannot reach it.
- [x] 3.2 `ticksDuring(_:)` polls the main actor every 40 ms while the operation runs and returns how
      many times the poll got scheduled.
- [x] 3.3 Threshold is 8 for a 0.6 s operation, not the 15 a free 40 ms poll would produce: it must
      fail loudly on the old code (measured **3**) and not hinge on one tick of scheduling noise.
- [x] 3.4 The threshold was checked by mutation rather than trusted: raising it to 999 on the final
      `@concurrent` implementation reported **"(16) is less than (999)"** — the poller ran 16 times
      while the file was being processed. The earlier `Task.detached` version measured 16 as well, so
      switching mechanism cost nothing observable.
- [x] 3.5 `offMain` itself is tested for the three things a helper like this can get wrong: the actor
      stays runnable, the result comes back typed, the error propagates.
- [ ] 3.6 **Not covered:** a measured before/after for the file reads and writes. Observing them needs
      a several-hundred-megabyte fixture in every run to make one 40 ms window countable.
- [ ] 3.7 **Not coverable:** that a buffer passed through the hop is still uniquely the caller's
      afterwards. A test that could observe those bytes would have to hold a second reference to them,
      which is the very condition being avoided — `KeyCacheClearingTests` documents the same limit.
- [x] 3.8 `test_saveToDisk_success_zerosBuffer` never asserted anything about zeroization: it checked
      that a file appeared on disk and that no error was set. Renamed to
      `test_saveToDisk_success_writesTheFileAndRaisesNoError`, with a comment saying what it cannot
      check. A test name that promises coverage is its own kind of lie.

## 4. FaviconLoader, found by this change's verification

- [x] 4.1 The in-memory icon table is now `[String: NSImage]` plus an insertion-order array, bounded at
      `FaviconLoader.memoryCacheLimit = 512`, evicting the oldest fetched domain.
- [x] 4.2 `remember(_:for:)` only extends the order for a genuinely new domain: `favicon(for:)` awaits
      inside the actor, so two calls for one domain can both miss and both store.
- [x] 4.3 New test `test_theCacheIsBoundedAndDropsTheOldestFetchedDomain` — fails if eviction stops
      happening **and** if the table is unbounded, which is the pair `NSCache` gave implicitly.
- [x] 4.4 `RecordingURLProtocol` tags each request with the test that caused it; the two
      retention-dependent count assertions print that tagged log when they fail.
- [x] 4.5 The diagnosis is recorded as an inference in `proposal.md`, including that no run in this
      session reproduced the failure.

## 5. Documentation the rename broke

- [x] 5.1 `-scheme "Vitrine"` → `-scheme "Prizm"` in `DEVELOPMENT.md` (2), `CLAUDE.md` (2), and
      `fix-test-target-buildability`'s design and tasks notes.
- [x] 5.2 `DEVELOPMENT.md` already told the reader to add CI's no-signing flags when no identity is
      configured; the failure was that `CLAUDE.md`'s quick reference omitted them. Its test command now
      carries the flags and says why in one line.

## 6. Verification

Each run is `xcodebuild test … CODE_SIGNING_ALLOWED=NO` against `platform=macOS`, and each number below
is from the run named beside it — they are not one run's numbers reused.

- [x] 6.1 Targeted, on the final shape of the helper: `AttachmentRepositoryMainActorTests` +
      `AttachmentRepositoryImplTests` + `AttachmentAddViewModelTests` + `AttachmentRowViewModelTests` +
      `AttachmentBatchViewModelTests` — 54 passed, 0 failed, with the upload test taking 0.871 s, which
      is the 0.6 s simulated encryption plus its polling window.
- [x] 6.2 `FaviconLoaderTests` alone after the cache change: 14 passed, 0 failed; the bound test costs
      0.3 s.
- [x] 6.3 The tick count was read from a failing assertion rather than estimated — see 3.4.
- [x] 6.4 Full suite on the exact tree being committed, **2026-09-22 one batch**: 1549 passed, 0
      failed, 0 skipped in 178 s. 1549 is also the number of `func test` declarations in `PrizmTests`
      (there are no `@Test` cases), so the executed set is the whole set. That includes 3 tests from
      `P3MainWindowScreenshotTests` — another session's untracked work in this tree, not this change's.
- [x] 6.5 CI green on the pushed commit — run 35740555391 on `b56367f`, every step including
      `Test (no signing)`. **CI executed 1546 tests, 0 failures**; the 3-test difference from the local
      1549 is `P3MainWindowScreenshotTests`, which is not in the pushed tree. Both build and test steps
      run under `set -o pipefail`, so a failure fails the job — see `fix(ci): make a failed build
      actually fail the job`.
- [ ] 6.6 **Still unknown:** the favicon flake was never reproduced, so the diagnosis in
      `proposal.md` remains an inference. If a count assertion in that file fails again, the tagged
      request log now says whose request the extra one was — that is the observation this session
      needed and did not get.
