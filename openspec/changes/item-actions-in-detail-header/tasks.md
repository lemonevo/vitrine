# Item actions in the detail header — Tasks

## 1. Move the item's commands

- [x] 1.1 `ItemDetailView` gains `onToggleFavorite`, defaulting to nil like its sibling callbacks.
- [x] 1.2 `itemHeader`'s trailing cluster: `favoriteToggle(for:)` + `Button(L("Edit"))`. Both hidden
      when `item.isDeleted` (D3).
- [x] 1.3 The display-only `if item.isFavorite { Image("star.fill") }` is gone, replaced by the control
      (D2).
- [x] 1.4 ⌘E and `AccessibilityID.Edit.editButton` moved with the button; new
      `AccessibilityID.Detail.favoriteToggle` = `detail.favorite`.
- [x] 1.5 `VaultBrowserView`: the detail toolbar now carries only the trash pair; `onToggleFavorite`
      wired to the existing `viewModel.toggleFavorite(item:)`.

## 2. Type-checker fallout

- [x] 2.1 Adding one closure argument to `ItemDetailView(...)` pushed `NavigationSplitView { } content:
      { } detail: { }` past what the checker will infer — the failure this file already documents twice.
      Fixed by extracting, not by splitting an expression arbitrarily: `syncToolbarItem`,
      `newItemToolbarItem`, `trashToolbarItems` and `detailColumn` are now named properties.
- [x] 2.2 Behaviour is unchanged by the extraction; it is the same view tree.

## 3. Verification codes countdown

- [x] 3.1 `CountdownRing` extracted from `TOTPCodeView` to file scope, in the same file (D4).
- [x] 3.2 `VerificationCodeRowView.codeCell` — bar replaced by ring + `L("%ds", seconds)`, shown only
      when the row reports seconds. `Spacing.codesCountdownWidth` keeps the copy button still as the
      number loses a digit.
- [x] 3.3 Both keys already existed and are already translated; no strings added.

## 4. Verification

- [x] 4.1 App builds (`swift build --disable-sandbox`).
- [x] 4.2 Full `PrizmTests`: **1491 passed, 0 failed, 0 skipped**.
- [x] 4.3 Rendered the real screens: `vault-login.png` (header star + Edit at the trailing edge) and
      `codes.png` (ring + `28s` on every row). `codes.png` is a new harness case, so the countdown stays
      visible to the screenshot tests from here on.
- [x] 4.4 The design options were rendered from a mock `NavigationSplitView` before choosing — see
      `/tmp/prizm-design/chrome-compare.png`. That probe file was a decision tool and has been deleted
      rather than left as rotting mocks.
- [x] 4.5 Deltas written for `detail-column-header` (which also retires a `[Delete]` requirement the
      code stopped honouring), `toggle-favorite` and `voiceover-labels`; `ui-redesign`'s pending
      `detail-card-view` delta amended so the two do not contradict at archive time.

## 5. Found while looking at the result: the countdown never reached the screen

The user reported the ring and the seconds sitting frozen at the instant the sheet opened. They were
right, and it was worse than a missing animation:

- ❌ **`VerificationCodeRowView` held its `TOTPCodeViewModel` as a plain `let`** — no subscription, so
  the cell drew once and never again. `displayCode` was frozen by the same omission, so **an expired
  code stayed on screen looking current** until the sheet was reopened.
- ✅ Fixed by giving the cell its own type with `@ObservedObject var code`. The view model was correct
  throughout — it refreshes every second and re-aligns to the step boundary — which is why its own tests
  never caught any of this.
- ✅ `testCodesCountdownReachesTheView` guards it. **The first version of that test was wrong and the
  mutation check caught it**: it rendered the sheet twice, in two separate windows, 3 real seconds
  apart, and passed with the defect still in place — two fresh windows differ for reasons unrelated to
  ticking. The rewrite captures one window twice and advances the clock by calling `refresh(at:)`
  directly, because a main-queue `Task { @MainActor }` continuation cannot run inside
  `RunLoop.run(until:)` when the test itself is a block on the main queue. Verified both ways: fails
  with `@ObservedObject` reverted to `let`, passes with the fix.
- Full suite after: **1492 passed, 0 failed, 0 skipped**.

## 6. Deliberately not done / follow-up

- 5.1 **The trash pair stays in the toolbar** (D3). If it is ever unified, `destructive-action-styling`
      moves with it.
- 5.2 `"Restore"` and `"Delete Permanently"` in that toolbar are still untranslated string literals, so
      the Chinese interface shows them in English. Same class as the `Edit` literal fixed here; left
      because it is outside the scope chosen.
- 5.3 Whether ⚙ Settings belongs in a titlebar at all — the other half of "this row looks wrong" — is
      untouched.
- 5.4 `Prizm/UITests/EditItemJourneyTests` looks the button up as `app.buttons["edit.button.edit"]`.
      The identifier moved with the button so the lookup still holds, but those files are in no test
      target and never run (defect A.2 in the audit), so this is reasoning, not verification.

## 7. Not verified

- 6.1 **The production toolbar after the change was never captured.** See design D6 — the mock renders
      the same AppKit chrome, but that the real titlebar now shows five controls is a look-at-the-app
      step.
- 6.2 VoiceOver ordering of the new header cluster, and ⌘E from inside the list / search field / an
      open sheet.
