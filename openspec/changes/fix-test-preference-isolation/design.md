# Fix test preference isolation — Design

## Decision — inject the domain rather than guard the shared one

Three options were considered.

**Rejected: a lock or an ordering rule between the suites.** They run in separate processes; there is
nothing to lock.

**Rejected: remove the preference-clearing from `VaultBrowserViewModelBackupTests`.** It clears the
key to make the environment deterministic for its own tests, which is correct of it. The fault is that
"deterministic for me" was implemented as "delete the shared key", and the fix for that is to stop
sharing, not to stop clearing.

**Chosen: give every suite its own domain.** `ItemSortPreference` already supports it, and
`ItemSortPreferenceTests` already does it (`:164`, `suiteName = "ItemSortPreferenceTests-\(UUID().uuidString)"`).
This change makes the view model accept the domain and moves the two stragglers onto it, so the rule
is uniform: no test reads or writes the real preference domain.

The name is per test *instance*, not per class. Per class would be enough for the traffic that exists
today, and per instance costs nothing — one `UserDefaults(suiteName:)` — and removes the need to
reason about which classes might be scheduled together later.

## Decision — the parameter defaults to `.standard`

`AppContainer` is the only production construction site and it passes nothing, so the app is
unchanged. A defaulted parameter keeps the other eight construction sites (most of them in tests that
never touch the sort order) from having to thread a value they do not care about — the same shape as
`sessionEpoch` on that initialiser.

## Verification

The evidence is the run itself: the failing test must pass in a full suite run, repeatedly, not only
in isolation. One green run is not proof of a race being gone, so the check is several consecutive
full runs.
