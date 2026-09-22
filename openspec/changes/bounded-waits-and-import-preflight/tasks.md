# Tasks — bounded waits and an import preflight

## 1. Import preflight

- [x] 1.1 `VaultBrowserViewModel.importFileRejection(for:)` — metadata only, never the contents.
- [x] 1.2 `ImportLimits.maximumFileBytes = 64 MB`, with the reasoning for the number at the constant.
- [x] 1.3 The rejection message names both the file's size and the limit; a bare "too large" sends the
      user to look for a setting that does not exist.
- [x] 1.4 Unknown size is allowed through, and the reason is written down rather than left as a
      permissive-looking hole.
- [x] 1.5 `if Task.isCancelled { return }` before and after the detached read. The read itself is not
      interruptible — `Data(contentsOf:)` never checks the flag — so the fix is to bound it and to
      refuse to continue after a dismissal, not to pretend it can be aborted.

## 2. SSH answer window

- [x] 2.1 `SSHAgentAuthorizer.answerWindow`, default 120 s, injectable for tests.
- [x] 2.2 Armed in `promoteNextIfIdle()`, i.e. when a request reaches the screen.
- [x] 2.3 No task handles kept: the expiry re-checks `pending?.id`, so a stale deadline finds nothing to
      do. Cancelling on every transition would be a second trail of bookkeeping that can disagree.
- [x] 2.4 `refuse(id:)` clears `pending` only when the refused request was the one on screen.

## 3. Tests

- [x] 3.1 Import: an 80 MB **sparse** file is refused before being read. `truncate(atOffset:)` makes
      the test allocate nothing, which is the same property the preflight relies on. The assertion
      checks for "64.0" in the message, so it cannot pass on a generic error string.
- [x] 3.2 Import: a missing file still fails as a missing file, not as an oversized one.
- [x] 3.3 Agent: an unanswered prompt is refused, nothing is ever checked, and the awaiting call
      returns — this test cannot pass without the deadline, because `await request.value` would never
      resume.
- [x] 3.4 Agent: at one window past arrival the queued request is **on screen**, not refused. This is
      the assertion that distinguishes "timed from promotion" from "timed from arrival" — the latter
      leaves `pending` nil and fails.
- [x] 3.5 Agent: a request answered inside its window keeps its grant after the deadline passes.
- [ ] 3.6 **Not covered:** that a real `git push` against the live agent is released after two minutes.
      `SSHAgentServerTests` drives the socket directly and never reaches the authorizer's window; the
      end-to-end behaviour needs the app running with the agent enabled.

## 4. Verification

- [x] 4.1 Targeted: `SSHAgentAuthorizerTests` + `SSHAgentServerTests` + `SSHAgentCoordinatorTests` —
      46 passed, 0 failed.
- [x] 4.2 Targeted: `VaultBrowserViewModelBackupTests` + `LocalizationResourcesTests` — 25 passed,
      0 failed (key parity across both tables).
- [x] 4.3 Full suite: **1544 passed, 0 failed, 0 skipped**, and 1544 is also the number of `func test`
      declarations in `PrizmTests` — executed set equals the whole set. (That includes 3 tests from
      `P3MainWindowScreenshotTests`, which is another session's untracked work in this tree, not this
      change's.)
