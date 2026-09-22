# Background sync — Design

## Context

`SyncRepositoryImpl.sync` is called from exactly two places: the unlock path
(`UnlockUseCaseImpl.execute`) and `VaultBrowserViewModel.performManualSync()` (⌘R / `View ▸ Sync
Now`). Both are user-initiated, in the sense that both happen because the user did something. A
session that nobody touches for four hours has the vault it unlocked with, four hours old.

The machinery a timer needs already exists and is worth naming, because the design is mostly about
reusing it rather than adding to it:

- `VaultIdleMonitor` (`Prizm/App/VaultIdleMonitor.swift`) is the pattern: a `@MainActor` protocol, an
  injected `now: () -> Date`, `start()`/`stop()`, and the decision exposed as a plain method so a test
  drives the decision and never the timer. Its doc comment states the reason — "testing a 15-minute
  timeout would mean waiting 15 minutes" — and the same argument applies to a 5-minute interval.
- `VaultBrowserViewModel.performManualSync()` already has the shape a background tick wants: `guard
  !isSyncing`, `isSyncing = true`, `defer { isSyncing = false }`, `handleSyncCompleted(syncedAt:)` on
  success, `handleSyncError` on failure.
- `SyncError.syncInProgress` already names the "two syncs at once" problem at the repository layer.
- `RootViewModel.updateIdleMonitoring(for:)` (`PrizmApp.swift:772`) is already the single place that
  reacts to the locked/unlocked transition by starting and stopping a timer.
- `VaultBrowserViewModel.editSheetOpen` is already kept current by
  `ItemDetailView`'s `handleEditSheetState(_:)`.

## Decision 1 — a separate monitor, not a second timer inside the view model

`BackgroundSyncMonitor` sits beside `VaultIdleMonitor` with the same shape, for the same reason: it is
a `Timer` and two `NSNotification` observers, none of which a unit test should install. The monitor
knows two things — that an interval elapsed, and that the app just came back — and it asks a decision
function whether that means "sync now". The view model answers.

The alternative, threading a timer through `VaultBrowserViewModel`, was rejected because that type is
already the largest in the presentation layer and because it would put AppKit notification
observation into a type that `PrizmTests` constructs directly.

## Decision 2 — 300 seconds, and no setting

The default vault timeout is **15 minutes** (`VaultTimeoutSettings.swift:85`). An interval longer
than that would mean the timer frequently never fires at all: the vault locks first, and the session
it was going to refresh is gone. Bitwarden's own 30-minute figure is above this project's default
lock, which is why it is not copied.

Five minutes gives at least two ticks inside a default-configured idle session, and three inside a
session that is actively being used (activity postpones the lock, so it can run much longer).

Not configurable, because the setting would be a row the user has no basis to set: the difference
between 5 and 15 minutes of staleness is not something anyone can evaluate without knowing the sync
cost, and the honest answer is that both are fine. If it later needs to change, it changes as a
constant.

## Decision 3 — reactivation and wake are the triggers that carry the feature

A pure interval is a poor fit for how a Mac is used. The common case is not "the app has been open
for five minutes"; it is "the laptop was shut, reopened this morning, and the vault is now a day
old". A 5-minute tick will get there — after up to five minutes of the user working against stale
data.

So the monitor also listens for `NSApplication.didBecomeActiveNotification` (the user came back to
Prizm) and `NSWorkspace.didWakeNotification` (the machine came back). Both are throttled by the same
decision function: a tick is suppressed if the last successful sync was recent, so switching windows
rapidly does not produce a sync per switch. `lastSuccessfulSyncAt` is the input, not "time since last
attempt", so a run of failures does not turn into a retry storm either.

## Decision 4 — reuse `isSyncing` and the manual sync path; do not add a second in-flight flag

A second flag would mean two ways to be syncing and one `guard` that checks the wrong one — which is
precisely the defect `SyncError.syncInProgress` exists to prevent. `performManualSync()` is split into
a shared `performSync(origin:)` with the in-flight guard in one place, and the origin (`manual` /
`background`) decides only what happens *afterwards*: a manual sync reports its failure to the user, a
background sync does not.

Consequence, accepted: the toolbar's sync indicator appears during a background sync, and ⌘R is
disabled for its duration. That is accurate — a sync is running — and a second sync started from ⌘R
while one is in flight would be refused anyway.

## Decision 5 — refuse to refresh a session that is mid-edit

`handleSyncCompleted` calls `refreshItems()`, `refreshCounts()`, `refreshFolders()`,
`refreshOrganizations()` and `refreshItemSelection()`. The last of those replaces `itemSelection` with
the store's copy of the selected item. That is correct after a user-requested sync and wrong during a
background one if the user is currently editing that item: the edit sheet holds a draft, and the
draft's base is the value the sheet was opened with.

So the background path asks first, and refuses when:

- the edit sheet is open (`editSheetOpen`), or
- a mutation is in flight (a second flag, distinct from `isSyncing`, set by the delete / duplicate /
  save paths) — the same reasoning: a refresh landing between a write and the store's update would
  make the list disagree with the server in a way the next sync would not necessarily repair.

The tick is **dropped, not deferred** — there is no queue to hold it, and holding one would mean the
app fires a sync at the moment the sheet closes, which the user experiences as "the list jumped the
instant I closed the editor". The next tick is at most five minutes away, and the reactivation
triggers mean it is usually sooner.

## Decision 6 — a failed background refresh is logged and left to age the label

`handleSyncError` sets `syncErrorMessage`, which the sync-status banner renders as a dismissable
error. That is right for ⌘R: the user asked, so they should be told. It is wrong for a background
tick — a user working offline would get a banner every five minutes to dismiss, about a sync they did
not request, and would learn to treat the banner as noise. (Becoming noise is worse than not
appearing: the same banner is how a *manual* failure is reported.)

So a background failure:

- **logs** at `error` with the reason, which is where the diagnosis lives,
- **leaves `lastSyncedAt` alone**, so the sidebar keeps ageing honestly — "Synced 43 minutes ago" is
  the user-visible signal that refreshes are not landing, and it is a true one,
- sets nothing dismissable.

This is not a silent failure. The Constitution's no-silent-failures rule asks that a failure be
observable and diagnosable; a log line plus a label that visibly ages satisfies both, and the rule
does not require every failure to interrupt the user.

## Decision 7 — never while locked

The monitor is started and stopped by the same screen transition that drives the idle monitor
(`updateIdleMonitoring(for:)`), so `.vault`/`.syncing` run it and every other screen stops it. A
background sync with the vault locked would have to keep the user key resident to decrypt the
response, which is the exact state `lockVault()` exists to destroy and `SECURITY.md` claims does not
persist. An unattended refresh is not worth a weakened lock guarantee.

## Verification

The unit tests cover the decision function (interval elapsed, reactivation too soon, busy session,
locked session) and the post-sync routing (background failure does not set the banner; manual failure
does). What they cannot cover is the wiring, so the manual check that matters is: leave the app open
and unlocked past the interval with an item changed on the server, and watch it appear without
pressing anything; then the same with the network off, and confirm no banner appears and the label
ages.
