# Background sync — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`. Until the test target compiles,
> none of the tests below can run. Tasks are written test-first for that reason.
>
> **Ordering note:** this change is independent of `offline-vault-cache` in code, but the two meet in
> `performSync`: a background refresh against an unreachable server will now consult the cache and
> succeed from it. Whichever lands second should add the cross-check that a cache-sourced background
> refresh does not move `lastSyncedAt` to the cache's write time.

## 1. The decision

- [x] 1.1 Failing tests for `BackgroundSyncMonitor.shouldSync(...)`, driving the clock explicitly:
      - [x] 1.1.1 interval elapsed since the last successful sync → true
      - [x] 1.1.2 interval not elapsed → false
      - [x] 1.1.3 interval elapsed but the session is locked → false
      - [x] 1.1.4 reactivation before the throttle has elapsed → false
      - [x] 1.1.5 reactivation after the throttle, when the last successful sync is recent → false
      - [x] 1.1.6 edit sheet open → false, regardless of the interval
      - [x] 1.1.7 mutation in flight → false, regardless of the interval
      - [x] 1.1.8 a run of failures does not shorten the interval: a failed attempt does **not** reset
            the clock the interval is measured from (only success does), so failure cannot produce a
            retry storm
            → **note:** expressed as the absence of a "last attempt" input. There is no clock for a
            failure to reset, and the test pins that a success is the only thing that moves the
            baseline. A test that merely re-asserted 1.1.1 after a failure would pass for the wrong
            implementation too.
- [x] 1.2 `BackgroundSyncMonitor` in `Prizm/App/BackgroundSyncMonitor.swift`: the `@MainActor`
      protocol (`start()`, `stop()`, `onTick`), the interval and throttle constants, and the decision
      method. No `Timer`, no notification observers yet.
      → **addition:** the protocol also declares `shouldSync(trigger:isUnlocked:isBusy:lastSuccessfulSyncAt:)`.
      The decision has to be reachable through the injected `any BackgroundSyncMonitoring`, or
      `RootViewModel` could not ask it and the tests would have no way to stub the answer.

## 2. The wiring inside the monitor

- [x] 2.1 `start()` installs the repeating `Timer` and the two notification observers, is idempotent,
      and installs nothing twice.
- [x] 2.2 `stop()` invalidates and releases both, and is idempotent.
- [x] 2.3 `deinit` does not leak the timer or the observers (mirror `VaultIdleMonitor.deinit`).
- [x] 2.4 Observers are `nonisolated(unsafe)` with mutation confined to MainActor, following
      `VaultIdleMonitor`'s stated reason (`deinit` is nonisolated in Swift 6 and neither a `Timer` nor
      an observer token is `Sendable`).
- [x] 2.5 A tick that the decision refuses is a no-op: no sync, no state change, no log at `error`
      level.
      → **where it is enforced:** the monitor emits, the app layer decides. A refused tick is covered
      by `RootViewModelBackgroundSyncTests.test_tick_isANoOpWhenTheDecisionRefuses`.

## 3. The sync path

- [x] 3.1 Failing test: `performSync(origin: .background)` sets and clears `isSyncing` exactly as the
      manual path does.
- [x] 3.2 Failing test: a background sync requested while `isSyncing` is already true performs no
      second sync (the guard is shared, not duplicated). Tested in both directions.
- [x] 3.3 Failing test: a background **failure** does not set `syncErrorMessage`.
- [x] 3.4 Failing test: a **manual** failure still sets `syncErrorMessage` (the regression guard for
      3.3 — the two origins must not be collapsed).
- [x] 3.5 Failing test: a background failure does not call `recordSuccessfulSync()`, so `lastSyncedAt`
      is unchanged.
- [x] 3.6 Failing test: a background **success** calls `handleSyncCompleted` and refreshes items,
      counts, folders and organizations.
- [x] 3.7 Refactor `performManualSync()` into `performSync(origin:)`; keep `performManualSync()` as
      the manual entry point so existing call sites and tests do not change.
- [x] 3.8 Add `isMutating` (or equivalent) set by the delete, duplicate and save paths, cleared on
      completion. Must be cleared on the failure path too — a flag left set disables background sync
      for the rest of the session.
      → **deviations:** (a) it is a counter, not a flag — two writes can overlap, and the first to
      finish must not clear the state the second still needs. (b) The **save** path is covered by
      `editSheetOpen` instead: the edit sheet stays open for the whole of `ItemEditViewModel.save()`,
      and the decision checks that first. The counter is set by delete, restore, permanent delete,
      duplicate, favourite toggle, move-to-folder and empty-trash.

## 4. App wiring

- [x] 4.1 `RootViewModel` owns the monitor and starts/stops it from the same transition as the idle
      monitor — extend `updateIdleMonitoring(for:)` or add a sibling called from the same place, so
      the two cannot drift.
      → **chosen:** extended, and renamed `updateSessionMonitoring(for:)`. One method driving both is
      the strongest form of "cannot drift"; a sibling leaves the next transition free to call one.
- [x] 4.2 Failing test (stub monitor): the monitor is started on `.vault` and `.syncing`, and stopped
      on `.login`, `.loading`, `.twoFactorPrompt`, `.unlock`.
- [x] 4.3 Failing test (stub monitor): `lockVault()` and `signOut()` leave the monitor stopped.
- [x] 4.4 `AppContainer` constructs the monitor; `RootViewModel` receives it by injection so tests
      substitute a stub.
- [x] 4.5 The monitor's tick handler routes to `vaultBrowserVM` on MainActor; the view model is
      optional at that point (it does not exist before the first unlock) and a tick with no view model
      is a no-op.
      → **note:** `RootViewModel.vaultBrowserVM` is non-optional and built in `init`, so there is no
      window in which a tick could arrive with no view model — the monitor is stopped until the
      vault unlocks. The handler carries an explicit `isVaultUnlocked` guard anyway, and that path is
      tested (`test_tick_whileLocked_isIgnored`).

## 5. Presentation

- [x] 5.1 Confirm no new user-visible string is required: the ageing label is the existing
      `syncStatusLabel`. If a string is needed for anything, add it to
      `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings`.
      → confirmed: no new keys. The failure signal is the existing label ageing, which already
      localizes.
- [ ] 5.2 Check the toolbar sync indicator appearing on a background tick does not steal focus or
      interrupt typing in the search field or an open edit sheet (Decision 4's accepted consequence —
      verify it is only cosmetic).
      → **outstanding:** this is a UI observation and cannot be made without a running signed app
      against a live account. See the note under section 7.

## 6. Documentation

- [x] 6.1 `SECURITY.md`: remove or correct the claim that the vault is fetched once per unlock; state
      that refreshes happen while unlocked and stop when locked.
      → added to **Data in transit** ("When the app talks to the server"): what a refresh sends, how
      often, and that a locked session makes no requests at all.
- [x] 6.2 `README.md`: the "no background sync" limitation note.
      → it was a roadmap row, not a limitation. Moved to Now, and a **Background refresh** feature
      bullet added.
- [x] 6.3 `FEATURE-GAP-ANALYSIS.md`: mark the background-sync row as implemented, and check the
      `CLAUDE.md` "Active Changes" table is not left pointing at this change after it is archived.
      → the table pointed at two changes already in `archive/`; replaced with the two live ones.

## 7. Verification

- [x] 7.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
      → **1280 passed / 0 failures** (baseline 1214; +33 from this change, +33 from
      `offline-vault-cache`).
- [ ] 7.2 Manual: unlock, leave the app open and idle, change an item on the server, confirm it
      appears without any user action and that the sidebar label resets.
- [ ] 7.3 Manual: with the app open and unlocked, disable the network, wait past the interval, confirm
      **no** banner appears and the label visibly ages. Re-enable the network, confirm the next tick
      succeeds and the banner never appeared.
- [ ] 7.4 Manual: open the edit sheet on an item and hold it open across an interval, confirm no
      refresh occurs and the draft is untouched; close the sheet and confirm the list does not jump
      until the next tick.
- [ ] 7.5 Manual: lock the vault and leave it locked past the interval, confirm no network traffic
      (the monitor is stopped, not merely refusing).
- [ ] 7.6 Manual: sleep and wake the machine with the app unlocked, confirm a refresh fires on wake
      rather than after the remaining interval.

> **7.2–7.6 (and 5.2) are outstanding.** Each needs a running signed app, a live Vaultwarden account,
> a five-minute wait and a way to take the network down — none of which the agent that wrote this
> change has. The decision, the post-sync routing and the start/stop wiring are covered by unit tests;
> what is unproven is that the `Timer` and the two observers actually fire in a real process, which is
> precisely the part the seam exists to keep out of the tests. Do not mark these done on the strength
> of the suite.

## Cross-check with `offline-vault-cache`

- [x] Whichever of the two changes lands second adds the check that a **cache-sourced** background
      refresh does not move `lastSyncedAt` to the cache's write time.
      → `VaultBrowserViewModelBackgroundSyncTests.testBackgroundSync_cacheSourced_doesNotMoveTheTimestamp`.
