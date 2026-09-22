# Session teardown — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`. Until the test target compiles,
> none of the tests below can run. Tasks are written test-first for that reason.

## 1. The epoch

- [x] 1.1 Failing tests for `SessionEpoch`:
      - [x] 1.1.1 a freshly built epoch reports a token as current
      - [x] 1.1.2 `advance()` makes every previously issued token stale
      - [x] 1.1.3 two successive advances each invalidate the previous token
      - [x] 1.1.4 tokens are not reused: an epoch advanced twice never reports the first token as
            current again (the property that distinguishes a counter from a boolean flag)
- [x] 1.2 `SessionEpoch` in `Prizm/Domain/SessionEpoch.swift`, as an `actor`.
      → **deviation: it is a `@MainActor final class`, not an `actor`.** Found while implementing
      (see design "The teardown has to survive its own side effects"). Capturing the token has to be
      *synchronous*: a view model that reads the epoch inside a `Task` can be pre-empted between
      deciding to sync and recording which session that was for, and a lock landing in that gap hands
      the sync the **new** session's token — so it applies its result to a session it does not belong
      to, which is the exact failure this type exists to prevent. `@MainActor` matches the isolation
      of the lock paths and the view model, so those reads are immediate; the sync repository is an
      actor and reaches it with an `await`.
- [x] 1.3 `SyncError.sessionEnded` in `Prizm/Domain/Repositories/SyncRepository.swift`. Confirm any
      exhaustive `switch` over `SyncError` still compiles, and that no user-facing string is
      required for it (it is never reported — see design Decision 4).
      → no exhaustive switches broke. A `localizedDescription` **was** added anyway, because
      `LocalizedError` is exhaustive over the cases and the compiler requires one; nothing presents
      it to the user, since both call sites discard the error before it reaches a banner.

## 2. The view model teardown

- [x] 2.1 Failing tests for `clearSessionState()`, one per category of content:
      - [x] 2.1.1 the item list is empty
      - [x] 2.1.2 the selection is nil
      - [x] 2.1.3 folder names are gone
      - [x] 2.1.4 organisation and collection names are gone
      - [x] 2.1.5 the search query is cleared and global search is exited
      - [x] 2.1.6 reveals are discarded
      - [x] 2.1.7 pending re-prompt state and its error are cleared
      - [x] 2.1.8 banner/alert error strings are cleared
- [x] 2.2 `clearSessionState()` on `VaultBrowserViewModel`, covering the 2.1 list plus the create
      sheet, the backup sheet and the item counts.
      → **addition:** it also sets `sessionStateCleared` first, and the four `refresh*` methods no-op
      while it is set. Without that, clearing `searchQuery` schedules a refresh that reads the item
      list back out of the vault store — harmless only because both callers empty the store first.
      That is ordering-by-luck, and it has a live failure path when a racing sync repopulates the
      store in between. See design "The teardown has to survive its own side effects".
- [x] 2.3 Confirm `RootViewModel.selectedLogin` is nil after the teardown — it is derived from
      `itemSelection`, so clearing the selection must clear it. Assert on the derived property, not
      on the mechanism.

## 3. The copy commands

- [x] 3.1 Failing test: `selectedFieldAvailable(_:)` is `false` for every field once the vault is
      locked, even though the selection would otherwise supply one.
- [x] 3.2 Failing test: it is `true` for a field the selection supplies while the vault is unlocked
      (the regression guard for 3.1 — a gate that is always closed is not a gate).
- [x] 3.3 Add the unlocked check to `selectedFieldAvailable(_:)`.

## 4. The repository refuses a dead session

- [x] 4.1 Failing test: a sync whose epoch advanced mid-flight throws `SyncError.sessionEnded`.
- [x] 4.2 Failing test: that sync populated neither the key cache, nor the org key cache, nor the
      vault store, nor the offline cache. (Assert on each, not on the thrown error — the error being
      right while a write slipped through is the failure mode being guarded.)
- [x] 4.3 Failing test: a sync whose epoch did **not** move still populates everything as before.
- [x] 4.4 Capture the epoch at the top of `SyncRepositoryImpl.sync()` and check it before the
      populate/cache-write tail.
      → **stronger than specified:** one check is not enough. A check placed only after the fetch is
      too early to catch a lock during the decryption of a large vault, and one placed only before
      the tail is too late — the key caches were already written. So there is a `requireLiveSession`
      call before *each* group of writes (after the fetch, before the per-cipher key cache, before
      the org key cache, before the commit tail). The org ciphers' per-item keys were moved into the
      commit tail so that the worst case is a smaller number of write sites to reason about.
      Remaining gap, recorded rather than papered over: a write that passes its check can still land
      microseconds later while a lock is clearing the same cache. Closing that needs mutual exclusion
      between the commit and the teardown; what would remain is key bytes in a cache no unlocked code
      path can read, since the crypto service refuses to hand out keys once locked.

## 5. The view model refuses a dead session

- [x] 5.1 Failing test: a background sync that completes after the epoch advanced leaves the view
      model untouched — no items, no counts, no timestamp, and **no error banner**.
- [x] 5.2 Failing test: the same for a manual sync.
- [x] 5.3 Failing test: `isSyncing` is cleared even when the result is discarded (a flag left set
      disables every later sync).
- [x] 5.4 Add the epoch check to `performSync(origin:)` around the use-case call.

## 6. App wiring

- [x] 6.1 Failing test: `lockVault()` leaves `RootViewModel.selectedLogin` nil and the view model
      cleared.
- [x] 6.2 Failing test: `signOut()` leaves the same set cleared — asserted against the same
       expectations as 6.1, so a property cleared on one path and not the other fails.
- [x] 6.3 Failing test: `lockVault()` advances the epoch **before** its teardown `await`s, so a sync
      completing during the teardown already sees the new one.
- [x] 6.4 `AppContainer` builds one `SessionEpoch` and injects it into `SyncRepositoryImpl` and into
      the browser view model; `RootViewModelDependencies` exposes it to `RootViewModel`.
- [x] 6.5 Update every `VaultBrowserViewModel(...)` and `SyncRepositoryImpl(...)` construction site
      (9 and 3 respectively, most of them in `PrizmTests`).

## 7. Documentation

- [x] 7.1 `SECURITY.md`: the lock section states what is actually cleared — the decrypted item list
      and selection go with the keys, and in-flight work cannot restore them.
- [x] 7.2 Check whether the "Memory dump after lock" threat-model line is still exactly true, and
      correct it if this change makes it more true than it was (it currently claims no usable *keys*
      survive; the new claim is that no usable *plaintext* survives either).

## 8. Verification

- [x] 8.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
      → **1307 passed / 0 failures** (baseline 1280; +27 from this change).
- [ ] 8.2 Manual: select a login, lock the vault, and confirm the Copy Password / Copy Username / Copy
      Code / Copy Website menu items are disabled on the unlock screen.
- [ ] 8.3 Manual: start a sync and lock immediately (⌘R then ⌘L in quick succession); confirm the
      unlock screen shows no item list, and that the log reports the sync as `sessionEnded` rather
      than as a failure.
- [ ] 8.4 Manual: unlock, select an item, lock, unlock again, and confirm the item list is repopulated
      from a fresh sync rather than showing stale entries from before the lock.

> **8.2–8.4 are outstanding.** Each needs a running signed app against a live Vaultwarden account and
> a way to race a real network fetch against a real lock — neither of which the agent that wrote this
> change has. The logic is covered by unit tests on both sides of the boundary (`SessionEpochTests`,
> `SyncRepositorySessionEpochTests`, `VaultBrowserViewModelSessionTeardownTests`,
> `VaultBrowserViewModelSessionEpochTests`, `RootViewModelSessionTeardownTests`); what is unproven is
> that the ordering holds in a real process with a real sync in flight. Do not mark these done on the
> strength of the suite.
