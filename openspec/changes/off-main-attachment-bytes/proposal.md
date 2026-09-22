# Attachment bytes never meet the main thread — Proposal

## Why

`FEATURE-GAP-ANALYSIS.md` §D15: uploading or downloading an attachment froze the interface for the
whole duration of the crypto. The upper bound this app enforces is 500 MB per file, which is tens of
seconds of a dead window with a progress spinner that cannot animate.

Three facts compose into it, and none of them is a mistake on its own:

1. The app target compiles with `-default-isolation MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION`), so
   `AttachmentRepositoryImpl` — a plain `final class` that never says otherwise — is main-actor
   isolated.
2. The attachment crypto methods are declared `nonisolated` on `PrizmCryptoServiceImpl`, an `actor`,
   and that was deliberate: it is what lets a test call `sut.encryptData(...)` synchronously through
   `any PrizmCryptoService` without an `await`.
3. `nonisolated` on an actor method describes **who may call it**, not **where it runs**. It runs on
   the caller's thread.

So AES-256-CBC plus HMAC-SHA256 over the entire file executed on the thread drawing the interface.
The same shape applies to the file bytes themselves: four places read or wrote a whole file with
`Data(contentsOf:)` / `Data.write(to:)` from a main-actor view model.

**The spec already forbade this, and the code satisfied it anyway.** `attachment-add-flow` has said
"Encryption and upload SHALL execute on a background `Task`" since it was written. The code did run
inside a `Task` — a main-actor-bound one, which is precisely the thing that does not make the
encryption background. A requirement whose wording is satisfied by an implementation that does the
opposite is rewritten here, not just implemented.

## What changes

- **`offMain(_:…)`** (`Domain/Utilities/OffMain.swift`) — `@concurrent` functions that run a
  synchronous computation on the global concurrent executor and await its result. The buffers arrive
  **as arguments**, which is the part that needs a design and not just a one-liner; see the next
  section.
- **Seven call sites moved**, all in the attachment flows:
  - encrypt the blob on upload (`AttachmentRepositoryImpl.upload` step 3);
  - decrypt the blob on download (`AttachmentRepositoryImpl.download`);
  - read the picked file in the single-file sheet, the batch sheet, and retry-upload;
  - write the decrypted bytes in save-to-disk and in the temp file behind "Open".
- **`attachment-add-flow` / `vault-actor-isolation` deltas** state the executor requirement in terms
  that a main-actor `Task` can no longer satisfy.

## The trap the first version of this fell into

The obvious shape is `offMain { try crypto.encryptData(snapshot, attachmentKey: keySnapshot) }` — bind
what the closure needs to locals, because a `@Sendable` closure cannot reach through `self`. That is
also **silently wrong**, and it is wrong in a way this repository already has a name for.

`Data` is copy-on-write, and `Data.zeroize()` is implemented with `withUnsafeMutableBytes` — which
means: if a second reference to those bytes exists when `zeroize()` is called, the buffer is copied
first and the memset erases **the copy**, leaving the real key material in the original. This is
`KeyCacheClearingTests.test_zeroize_doesNotReachAnotherCopy`, stated as a test so nobody writes a
stronger one and reads the green suite as proof of memory erasure.

A closure that *captures* a file blob or an attachment key holds exactly such a second reference, for
a lifetime this file cannot reason about. So the helper takes its inputs as parameters: a parameter is
released at a call boundary, which is the same — and the only — guarantee the synchronous call it
replaced had. The consequence for callers is a rule worth stating plainly: **do not hold a `let` of a
buffer next to the hop that processes it.** `AttachmentRowViewModel.saveToDisk` is the site where that
mistake was live for a few minutes, and its comment now says why the argument form is used.

Nothing asserts this. A test could not: to observe whether `zeroize()` reached the real bytes, the
test would have to hold a reference to them, which is the condition that defeats it. That is the same
limitation `KeyCacheClearingTests` records. The defence is the helper's shape plus this paragraph.

**Found while doing this: `test_saveToDisk_success_zerosBuffer` did not test zeroization.** It asserted
that a file appeared on disk and that no error was set. Renamed to
`test_saveToDisk_success_writesTheFileAndRaisesNoError`, with a comment saying what it cannot check and
why.


## Measured

`AttachmentRepositoryMainActorTests` polls the main actor every 40 ms while a mocked encryption that
takes 0.6 s runs, and asserts the actor got the chance to run in that window:

- before the change: **3 ticks** — the polling task could only resume around the blocked interval;
- after: **16 ticks** — the file is processed while the interface is runnable (0.6 s / 40 ms = 15).

The test's threshold is 8, deliberately below the 15 achievable: it fails on the old code by a wide
margin rather than by one tick.

## Deliberate limits

- **Only the bulk methods moved.** `encryptFileName`, `encryptAttachmentKey`, `decryptAttachmentKey`
  and `generateAttachmentKey` handle a filename and three 64-byte values. A thread hop costs more
  than the work it would move.
- **This does not make the work interruptible.** A single `CommonCrypto` call cannot be abandoned
  mid-buffer. The hop is an ordinary `await` inside the caller's own task — `@concurrent` moves the
  executor, not the task — so priority and cancellation still reach everything *around* the call, and
  cancelling an upload lets the in-flight buffer finish. A real progress percentage and true
  interruption need the buffer chunked, which changes the encrypted blob layout — a wire-format
  decision, not a threading one. Recorded in `OffMain.swift`.
- **The KDF was never affected.** `deriveMasterKey` and the rest are actor-isolated (`async`), so
  they already ran off the main thread. The six `nonisolated` attachment methods were the only
  synchronous bulk crypto reachable from the main actor — that was checked by enumerating every
  `nonisolated` declaration in `PrizmCryptoService` and then every production call site of them.
- **`AttachmentTempFileManager`'s zeroing write stays where it is.** It runs on a 30-second timer
  after the file was already handed to another app, not inside an interaction the user is waiting on.
- **The repository was not converted to an `actor`.** That would move every method off-main to fix
  seven buffers, including the vault-cache patching whose isolation nobody complained about. The hop
  names the exact cost being moved and leaves the rest of the type's reasoning intact.
- **No measurement for the file I/O hops.** Proving them would need a several-hundred-megabyte
  fixture in every CI run to make one 40 ms window observable; the mechanism is the same synchronous
  call on the same thread, and the existing test already pins that mechanism.

## Why this change also touches FaviconLoader

Verifying this change in the full suite produced two intermittent failures — in
`test_repeatedRequestsForTheSameDomainUseTheCache` and
`test_configuringTheSameBaseTwiceDoesNotClearTheCache`, both `("2") is not equal to ("1")`, both green
when the class is run alone.

**What the pattern says.** The two failures are exactly the tests whose assertion depends on the
in-memory icon table *retaining* an entry between two calls. The neighbouring tests that would break if
another test's traffic were landing in the shared request log — `test_reconfiguringClearsTheCache`,
which expects 2 and would have read 3, and `test_disablingStopsRequestsImmediately`, which asserts the
count at 1 — passed. A lost cache entry fits; a polluted counter does not.

**What was not observed.** No run in this session reproduced it, so the eviction itself was never
watched happening. The diagnosis above is inference from which tests failed, not a captured trace.

**What was done about it, and why it is safe either way.** `FaviconLoader`'s dedupe table stops being an
`NSCache` and becomes an explicit dictionary with a stated bound of 512 domains and a stated eviction
rule (oldest fetched first). `NSCache`'s thread-safety buys nothing inside an `actor`, and its
discretionary discarding is the only behaviour it added — which is precisely the behaviour the tests
assert against. A new test pins the bound: fill past it, and the oldest domain refetches while the
newest does not. That test would fail if eviction stopped happening *or* if the table were unbounded,
which is the pair of properties `NSCache` provided implicitly and unverifiably.

The request recorder in those tests additionally now tags every request with the test that caused it,
and the two count assertions that depend on retention print that tagged log on failure. A process-global
counter should not be asked to produce per-test facts without saying whose requests it contains.

## Impact

- 1 new production file (`OffMain.swift`), registered in `project.pbxproj`.
- 1 new test file, 4 tests.
- 1 knob in `MockPrizmCryptoService` so the mock can simulate a slow bulk operation.
- `FaviconLoader`'s icon table: `NSCache` replaced by a bounded dictionary, 1 new test.
- Documentation: six `-scheme "Vitrine"` command lines in `DEVELOPMENT.md`, `CLAUDE.md` and an archived
  change's notes are corrected back to `"Prizm"`. The shared scheme was never renamed — the product
  rename swept markdown indiscriminately and made the documented build and test commands unrunnable.
  `CLAUDE.md`'s test command also gains the no-signing flags CI passes. That part is not caused by the
  rename: `DEVELOPMENT.md` already told readers to add them, and a local `LocalConfig.xcconfig` with an
  empty `DEVELOPMENT_TEAM` has always needed them. The rename only changed the wording of the error.
- No API, wire-format, or UI change; no new strings.
