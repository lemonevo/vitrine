## Why

The vault is fetched exactly once per unlock. `UnlockUseCaseImpl.execute` calls `sync.sync(progress:)`
as its last step, and nothing calls it again — the in-memory store is populated at unlock and then
held for the life of the session. The only other caller is `View ▸ Sync Now` (⌘R), which the user has
to remember to press.

So a session drifts. Item edited in the web vault, a password rotated on another device, a new item
added by a colleague sharing a collection — none of it appears in a running Vitrine until the user
quits, or thinks to sync. The failure mode is the dangerous kind: the vault is *unlocked and looks
current*. There is no staleness cue beyond a relative timestamp in the sidebar footer, and a user who
is not looking at the footer sees an authoritative-looking list that is quietly hours old.

The official Bitwarden clients refresh on a timer while unlocked. Vitrine has the sync path, the
in-flight guard (`SyncError.syncInProgress`) and the manual trigger already; what it lacks is the
timer.

## What Changes

- A new `BackgroundSyncMonitor` in the App layer, built on the same seam as `VaultIdleMonitor`: a
  `@MainActor` protocol, an injected clock, and the decision (`shouldSync(...)`) split out from the
  AppKit and `Timer` wiring so the decision is unit-testable and the timer is not driven by a test
  clock.
- It fires **every 5 minutes while the vault is unlocked**, and additionally on **app reactivation
  and system wake**, so returning to the machine after a lunch break refreshes immediately instead of
  waiting out the remainder of an interval.
- It starts when the session becomes unlocked and stops on lock and on sign-out, from the same
  screen-transition hook that already drives the idle monitor — so the two cannot get out of step.
- It reuses the existing sync path and the existing `isSyncing` flag rather than adding a second one.
  A background tick that lands while a manual sync is running is **refused**, not queued.
- It **skips a session that is busy in a way a refresh would disturb**: while the edit sheet is open,
  or while a mutation is in flight. The tick is dropped, not deferred, and the next one picks it up.
  This is the difference between a background refresh and a background refresh that discards a
  half-written item.
- A failed background refresh is **logged and left to age the label**. It does not raise the
  dismissable error banner that a *manual* sync raises, and it does not move the last-sync timestamp.
  The user did not ask for the sync, so they are not made to dismiss the failure of one.
- The interval is a constant, not a setting.

## Non-goals

- **Syncing while locked.** A background sync with the vault locked would mean holding the user key
  resident and deriving plaintext on a timer for a session the user believes is closed. That is the
  guarantee `SECURITY.md` makes about locking, and a convenience refresh is not worth spending it on.
- **A configurable interval**, a background-sync toggle, or any new setting. The 5-minute figure is
  chosen against the default 15-minute idle lock (below); exposing it would add a row to the settings
  screen and a new class of "why is my vault stale" support question without changing the default.
- **Push, SSE, or a long-poll socket.** A server-initiated channel is a different feature with a
  different failure model, and Vaultwarden does not offer one.
- Changing what a sync *does*. This change moves the existing sync onto a timer; the sync itself —
  what is fetched, decrypted and populated — is unchanged.
- Changing `⌘R`, or the unlock-time sync.

## Capabilities

### New Capabilities

- `background-sync`: refreshing the vault on a timer and on reactivation while the session is
  unlocked, without disturbing work in progress or turning an unreachable server into a banner the
  user has to dismiss.

### Modified Capabilities

_None._

## Impact

- `Prizm/App/BackgroundSyncMonitor.swift` — **new**; the protocol, the monitor, the decision
- `Prizm/App/PrizmApp.swift` — start/stop on the session transition; the reactivation and wake hooks
- `Prizm/App/AppContainer.swift` — build the monitor and inject it into `RootViewModel`
- `Prizm/Presentation/Vault/VaultBrowserViewModel.swift` — a `backgroundSync()` entry point beside
  `performManualSync()`, sharing the in-flight guard; a way to report "busy — do not refresh now"
- `Prizm/Presentation/Vault/Detail/ItemDetailView.swift` — already reports the edit-sheet state via
  `handleEditSheetState(_:)`; the background path reads it
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — only if a new string is needed for a
  failed background refresh; the existing sync label strings may suffice
- `Prizm/PrizmTests/Mocks/` — a stub monitor for `RootViewModel` tests
- `SECURITY.md`, `README.md` — the statement that the vault is fetched once per unlock is no longer
  accurate
