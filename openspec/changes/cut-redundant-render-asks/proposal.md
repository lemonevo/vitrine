# Cut the repeated asks inside three renders — Proposal

## Why

Three places in the interface ask the same question several times within a single render, on screens
where a render happens on every keystroke. None of them is a wrong answer; all of them cost a round
trip outside the process that draws the window.

**The unlock screen asked 2–3 times what one render needed once.** `UnlockView`'s body read
`viewModel.biometricUnlockAvailable` twice — once to name the sensor in the subtitle, once as the gate
for the biometric button — and read the sensor *type* three times on top of that (the subtitle's name,
the button's name, the button's icon). In the repository each of those is an `LAContext` built from
scratch and a policy evaluation sent to the system; the sensor name and icon each built their own. The
password field is bound to `@Published var password` (`UnlockViewModel.swift:27`), so the whole body
re-runs per character: a user typing a master password was paying for three policy evaluations per
keystroke. In PIN mode the remaining-attempts count — two keychain reads each time — was asked three
times per render, twice to print the same number.

**A burst of typing rewrote the item list once per character.** `searchQuery`'s observer started a
pass with no reference to the pass already in flight (`VaultBrowserViewModel.swift:43-45`), and each
pass ended in `displayedItems = sortOrder.sort(...)`. Two things follow. First, the sort is
`ItemSortOrder.sort` — O(n log n) `localizedCaseInsensitiveCompare` calls — and it runs in the view
model's `Task`, on the main actor; only the filtering underneath it is on the vault actor. Second,
`@Published` publishes on assignment, not on change, so five keystrokes were five sorts and five list
invalidations of which exactly one could describe the text now in the field.

This also made the pass's inputs read late. Every pass re-read `searchQuery` *after* its `await`, so
five concurrent passes all searched the newest text — which is why the list was never visibly wrong,
and why the waste was invisible. Reading the query at the moment the pass starts is the only way to be
able to tell an old pass from a new one, so the two changes are one change.

**The folder tree was rebuilt inside `body`.** `SidebarView.folderTree` was a computed property
returning `FolderTreeNode.buildTree(from: folders)`, consumed by `renderRows(for:)`. Building it is
not a walk of the array: `buildTree` sorts by locale-aware comparison and then inserts each folder by
rewriting a nested array of nodes (`FolderTreeNode.swift:27-38`), which copies the enclosing subtree
each time it descends. And the sidebar observes the whole browser view model, so this ran on every
keystroke of a search — a query the folder tree does not depend on. `OrgDisclosureRow.collectionTree`
was the same shape.

## What changes

- **`UnlockView`** (`Presentation/Unlock/UnlockView.swift`) — the availability answers and the sensor
  type are read into constants at the top of `body` and passed down. `credentialField` and `pinField`
  became functions taking what they print; `biometricMethodName(for:)` and
  `biometricSystemImage(for:)` take the sensor type instead of each probing for it. Nothing moved into
  the view model, and the repository's answers stay live: `UnlockViewModelBiometricTests` flips the
  stub *after* construction and expects the new answer, which is a deliberate property of this screen
  (see Deliberate limits).
- **`VaultBrowserViewModel.refreshItems()`** — the query and the sidebar scope are now read when the
  pass starts, and a pass bumps a counter and compares it against the current value before writing
  anything. The wrapper `Task { @MainActor in refreshItems() }` in `searchQuery`'s observer is gone;
  `refreshItems()` already started a task, so that was one suspension point of pure overhead.
- **`SidebarView` / `OrgDisclosureRow`** — `folderTree` and `collectionTree` become `@State`, refreshed
  by `.onChange(of: folders, initial: true)` / `.onChange(of: collections, initial: true)`. Identical
  output, built when the input changes.
- **One `global-search` delta**, because "the list shows the results of the query in the field" is now
  a property the implementation depends on rather than one it happens to satisfy.

## Measured

`UnlockViewRenderCostTests` installs the screen in an `NSHostingView`, types, and counts what the
repository was asked. Four keystrokes, master-password mode:

| Asked of the repository | before | after |
|---|---|---|
| `biometricUnlockAvailable` (a policy evaluation in the app) | **8** | **4** |
| `pinUnlockAvailable` (two keychain reads in the app) | 4 | 4 |
| `pinRemainingAttempts` (two keychain reads), four keystrokes in PIN mode | **12** | **8** |

The sensor-type probe fell from three `LAContext` constructions per render to one; that is counted in
the source rather than in a test, because `LABiometryType` is not reachable through the injected
repository.

`VaultBrowserViewModelSearchCoalescingTests` holds five overlapping passes and counts writes to
`displayedItems`: **five before, one after**, with the search double confirming it was still called
five times — the passes still run, they are simply no longer allowed to draw.

**Both were confirmed red first**, by reverting the two production files and re-running: the unlock
test failed at 8-against-4 and 12-against-8, the search test at 5-against-1.

The first version of `UnlockViewRenderCostTests` read `UnlockView.body` directly and passed against
the unmodified code by reporting **zero** asks. `AuthCard { ... }` stores its content as a
`@ViewBuilder` closure, and constructing a body never invokes it, so every question being counted
lived in a closure that never ran. That is the same false-green shape `-only-testing:` with a typo in
the class name produces, recorded here so the next person who wants to count what a view does reaches
for a hosting view and not for `.body`.

## Deliberate limits

- **The unlock screen's asks are not cached.** Answering once per render instead of once per control
  is the whole of that fix. The remaining one-per-keystroke read is live by design: the repository
  probes the system each time so a biometric lockout, or a keychain item that vanished mid-flow, makes
  the button disappear on the next render. Freezing it at init would hide that, and
  `testBiometricUnlockAvailable_reflectsAuthRepository` exists to keep it visible. Making it cheap
  would mean caching inside `AuthRepositoryImpl` — which is the keychain-and-policy path this change
  deliberately stays out of.
- **No debounce on search.** Typing still issues one vault pass per character; the passes are off the
  main thread, and what this change removes is the main-thread sort and the redundant redraws. A delay
  would also make the timing that several existing tests assert on indeterminate.
- **Superseded passes are discarded by comparison, not cancelled.** `Task.cancel()` cannot interrupt
  an actor method already running, so the only thing cancellation could buy is the same early return
  the counter already gives — one mechanism rather than two that have to agree.
- **The PIN mode count is read twice, not once.** `shouldShowRemainingAttempts` asks the repository for
  the number and then the number is printed. Reading it once in the view would mean duplicating the
  "is this worth showing" rule out of the view model.
- **Not touched, on purpose:** the one view model with 28 published properties that invalidates the
  whole split view; `KeychainService`'s single-record design (one read decodes the whole store);
  `AuthRepositoryImpl` being `@MainActor`; the oversized types. Splitting `VaultBrowserViewModel` is
  already a recorded non-goal in `audit-findings-remediation`, and the rest are their own changes.
- **No UI change and no new strings.**

## Impact

- 3 production files, all presentation-layer; no `Domain/`, no `Data/`, no wire format.
- 2 new test files (7 tests), 3 counters added to `MockAuthRepository`.
- `PrizmTests` picks the new files up through its synchronised folder group; no `project.pbxproj` edit,
  since the app target gained nothing.
- One spec delta (`global-search`), one requirement added.
- Environment note, unrelated to the above: `Prizm/LocalConfig.xcconfig` was absent in this checkout,
  which makes every `xcodebuild` invocation — including the one documented in `AGENTS.md` — fail with
  `Unable to open base configuration reference file`. It is git-ignored and `README.md:120` documents
  copying it from the template; `AGENTS.md`'s verification section does not mention that it is a
  precondition.
