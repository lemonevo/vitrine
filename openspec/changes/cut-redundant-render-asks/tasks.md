# Tasks — cut the repeated asks inside three renders

## 1. Unlock screen: one ask per render, not one per control

- [x] 1.1 `UnlockView.body` reads `biometricUnlockAvailable`, `pinUnlockAvailable`, the sensor type and
      the PIN attempt count into constants before building the card, and passes them down.
- [x] 1.2 `credentialField` and `pinField` became functions taking the values they print;
      `biometricMethodName(for:)` and `biometricSystemImage(for:)` take the sensor type instead of each
      probing `LAContext` for it.
- [x] 1.3 The availability answers stay live — read per render, never cached — because
      `UnlockViewModelBiometricTests.testBiometricUnlockAvailable_reflectsAuthRepository` requires the
      screen to follow the repository between renders, and a biometric lockout has to remove the button
      on the next draw. Recorded in the proposal as a deliberate limit.
- [x] 1.4 `UnlockViewRenderCostTests` — 4 tests, counting asks across four keystrokes: biometric 8→4,
      pin availability 4→4 (unchanged, a regression guard), PIN attempt count 12→8, and zero attempt
      reads while typing a master password.
- [x] 1.5 The harness renders through `NSHostingView`. Reading `UnlockView.body` directly was the first
      attempt and it passed against the unmodified code by reporting zero asks: a `@ViewBuilder` closure
      stored by `AuthCard { … }` is not invoked by constructing a body. Recorded in the test's own
      header comment and in the proposal, because the shape of that false green is easy to fall into
      again.

## 2. Search: a pass may only draw if it is still the current one

- [x] 2.1 `itemsPassID` bumped at the start of every pass; compared before writing `displayedItems`, in
      both the success and the failure branch.
- [x] 2.2 The query and the sidebar scope are read when the pass starts rather than after its `await`,
      which is what makes an overtaken pass identifiable. The old late read meant five overlapping
      passes all searched the newest text — never visibly wrong, always doing the work five times.
- [x] 2.3 `searchQuery`'s observer calls `refreshItems()` directly; the wrapper
      `Task { @MainActor in … }` was a second suspension point in front of one `refreshItems()` already
      starts.
- [x] 2.4 `VaultBrowserViewModelSearchCoalescingTests` — 3 tests: five overlapping queries publish the
      list once rather than five times, the newest query owns the list, a lone query still lands. The
      search double also asserts it was called five times, so the test cannot pass by suppressing work.
- [x] 2.5 No debounce, and no `Task.cancel()` in place of the comparison — see Deliberate limits.
- [x] 2.6 `global-search` delta: the list always shows the results of the query in the field, stated as
      a requirement because the implementation now depends on it.

## 3. Sidebar: the tree is built when the folders change

- [x] 3.1 `SidebarView.folderTree` and `OrgDisclosureRow.collectionTree` became `@State`, refreshed by
      `.onChange(of:initial:)`. `Folder` and `OrgCollection` are already `Equatable`/`Hashable`, so the
      comparison is free and an unchanged array rebuilds nothing.
- [x] 3.2 `FolderTreeNode.buildTree` itself untouched. Its nested-array insertion copies the enclosing
      subtree at every level, but after 3.1 it runs on a folder edit rather than on each keystroke, so
      the quadratic step is no longer in a render path. Not rewritten here.
- [x] 3.3 No test: nothing observable changed, so there is no assertion that could have been red before.
      Covered by the sidebar renders in `VaultScreenshotTests` and by the launched app below.

## 4. Verification

- [x] 4.1 Red-first proof: `VaultBrowserViewModel.swift` and `UnlockView.swift` reverted to `HEAD`,
      both new classes re-run. Search failed at 5-against-1; unlock failed at 8-against-4 and
      12-against-8. Files restored from a copy taken before the revert, and the restore confirmed by
      checksum.
- [x] 4.2 Full suite: `xcodebuild test` with the signing flags CI passes.
- [x] 4.3 **1577 tests executed, 0 failures.** The count is read from the log, not from the verdict
      line, per `AGENTS.md` — a `-only-testing:` selector that names nothing still prints
      `** TEST SUCCEEDED **`.
- [x] 4.4 `./build-app.sh` produced `dist/Vitrine.app` (executable `Prizm`, ad-hoc signed, sandbox off)
      and it was launched. Nothing was running beforehand, so no session was displaced. A comment-only
      correction afterwards needed a second build: the executable's checksum moved
      (`1fb528b2…` → `b2c5136f…`), the AppleScript `quit` event timed out (-1712) so the running
      instance was ended with `kill`, and the relaunched app is a new PID — 48725 → 49930. Replaced the
      binary rather than trusting "I rebuilt it".
- [x] 4.5 The three screens were checked as rendered pixels, from `AuthScreenScreenshotTests` and
      `VaultScreenshotTests`, which build the real views in an offscreen `NSHostingView`:
      `auth-unlock-biometric` (subtitle names Touch ID, the button and its glyph present),
      `auth-unlock-pin` (PIN field, the attempt line reading the hoisted count, the switch-credential
      control), and `vault-empty-selection` (the sidebar's FOLDERS section showing `Social` with its
      disclosure chevron, which only appears if `buildTree` nested it — so 3.1's `.onChange(initial:)`
      populates before the first draw). The auth PNGs came out the same byte size as before the change.
- [x] 4.6 What was **not** verified: the live screen. `screencapture` returns a black image in this
      session (no screen-recording permission), so the running app was confirmed by process and by the
      renders above, not by a capture of the display — and no keystroke was typed into it.
