# Session teardown — Design

## Context

The existing teardown is thorough about the *store* and incomplete about the *view model*.

`RootViewModel.lockVault()` (`PrizmApp.swift:733`) awaits `authRepo.lockVault()` (which zeroes the
crypto service's keys), then `vaultRepo.clearVault()`, then clears `vaultKeyCache`, `orgKeyCache`,
`accountKeyCache`, `generatorHistory`, `healthReportVM`, `repromptGrants`, the SSH agent's grants and
socket, and calls `vaultBrowserVM.discardReveals()`. `signOut()` does the same plus discarding the
Keychain session.

What neither touches is the browser view model's own state:

- `displayedItems: [VaultItem]` and `itemSelection: VaultItem?` hold fully decrypted items —
  `LoginContent.password`, `.totp`, `SSHKeyContent.privateKey`, secure-note bodies.
- `folders`, `organizations`, `collections` hold decrypted names.
- `searchQuery` holds whatever the user typed, which for a search over a password manager is
  frequently a secret.
- `RootViewModel.selectedLogin` is recomputed only when `itemSelection` publishes (`:574-586`), so it
  survives the lock holding a username, password and TOTP secret.

And `discardReveals()` clears only `revealedItemIds`.

The second half of the problem is temporal. Both teardown methods run inside a `Task` and have
several `await`s. A sync that started earlier is concurrently awaiting its own network call, and
after it returns it calls `vaultKeyCache.populate`, populates the org key cache, and calls
`vaultRepository.populate`. There is no check that the session it belongs to still exists. Two
outcomes follow, and both are wrong:

1. The store and key caches are repopulated after being cleared — key material for a session the user
   believes is closed.
2. `handleSyncCompleted` refreshes the view model, putting the decrypted items back — on the unlock
   screen.

## Decision 1 — one teardown method on the view model, called from both paths

`VaultBrowserViewModel.clearSessionState()` clears every session-scoped property that can hold
decrypted content. It is a single method, not two call sites each clearing what they remember, for
the same reason the offline cache is deleted inside `AuthRepositoryImpl.signOut()` rather than by its
callers: this project has already had two sign-out paths diverge once, and a property added to the
view model later must not need to be remembered in two places.

The alternative — having `RootViewModel` reach into the view model's published properties — was
rejected because it puts the knowledge of what is sensitive in the wrong type, and because
`displayedItems` and `itemSelection` are `private(set)`.

**`discardReveals()` remains a separate method** and is still called on the same paths. It answers a
narrower question ("which fields is this item currently showing?") and is also called on selection
changes, where a full teardown would be absurd.

### The teardown has to survive its own side effects

Found while implementing, and the reason `clearSessionState()` sets a flag before it assigns
anything.

Several of the properties it clears have observers that start work. `searchQuery`'s `didSet` kicks
off `refreshItems()` (`VaultBrowserViewModel.swift:43`), and `refreshItems()` reads the item list
back out of the vault store. So clearing the query scheduled a refresh that could repopulate the
very list the teardown had just emptied.

In production this happened to be harmless, because both callers empty the *store* first — so the
refresh read nothing. That is ordering-by-luck of exactly the kind this change exists to remove, and
it has a live failure path: a sync racing the lock could repopulate the store between the two steps,
and the refresh would then put its items on the unlock screen.

So the teardown sets `sessionStateCleared` first, and the refresh methods no-op while it is set. The
flag is cleared by `handleSyncCompleted` and by `handleVaultEnteredWithoutSync` — the two paths by
which a new session's data arrives — so it cannot be left standing in a way that keeps the vault
list empty.

## Decision 2 — the copy commands also require an unlocked vault

`RootViewModel.selectedFieldAvailable(_:)` returns `false` when `isVaultUnlocked` is false. Once
Decision 1 runs, `selectedLogin` is `nil` and the check is redundant.

It is kept anyway. The cost is one boolean; the benefit is that the one gate the user actually
interacts with — a menu item — does not depend on a state-clearing routine having been called
correctly at some earlier point. This is the same judgement as the background-refresh tick guard:
for a security property, one lock on the door is a bug waiting for a refactor, and two is a design.

## Decision 3 — a session epoch, because the store must refuse too

Decision 1 fixes the view model. It does not fix the store or the key caches, and those are the worse
half: a repopulated `vaultKeyCache` means the vault is, cryptographically, still open.

`VaultBrowserViewModel` discarding its own results would not help, because the repository populates
the store before the view model is ever told.

So the refusal has to be at both ends, driven by one shared value:

```swift
actor SessionEpoch {
    private var value = 0
    func current() -> Int { value }
    func advance() { value += 1 }
    func isCurrent(_ token: Int) -> Bool { token == value }
}
```

- `lockVault()` and `signOut()` call `advance()` **first**, before any teardown `await`. Everything
  that follows is teardown, and a sync completing during it must already see the session as over.
- `SyncRepositoryImpl.sync()` captures `current()` on entry. Before it populates the key caches, the
  store, or the offline cache, it checks `isCurrent(token)`; if not, it throws
  `SyncError.sessionEnded` without writing anything.
- `VaultBrowserViewModel.performSync(origin:)` captures the epoch before it awaits the use case and
  checks it before touching any state. If it moved, the result is dropped.

**Why an epoch and not a flag.** A boolean "is locked" would be wrong: signing in again re-locks-nothing
but does start a new session, and a stale sync from the previous session must not be able to write
into it. A monotonic counter distinguishes "still the same session" from "unlocked again", which is
exactly the question being asked.

**Why not cancellation.** Cancelling the in-flight task is the more obvious move, and it is
insufficient on its own: cancellation is cooperative, so `SyncRepositoryImpl` would need the same
explicit post-`await` check anyway — at which point the epoch is the same amount of code, works
regardless of task-tree plumbing through the use case layer, and does not depend on a cancelled
`URLSession` task unwinding promptly.

**Why not "make the lock wait for the sync".** Because a lock that blocks on an unreachable server is
a worse failure than the one being fixed: the user presses ⌘L and the vault stays open for thirty
seconds. The lock stays immediate; the in-flight work discards itself afterwards.

**Scope of the epoch.** It is deliberately *not* wired into the unlock path's own sync. There is no
lock to race: the vault cannot be locked while it is being unlocked.

## Decision 4 — `sessionEnded` is a named error, not a network failure

The repository could return the previous result or throw a generic error. Both are worse:

- Returning the fetched data would mean the caller has to remember not to use it.
- Throwing `networkUnavailable` would be a lie in the log, and would make a sign-out look like a
  connection problem during diagnosis.

`SyncError.sessionEnded` says what happened. The view model's background path treats it as "drop
silently" rather than "report" — it is not a failure, it is the correct outcome of a race that the
teardown won. The manual path does the same: the user pressed ⌘L, so they are not owed an error about
the sync they cancelled by locking.

## Verification

The unit tests cover: the teardown clears each category of content; a sync whose epoch moved applies
nothing to the store, the key caches or the view model; the copy commands are unavailable while
locked; and the two teardown paths clear the same set (asserted against a single list, so a property
added to one and not the other fails).

What they cannot cover is the *timing* — that a real sync racing a real lock lands on the right side.
The manual check that matters is: start a sync, lock immediately, and confirm the unlock screen shows
no item list on return and that `log stream` shows the sync reporting `sessionEnded` rather than
popping the list back.
