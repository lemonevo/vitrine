# Design — phase 1 (daily usability)

## D1. Duplicate is a create, not a clone of the wire format

`duplicate` builds a `DraftVaultItem` and hands it to the existing `create` path, so a duplicate
goes through exactly the same encryption, org-key resolution and cache-insert code as a new item.
No new write path is introduced.

**What a copy deliberately does NOT carry:**

| Field | Why not |
|---|---|
| `preserved.cipherKey` | The per-item key is what the *original's* attachments are wrapped with. Copying it would make the new cipher claim a key it has no attachments for, and would leave the original's attachments pointing at a key that is now shared. |
| `preserved.fido2Credentials` | A passkey is a credential for one account. Two ciphers holding the same credential is a state no Bitwarden client expects, and the user cannot see or remove the copy — Vitrine has no passkey UI. |
| `preserved.passwordHistory` | That is the *original's* history. A brand-new cipher has no history. |
| `preserved.archivedDate` | A copy is a new item; the user asked for a duplicate, not an archived duplicate. |
| `attachments` | Matches the official clients. Copying them would mean re-uploading blobs the server already has, and (with a per-item key) re-wrapping them. |

Everything the user can actually see is copied: name, all type-specific fields, notes, custom
fields, URIs, folder, organisation, collections, and the re-prompt flag.

**`isFavorite` is reset to `false`.** Favorites is a deliberate shortlist; adding to it is the
user's decision, not a side effect of duplicating. Stated in the spec so it is not mistaken for an
oversight.

## D2. Idle detection uses a local `NSEvent` monitor

`NSEvent.addLocalMonitorForEvents(matching:)` is the only supported way to observe input without an
accessibility entitlement. A local monitor only sees events delivered to *this* application, which
is the correct semantics for an idle timeout: if the user is working in another app, Vitrine is idle.

Two consequences worth stating, because they look like bugs:

- Moving the mouse over another app's window does not count as activity. It should not.
- The monitor returns the event unchanged. It is an observer, never a filter — swallowing input to
  implement a lock timer would be a serious defect.

The mask covers key down, mouse down (left/right/other), scroll and mouse move. Mouse-move events
arrive at display rate, so activity is recorded at most once per second rather than on every event;
the timer granularity is coarser than that anyway.

The timer polls every 5 seconds rather than being rescheduled per event. One repeating timer is
easier to reason about than a timer that is invalidated and recreated on every keystroke, and the
worst-case overshoot is 5 seconds against a minimum interval of 60.

**`.never` is expressed as a `nil` interval**, not as a sentinel number. `Int.max` minutes would
overflow when converted to seconds and would silently become "lock almost immediately".

## D3. The timeout decision is separated from the clock

`VaultIdleMonitor` takes its current time from an injected closure and exposes
`noteActivity(at:)` / `pollTimeout(at:)` alongside the convenience `noteActivity()` /
`pollTimeout()`. The AppKit wiring — the event monitor and the repeating timer — lives in
`start()`/`stop()` and is never exercised by tests. What the tests drive is the decision: given a
last-activity instant, a now, and a settings value, does the action fire?

Without this split the only way to test a 15-minute timeout would be to wait 15 minutes.

## D4. The timeout action is `lock` or `signOut`, and both already exist

`RootViewModel` already has `lockVault()` and `signOut()`, both of which clear the vault store and
every key cache. The timeout action therefore selects between two existing, already-audited paths
rather than introducing a third teardown. `signOut` additionally clears the stored session, which
is the difference the user is choosing between.

## D5. Manual sync reuses `handleSyncCompleted` / `handleSyncError`

The post-sync refresh (items, counts, folders, organisations, selected item, timestamp) already
exists and is already the single definition of "a sync finished". A manual sync calls the same
methods, so it cannot drift from the login-time sync. The only new state is `isSyncing`, which
guards re-entry in the UI and is separate from `SyncRepositoryImpl`'s own `isSyncing` guard — that
one protects the actor, this one protects the button.

`SyncError.syncInProgress` is therefore unreachable from the UI. It is still handled, because a
race between the manual button and a login-time sync is possible in principle and a thrown
"already in progress" is a better outcome than two concurrent syncs.

## D6. Sorting is applied in the ViewModel, not the repository

`VaultRepositoryImpl` pre-computes a sorted list per `SidebarSelection` at `populate()` time and
serves it in O(1) (`openspec/specs/vault-actor-isolation`). Making the sort order a repository
input would mean rebuilding those indexes on every sort change, and would put a UI preference
inside the actor that exists to hold vault data.

Sorting the already-filtered result in `VaultBrowserViewModel.refreshItems()` costs one pass over
a list that is at most a few hundred items, keeps the repository free of presentation concerns, and
keeps `vault-actor-isolation` intact.

The repository's own alphabetical ordering is left in place as the tie-break, so equal
`revisionDate`s do not produce an arbitrary order.

## D7. Letter sections are only rendered for name sorting

`ItemListView` groups items under their first letter. That is meaningful when the list is ordered
by name and meaningless otherwise — a date-ordered list sectioned A–Z looks like a rendering bug.
The sectioning is therefore conditional on the sort order being name-based, and the flat list is
used otherwise.

## D8. Search scope is widened in `matchesSearch`, folder names in the repository

Notes and custom fields live on the item, so they belong in `VaultItem.matchesSearch` next to the
existing per-type fields.

Folder names do not: an item stores a `folderId`, and the name lives in the repository's folder
list. Resolving it inside `matchesSearch` would require the item to know about folders, so the
folder-name test is a separate clause in `VaultRepositoryImpl.searchItems`, which already holds
both halves.

Widening the scope is strictly additive — every query that matched before still matches — so no
existing behaviour is removed.

## D9. `DraftCustomField` becomes fully mutable, with a stable identity

`name`, `type` and `linkedId` change from `let` to `var`, and the type gains a `UUID` `id`.

The `id` is needed because `CustomFieldsEditSection` uses `ForEach(fields.indices, id: \.self)`.
That is safe for a read-only list but not for one that can be reordered or have rows removed:
SwiftUI identifies rows by index, so deleting row 1 makes row 2 reuse row 1's view state — and the
reveal state of a hidden field is view state. A stable `UUID` fixes that. `id` is excluded from
`Equatable`, matching `DraftLoginURI`.

Switching a field's type to `.linked` clears its `value`: a linked field's value is derived from
the field it points at, and leaving a stale plaintext value behind would send a value the UI never
shows.

## D10. Empty Trash loops in the use case, and reports rather than throws

`DELETE /api/ciphers/{id}` is per-item; there is no bulk endpoint. The use case therefore lists
`.trash` and deletes each item in turn.

It **returns a result** (`deletedCount`, `failedCount`) instead of throwing on the first failure.
Throwing would stop halfway and leave the user unable to tell how much was removed; returning lets
the caller report "deleted 12, 3 failed" and refresh the list to whatever is actually left. A
partial result is the honest outcome for an operation that is N independent requests.

The loop lives in the use case rather than the repository so the repository keeps its existing
one-item primitive and gains no new bulk semantics.

## D11. New preferences follow the `WebsiteIconsPreference` shape

Each new preference is a small `enum`/`struct` namespace with a `static let key`, a read with an
explicit default, and a write. Reading goes through the same helper shape as
`WebsiteIconsPreference.isEnabled(in:)`.

The reason is the trap that preference already documented: `UserDefaults.bool(forKey:)` returns
`false` for a key that was never written, so a default-on or default-mid-list preference must test
`object(forKey:) == nil` rather than relying on the type's zero value. The new preferences use
`integer(forKey:)` with an explicit "key absent" branch for the same reason — `0` is a meaningful
value (`.never`) and cannot double as "unset".

Every preference reader takes an injectable `UserDefaults` so tests never touch the real domain.
