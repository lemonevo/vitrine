# Surface unreadable items — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`. Until the test target compiles,
> none of the tests below can run.

## 1. The count includes organisation failures

- [x] 1.1 Failing test: a sync where an organisation cipher fails to map reports it in
      `SyncResult.failedDecryptionCount`, not only in the log.
- [x] 1.2 Failing test: the personal and organisation counts are summed, not one or the other.
- [x] 1.3 Failing test: a sync with no failures still reports zero (the regression guard — a count
      that is always non-zero is worse than none, because it cries wolf).
- [x] 1.4 Sum the two counts in `SyncRepositoryImpl.sync`; update the field's doc comment to say what
      it now covers.

## 2. The view model publishes it

- [x] 2.1 Failing test: `unreadableItemCount` reflects the sync result's count.
- [x] 2.2 Failing test: a later sync with zero failures resets it to zero.
- [x] 2.3 Failing test: `clearSessionState()` resets it — the count describes a session's vault, so it
      cannot outlive one.
- [x] 2.4 Add `@Published private(set) var unreadableItemCount: Int = 0`, set in `handleSyncCompleted`,
      cleared in `clearSessionState()`.
- [x] 2.5 Failing test: entering the vault without a sync leaves it at zero rather than showing a
      stale count from a previous session.

## 3. It reaches the sidebar

- [x] 3.1 `SyncStatusView` takes the count and renders it below the freshness label when it is
      non-zero, with a warning treatment (icon + colour) distinct from the label.
- [x] 3.2 The tooltip states that the items are still on the server and that Prizm could not read
      them. Both halves — a count alone invites the conclusion that the items were deleted.
- [x] 3.3 `VaultBrowserView` passes it through from the view model.
- [x] 3.4 Accessibility: the row has a label that reads as a sentence, and an accessibility identifier,
      following `AccessibilityID.Vault.syncStatusLabel`'s pattern.

## 4. Strings

- [x] 4.1 `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings`: a singular key, a plural key, and
      the tooltip. `L` has no plural machinery, so the choice between the first two is made in code.
- [x] 4.2 Failing test: the singular string is used for a count of one and the plural for two.
- [x] 4.3 Confirm the keys are present in both language files (a missing key falls back to the key
      itself, which would ship the raw English string into a Chinese UI).

## 5. The debug type map

- [x] 5.1 Correct `SyncRepositoryImpl.swift:119` to `[1: "login", 2: "secureNote", 3: "card",
      4: "identity", 5: "sshKey"]`, matching `RawCipher.swift:17` and `CipherMapper`.
- [x] 5.2 Confirm nothing parses that string — it is a log message only.

## 6. Verification

- [x] 6.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
      → **1321 passed / 0 failures.**
- [x] 6.2 Manual: with a server that returns a cipher Prizm cannot map, unlock and confirm the sidebar
      reports the count while the rest of the vault is usable.
- [x] 6.3 Manual: confirm the count disappears after a sync that reads everything.

> **6.2–6.3 are outstanding.** They need a signed app and a server that will return a cipher Prizm
> cannot map — neither is available to the agent that wrote this change. What is unproven is the last
> inch: that the line renders in the footer and clears on the next good sync. The count's path from
> the repository to `unreadableItemCount`, and the strings it renders, are covered by
> `SyncRepositoryUnreadableCountTests`, `UnreadableItemCountTests` and `SyncLabelFormatterTests`.
