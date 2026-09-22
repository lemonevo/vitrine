# Session teardown — Proposal

## Why

Locking Vitrine destroys the key material in the vault store and every key cache. It does not touch
`VaultBrowserViewModel`, which keeps `displayedItems` and `itemSelection` — arrays of `VaultItem`
whose fields are plain `String`s, decrypted at sync time and never re-encrypted. So after a lock:

- the item list, folder names, organisation names and collection names are still in memory, and
- `RootViewModel.selectedLogin` still holds the selected item's username, password and TOTP secret,
  because it is only recomputed when `itemSelection` changes — and nothing changes it.

The copy commands are gated on `selectedFieldAvailable(_:)`, which is `selectedLogin != nil`. It
therefore stays `true` across a lock, and ⌘⌥C on the **unlock screen** copies the previous session's
password. That is not a theoretical window: the vault is locked precisely when the user has walked
away from the machine, and the menu bar is reachable regardless of which screen is showing.

There is a second, compounding problem. `lockVault()` and `signOut()` clear the store inside a
`Task`, while a sync that was already running continues its own `await`s and then calls
`vaultKeyCache.populate`, `orgKeyCache` population and `vaultRepository.populate`. Nothing checks
whether the session it belongs to still exists. A sync that lands after the teardown therefore
repopulates both the store and the key caches, and `handleSyncCompleted` writes the decrypted items
straight back into the view model — on the unlock screen.

`background-sync` widened this window considerably: syncs are no longer only user-initiated, so the
overlap between "a sync is in flight" and "the vault locks" is now a routine occurrence rather than
a coincidence of pressing ⌘R and then ⌘L.

Neither problem is visible from the outside, and both contradict what `SECURITY.md` tells the user
about locking. Locking is the one operation whose whole promise is that the plaintext is gone.

## What Changes

- **The view model gains one teardown.** `clearSessionState()` drops every session-scoped property
  that can hold decrypted content — the item list, the selection, folder/organisation/collection
  names, the search query, reveals, pending re-prompt state and error strings. It is called from
  `lockVault()` and from `signOut()`, so the two cannot diverge (the same reasoning that put the
  offline-cache deletion inside `signOut()`).
- **The copy commands additionally require an unlocked vault.** `selectedFieldAvailable(_:)` returns
  `false` when the vault is locked. This is redundant once the teardown runs, and it is kept
  deliberately: it is the gate the user actually touches, and "a locked vault yields no secrets"
  should not rest on a state-clearing routine having been called.
- **A session epoch.** A small `SessionEpoch` value that every session-ending path advances.
  `SyncRepositoryImpl` and `VaultBrowserViewModel` each capture it when they start a sync and refuse
  to apply any result if it has moved. A sync that began in a session that has since ended becomes a
  no-op instead of a resurrection.
- **`SyncError.sessionEnded`**, so that refusal is named rather than disguised as a network failure,
  and so the view model can discard it without logging it as an error.

## Non-goals

- **Changing what a sync does, or when.** This change adds a guard around the existing sync; the
  fetch, decrypt and populate steps are untouched.
- **Zeroing the master password and derived-key buffers on the login and unlock paths.** That is a
  real gap (the lock path zeroizes; login and unlock do not) and it is a separate change — it is
  about *creating* a session's material rather than about ending one.
- **Deleting the device identifier on sign-out**, and **cleaning the clipboard and temp attachment
  files at quit** (there is no termination hook at all). Same reason: adjacent, distinct concerns,
  and each needs its own tests.
- **Making the lock wait for an in-flight sync.** A lock that blocks on the network is a worse bug
  than the one being fixed. The epoch makes the lock immediate *and* correct; the in-flight work
  discards itself afterwards.
- **Cancelling in-flight requests.** Cancellation is cooperative and would need the same explicit
  post-await checks the epoch already provides; adding both would be two mechanisms for one
  invariant.

## Capabilities

### New Capabilities

- `session-teardown`: ending a session — by lock or by sign-out — removes decrypted vault content
  from memory, and work started in that session cannot put it back.

### Modified Capabilities

_None._

## Impact

- `Prizm/Presentation/Vault/VaultBrowserViewModel.swift` — `clearSessionState()`; the epoch check
  around `performSync(origin:)`
- `Prizm/App/PrizmApp.swift` — `lockVault()` and `signOut()` call the teardown and advance the epoch;
  `selectedFieldAvailable(_:)` gains the unlocked check
- `Prizm/Domain/SessionEpoch.swift` — **new**
- `Prizm/Domain/Repositories/SyncRepository.swift` — `SyncError.sessionEnded`
- `Prizm/Data/Repositories/SyncRepositoryImpl.swift` — captures the epoch; refuses to apply a result
  whose session has ended
- `Prizm/App/AppContainer.swift` — builds the epoch and injects it into both
- `Prizm/PrizmTests/` — the 9 `VaultBrowserViewModel(...)` and 3 `SyncRepositoryImpl(...)`
  construction sites gain the parameter
- `SECURITY.md` — the lock guarantee now says what is actually cleared
