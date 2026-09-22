# Remove dead code and doc drift — Proposal

## Why

Two audits and a hand-verification pass over the whole source tree, looking for code that is compiled but
unreachable and for documentation that asserts things the code no longer does. Both are cheap to fix and
both cost more the longer they sit: dead code is read as live by the next person, and a false comment is
worse than no comment because it is trusted.

Removed, each after an independent grep that found no reference outside its own declaration:

- **`enum Config`** (`clientName`, `deviceType`) — nothing reads either; the header comment implied it was
  app-wide configuration. `DebugConfig` and `vaultDidLock` in the same file are live and were kept.
- **`VerticalLabeledContentStyle.swift`** — its own comment claimed it was "shared by `LoginView` and
  `UnlockView`". `grep labeledContentStyle` across the tree: zero call sites. The last one went when the
  login form was rebuilt; the file was still compiled and still registered in the project.
- **`Opacity.listSelection`** — the list selection ended up using the system `List(selection:)` highlight.
- **`FaviconLoader.clearCache()`** — no caller. The comment said "e.g. on sign-out or low-memory warning";
  neither was ever wired.
- **`PrizmCryptoServiceError.hkdfFailed`**, **`EncStringError.invalidIVLength`** — error cases no code
  constructs.
- **11 design tokens** (`Typography.sectionHeader`, `sidebarChildRow`; `Spacing.footerPadding`,
  `readOnlyField`, `sidebarRowVertical`, `sidebarRowHorizontal`, `sidebarSectionTop`/`Bottom`,
  `sidebarSearchVertical`, `listRowHorizontal`, `listSelectionBarWidth`).
- **7 accessibility identifiers** (`Unlock.emailLabel`, `Vault.searchField`, `Vault.lastSyncedLabel`,
  `Detail.createdDate`, `Detail.updatedDate`, `Create.pickerList`, `Create.pickerRow`).

Comments corrected where they asserted something false:

- `DraftVaultItem.customFields` said adding/removing/reordering was "out of scope".
  `CustomFieldsEditSection` implements all three.
- `VaultExportDocument`'s format note said `URIMatchType` is `Int`-backed — no longer, by design.
- `FaviconLoader`'s removed comment, and `build-app.sh`'s false claim about where Xcode puts localisations
  (fixed in the localisation change).

Strings: **4 duplicate entries in each table** (`None`, `Reveal`, `Username`, `Words: %lld`), all with
identical values, from appending new sections instead of merging. Removed. In a `.strings` file the last
entry wins silently, so a duplicate whose value ever diverged would be an invisible translation bug —
which is what made them worth clearing even while they matched.

## What was deliberately not removed

**Localization keys.** A first sweep reported 14 orphans, then 15, 23, 15 depending on how the search was
written. The reason a count can't be settled: `Text("\"\(item.name)\" will be moved to Trash.")` resolves
through `LocalizedStringKey` to the key `"\"%@\" will be moved to Trash."`, so no literal-text search finds
it, and the tables also carry genuine curly/straight-quote twins where one side is live and one is not.
Deleting a live key fails silently into showing the raw key in the UI — the exact class of quiet breakage
this repo keeps finding. **The 15 candidates are left alone, and the finding is recorded as "unreliable
tooling", not as "unused strings".**

**Two performance items, after measuring their size.** `SidebarView` rebuilds the folder and collection
trees inside `body`, and `ItemListView.orgName(for:)` scans the org array per row. Both are real per-render
work; at the vault this app is used with (86 items, 5 folders, 2 orgs) both are microseconds. Neither was
touched, because the fix for the first means threading derived state through the view model and the fix for
the second means a new parameter type — churn and risk bought by nothing measurable.

## What was tried and reverted

`.nameAscending` was made a pass-through in `ItemSortOrder.sort`, on the reasoning that
`VaultRepositoryImpl` already hands back buckets in exactly that order and re-sorting per keystroke is
wasted. **Two existing tests went red.** They feed `sort()` an unsorted array directly, and they are right
to: it is a public function on a value type and cannot assume its caller pre-sorted. Reverted. The
per-keystroke sort stays.

## README

Four features that exist and were never listed — the vault-wide verification-codes list, PIN unlock, CSV
export, the username generator mode — plus the interface languages. The roadmap still had "offline vault
read" and "background refresh" under **Now**; both shipped. The TOTP line claimed "a live countdown", which
was true of the detail pane and false of the codes list until this session fixed it.
