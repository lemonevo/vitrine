## Why

`FEATURE-GAP-ANALYSIS.md` §5 phase 1 is "日常可用性补齐" — the low-cost, high-perception items that
make the client stop feeling like a demo. Phase 0 fixed the defects that made it unsafe to trust
with a real vault; this phase fixes the ones that make it tiring to use every day.

The complaints, in the order a user meets them:

1. **Nothing tells you the vault is fresh.** Sync runs once, at unlock. If the vault changed on
   another device there is no way to pull the change — the sidebar shows a read-only timestamp
   and that is the end of the story. There is no button and no ⌘R.
2. **The vault never times out from idleness.** Locking only happens on sleep, screensaver or
   screen lock. An unlocked vault left open on a desk stays unlocked forever.
3. **The clipboard timeout is hardcoded at 30 seconds.** A copied password is a plaintext secret
   sitting in a globally readable buffer; 30 s is a reasonable default and a bad only-option.
4. **Duplicating an item is impossible.** Rotating a password across similar accounts, or creating
   a second entry that differs in one field, means re-typing everything.
5. **Emptying Trash is one item at a time.** After a bulk cleanup there is no way to finish it.
6. **The list can only be sorted by name.** With 86+ items, "which did I touch last?" is
   unanswerable.
7. **Search only looks at names and a handful of type-specific fields.** Notes and custom fields —
   exactly where people write the thing they later search for — are invisible to it.
8. **Custom fields are half-editable.** Only the value can be changed. Name, type and order are
   fixed at whatever the item arrived with, and a field can neither be added nor removed.

## What Changes

- **Manual sync.** A toolbar button and ⌘R trigger `SyncRepository.sync` on demand. The button is
  disabled and shows progress while a sync is in flight; failures reuse the existing error banner.
- **Vault timeout.** A configurable idle interval (1/5/15/30/60 minutes, or never) and a
  configurable action (lock the vault, or sign out entirely). Idle time is measured from local
  input events; the existing sleep / screensaver / screen-lock locks are unchanged.
- **Configurable clipboard clearing.** 10/20/30/60/120 seconds or never, defaulting to the current
  30 seconds. Applied at copy time.
- **Duplicate an item.** ⌘D (and a context-menu entry) creates a copy named `"<name> (copy)"`,
  selects it, and leaves the original untouched. Deliberately not copied: attachments, the
  per-item key, password history, passkeys.
- **Empty Trash.** One confirmed action permanently deletes every trashed item, reporting how many
  succeeded and how many failed.
- **Sort order.** Name (ascending/descending), last modified, or date created — persisted across
  launches. Letter sections are shown only for name sorting, where they mean something.
- **Wider search.** Notes, custom field names and values, and folder names join the existing
  name/username/URI/cardholder/email/company matching.
- **Editable custom fields.** Add, delete, rename, retype (text / hidden / boolean / linked) and
  reorder. A linked field picks from the native fields of the item's own type.

## Capabilities

### New Capabilities

- `manual-sync`: triggering a vault sync from the UI, and the state that surrounds it.
- `vault-timeout`: idle-timeout interval and the action taken when it elapses.
- `clipboard-clear`: how long a copied secret stays on the clipboard.
- `item-duplicate`: creating a copy of an existing vault item, and what a copy excludes.
- `empty-trash`: permanently deleting every trashed item in one action.
- `item-sorting`: the order the item list is displayed in.
- `vault-search-scope`: which fields a search query is matched against.

### Modified Capabilities

- `vault-browser-ui`: the item list follows the selected sort order instead of always being
  alphabetical; the content toolbar gains a sort control.
- `settings-screen`: two new sections — a timeout picker and action picker in Security, a clipboard
  picker in Privacy.

## Impact

- `Prizm/Domain/Utilities/ItemSortOrder.swift` — new; order enum plus persistence
- `Prizm/Domain/Utilities/VaultTimeoutSettings.swift` — new; interval + action + persistence
- `Prizm/Domain/Utilities/ClipboardClearInterval.swift` — new; interval + persistence
- `Prizm/Domain/Utilities/LinkedFieldId+Options.swift` — new; per-item-type linked field options
- `Prizm/Domain/Entities/DraftVaultItem.swift` — `DraftCustomField` becomes fully mutable; new
  `duplicate(of:)` and `allCustomFields`
- `Prizm/Domain/UseCases/DuplicateVaultItemUseCase.swift`, `EmptyTrashUseCase.swift` — new
- `Prizm/Data/UseCases/` — their implementations
- `Prizm/Data/Repositories/VaultRepositoryImpl.swift` — folder-name matching in `searchItems`
- `Prizm/Domain/Repositories/VaultRepository.swift` — `duplicate(id:)`
- `Prizm/App/VaultIdleMonitor.swift` — new; local input-event monitor driving the idle timer
- `Prizm/App/AppContainer.swift`, `Prizm/App/PrizmApp.swift` — wiring, ⌘R, ⌘D
- `Prizm/Presentation/Vault/VaultBrowserViewModel.swift` — sync state, sort order, duplicate,
  empty trash, clipboard interval
- `Prizm/Presentation/Vault/VaultBrowserView.swift`, `ItemList/ItemListView.swift`,
  `Trash/TrashView.swift`, `Sidebar/SyncStatusView.swift` — UI
- `Prizm/Presentation/Vault/Edit/CustomFieldsEditSection.swift` and the five edit forms
- `Prizm/Presentation/Settings/SettingsView.swift` — the new pickers
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — new strings
- Tests: new suites for the four new utility types, the two new use cases, and the ViewModel
  actions; extended search and repository tests
