# Fix test preference isolation — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`.

## 1. The injection

- [x] 1.1 Failing test: a `VaultBrowserViewModel` built with a private suite stores its sort order in
      that suite, and `UserDefaults.standard` is not touched. Assert on both halves — the second is
      what stops a future change from putting the write back.
- [x] 1.2 Add a `sortPreferenceDefaults: UserDefaults = .standard` parameter to
      `VaultBrowserViewModel.init` and use it for `load` and `save`.

## 2. The suites

- [x] 2.1 `VaultBrowserViewModelActionsTests`: a per-instance suite, passed to the view model and used
      for the `removeObject` calls and the direct `ItemSortPreference.load()` assertions.
- [x] 2.2 `VaultBrowserViewModelBackupTests`: the same, so its `setUp`/`tearDown` clear its own
      domain rather than the shared one.
- [x] 2.3 Confirm no test target file references `UserDefaults.standard` for a Prizm preference key
      any more.

## 3. Verification

- [x] 3.1 Three consecutive full-suite runs, all green — one run is not evidence that a race is gone.
- [x] 3.2 Confirm nothing in the app target changed behaviour: `AppContainer` still uses `.standard`.

> **Outcome:** three consecutive full-suite runs, all green (1342 / 1342 / 1341 passed, 0 failures),
> against a run before the fix where the sort test failed at random.
>
> **One thing the fix moved rather than found.** Routing the clipboard interval through the injected
> domain broke two clipboard tests immediately and reproducibly — they wrote the interval to
> `UserDefaults.standard`, which the view model had been reading. That is the same coupling seen from
> the other side: those tests were passing because both sides happened to use the shared domain, not
> because the behaviour was right. They now write to their own suite too.
