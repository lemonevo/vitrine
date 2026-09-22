# Fix test preference isolation — Proposal

## Why

`VaultBrowserViewModelActionsTests.test_sortOrder_changeReSortsAndPersists` fails intermittently in a
full suite run and always passes in isolation. The cause is not timing:

- `VaultBrowserViewModelActionsTests:329` sets `sut.sortOrder = .nameDescending`, which writes
  `itemSortOrder` into `UserDefaults.standard` (`VaultBrowserViewModel.swift:128`), then reads it
  back at `:332`.
- `VaultBrowserViewModelBackupTests:30` and `:43` remove that same key from `UserDefaults.standard`
  in `setUp` and `tearDown`.

Xcode runs test **classes** in parallel **processes**, which share the host app's preference domain.
So one suite deletes the key the other has just written, and the read-back returns the default. The
test is not flaky; it is being deleted out from under.

`ItemSortPreference` already takes an injectable `UserDefaults` (`load(from:)`, `save(_:to:)`), and
`ItemSortPreferenceTests` already uses a UUID-named suite for exactly this reason. The view model
does not pass one, and the two suites above use `.standard` directly, so the isolation that exists is
not used where it is needed.

## What Changes

- `VaultBrowserViewModel` takes the `UserDefaults` to read and write the sort preference from,
  defaulting to `.standard`, and uses it in the `sortOrder` observer.
- The suites that read or clear the preference pass a suite named per test instance, and operate on
  that instead of `.standard`.
- No production behaviour changes: the app still uses `.standard`.

## Why this is not "just a test fix"

A suite that fails at random is worse than one that fails consistently, because it teaches everyone to
re-run rather than read. The claim "the suite is green" has been qualified in every report since this
started, and it is the kind of qualification that stops being honoured after the second or third time.

## Impact

- `Prizm/Presentation/Vault/VaultBrowserViewModel.swift` — the injected defaults
- `Prizm/PrizmTests/Presentation/VaultBrowserViewModelActionsTests.swift`
- `Prizm/PrizmTests/Presentation/VaultBrowserViewModelBackupTests.swift`
