# Bounded waits and an import preflight — Proposal

## Why

Two places where this app waits with no upper bound, found while working the release-readiness list.

**Import.** `requestImport()` called `Data(contentsOf:)` on whatever file the picker returned. A
mistaken selection — a database dump, an archive, a disk image — was committed to memory in full
before anything got round to rejecting it, and the read is a `Task.detached`, which does not inherit
cancellation, so dismissing the progress sheet could not stop it either.

**SSH agent.** `SSHAgentAuthorizer.authorize` suspended on a continuation until the user answered the
master-password prompt. Unanswered, it stays suspended: the responder is parked on it,
`SSHAgentServer.awaitResponse(to:)` is parked on the responder, and the `git` that asked hangs until
the app quits. The type already knew this was the failure to avoid — `revokeAll()` resumes every
continuation with the comment "a request left suspended is a socket thread blocked forever" — but that
only runs on lock and sign-out. Nobody answering is a different thing from the vault locking.

## What changes

- **Import is sized before it is read.** `url.resourceValues(forKeys: [.fileSizeKey])` answers without
  touching the contents; above 64 MB the file is refused with a message naming both the file's size and
  the limit, and no sheet opens. 64 MB is not a claim about how large a vault can be — ten thousand
  items is single-digit megabytes — it is the point past which the file almost certainly is not a vault
  export.
- **The import task checks cancellation before and after the read.** The read itself cannot be
  interrupted (`Data(contentsOf:)` never looks at the task's flag), so the honest fix is to bound it
  and to not start or continue work once it has been dismissed. The item loop was already cancellable
  (`ImportVaultUseCaseImpl.swift:43`).
- **An unanswered SSH prompt is refused after two minutes.** Timed from **promotion**, not arrival: a
  request queued behind one the user is still reading has not been shown, and refusing it unseen would
  be the app timing out its own queue. The window is injectable so the tests do not take two minutes.
- **`refuse(id:)` no longer closes the sheet for a request that was not on it.** It had one caller
  before, always the pending one; a timeout can now fire on a queued request, and the old
  unconditional `pending = nil` would have dismissed a prompt the user was looking at.

## Corrections to the record

The defect inventory described import as "uncancellable, no size limit". The first half was wrong:
`dismissBackupSheet()` does cancel the task and the use case's loop honours it. Only the detached read
is outside cancellation, and only the missing size bound was unconditionally true. Fixed here, and the
inventory entry corrected.

## Deliberate limits

- `SSHAgentServer.awaitResponse(to:)` keeps its unbounded `semaphore.wait()`. Its upstream is now
  bounded, so a second deadline in the server would be a second owner of one timeout, and the two
  would disagree about what expired.
- A file whose size cannot be read is let through. The failure being prevented is a mistaken
  selection, not a hostile one; refusing a legitimate export because a volume declined to report a
  length trades a real breakage for a hypothetical one.
- The 64 MB cap is a constant, not a setting. A preference for "how large a mistake you are allowed to
  make" is not worth a screen.

## Impact

- 5 new tests (2 import preflight, 3 answer window).
- 1 new string in each table.
- No protocol changes; `SSHAgentAuthorizer`'s new init parameter is defaulted, so every existing call
  site compiles untouched.
