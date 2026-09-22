## 1. Manual sync

- [x] 1.1 `VaultBrowserViewModel`: add `syncUseCase`, `isSyncing`, `syncProgressMessage`
- [x] 1.2 `performManualSync()` — re-entrancy guard, `handleSyncCompleted` on success, `handleSyncError` on failure
- [x] 1.3 Toolbar button in the content column (`arrow.clockwise`), disabled while syncing, `ProgressView` while syncing
- [x] 1.4 ⌘R in `PrizmApp`, disabled unless the vault is unlocked
- [x] 1.5 Tests: success refreshes items and the timestamp; failure surfaces the banner and does not move the timestamp; a second call while one is in flight is ignored

## 2. Vault timeout

- [x] 2.1 `VaultTimeoutInterval` (1/5/15/30/60 minutes, never) and `VaultTimeoutAction` (lock, sign out) with persistence; `never` maps to a `nil` second count
- [x] 2.2 `VaultIdleMonitor` — injected clock, `noteActivity(at:)`, `pollTimeout(at:)`, AppKit event monitor and 5 s timer confined to `start()`/`stop()`
- [x] 2.3 `RootViewModel`: own the monitor, act on the timeout via `lockVault()` / `signOut()`
- [x] 2.4 Tests: no fire before the interval, fire at and after it, activity resets the baseline, `never` never fires, each action routes to the right teardown

## 3. Clipboard clear interval

- [x] 3.1 `ClipboardClearInterval` (10/20/30/60/120 seconds, never) with persistence, default 30
- [x] 3.2 `VaultBrowserViewModel.copy` reads the preference instead of the literal 30; `never` schedules no clear
- [x] 3.3 Tests: each interval schedules the matching delay; `never` leaves the clipboard alone; a second copy cancels the first clear

## 4. Duplicate an item

- [x] 4.1 `DraftVaultItem.duplicate(of:)` — new id, `"<name> (copy)"`, favorite reset, `preserved` cleared, `reprompt`/folder/org/collections kept
- [x] 4.2 `DuplicateVaultItemUseCase` + impl, delegating to `VaultRepository.duplicate(id:)`
- [x] 4.3 `VaultRepositoryImpl.duplicate(id:)` — fetch, build the draft, go through `create`
- [x] 4.4 ⌘D in the Item menu plus a context-menu entry; select the new item afterwards
- [x] 4.5 Tests: content copied, name suffixed, id differs, favorite reset, `preserved` empty, folder/org/collections preserved, original untouched

## 5. Empty Trash

- [x] 5.1 `EmptyTrashUseCase` + impl — list `.trash`, delete each, return `deletedCount` / `failedCount`
- [x] 5.2 `VaultBrowserViewModel.performEmptyTrash()` — refresh items and counts, report partial failure via `actionError`
- [x] 5.3 Trash view button + confirmation alert naming the count
- [x] 5.4 Tests: all deleted, partial failure reported, empty trash is a no-op

## 6. Sort order

- [x] 6.1 `ItemSortOrder` (name ascending/descending, last modified, created; newest and oldest) with persistence, default name-ascending
- [x] 6.2 `VaultBrowserViewModel.sortOrder` — persisted, re-sorts on change
- [x] 6.3 Apply the order in `refreshItems()`; keep the repository's name order as tie-break
- [x] 6.4 `ItemListView`: letter sections only for name sorting, flat list otherwise
- [x] 6.5 Sort `Menu` in the content toolbar with the current order checked
- [x] 6.6 Tests: each order's output, case-insensitivity, tie-break stability, sectioning predicate

## 7. Search scope

- [x] 7.1 `VaultItem.matchesSearch` also matches notes and custom field names/values, for every item type
- [x] 7.2 `VaultRepositoryImpl.searchItems` also matches the item's folder name
- [x] 7.3 Tests: notes match, custom field name and value match, folder name matches, previously matching queries still match

## 8. Editable custom fields

- [x] 8.1 `DraftCustomField`: `name`/`type`/`linkedId` mutable, stable `UUID` id excluded from equality
- [x] 8.2 `LinkedFieldId.options(for:)` — the native fields available per item type
- [x] 8.3 `CustomFieldsEditSection` rewritten: editable name, type picker, per-type value editor, delete, move up/down, "Add field"
- [x] 8.4 Switching to `.linked` clears the value; linked rows pick from `options(for:)`
- [x] 8.5 Block saving while any custom field has a blank name (it would be dropped by the mapper)
- [x] 8.6 Tests: add/delete/reorder round-trips through `DraftVaultItem`, rename and retype reach the draft, `allCustomFields` covers all five content types

## 9. Localisation and verification

- [x] 9.1 Add every new user-visible string to both `Localizable.strings` files; keep key parity
- [x] 9.2 `plutil -lint` both files
- [x] 9.3 `swift build` with zero warnings
- [x] 9.4 Full test suite — no new failures against the base-commit failure set
- [x] 9.5 Rebuild `dist/Vitrine.app`; confirm it launches
- [x] 9.6 Update `FEATURE-GAP-ANALYSIS.md` §5 to mark phase 1 done
- [x] 9.7 Commit in dependency order, verifying each commit compiles in a worktree

---

## Notes recorded during implementation

- **9.4** — 718 tests, 10 failure records, byte-identical to the base commit `78b49b9`
  (`CardBackgroundTests.testCardBackgroundColor_exists` and the eight
  `PasswordGenerator*` records that need `Assets.car` / the EFF wordlist, neither of which
  is present when `Bundle.main` is the xctest runner). Base was 471 tests / 10 records;
  Phase 0 took it to 551 / 10; Phase 1 to 718 / 10.
- **9.7** — an extra defect was found and fixed while writing the menu-state tests: `⌘R`
  stayed disabled forever after unlocking, because `menuBarCanSync` was only recomputed
  when `isSyncing` emitted. The shortcut is one of the ways to start a sync, so the
  command could never enable itself. The `$screen` subscription now recomputes it.
- Four keys were introduced with different casing from existing ones
  (`Lock vault`/`Lock Vault`, `Sign out`/`Sign Out`, `Move Up`/`Move up`,
  `Move Down`/`Move down`) and were unified onto the existing keys rather than added.
