## ADDED Requirements

### Requirement: The user can trigger a vault sync on demand

The vault browser SHALL provide a manual sync action, reachable from a toolbar button and from the
⌘R keyboard shortcut. The action SHALL call the same sync path used at unlock, so a manual sync
produces exactly the same result as an automatic one: refreshed items, counts, folders,
organisations and last-sync timestamp.

While a sync is in flight the action SHALL be disabled and SHALL indicate that work is in progress,
so a second sync cannot be started from the UI. The disabled state SHALL end when the sync
completes, whether it succeeded or failed.

A failed manual sync SHALL surface the error through the existing sync error banner and SHALL NOT
update the last-sync timestamp, which continues to reflect the most recent *successful* sync.

#### Scenario: Toolbar button starts a sync
- **GIVEN** the vault is unlocked and no sync is in flight
- **WHEN** the user clicks the sync button
- **THEN** a vault sync SHALL be performed
- **AND** the item list, sidebar counts, folder list, organisation list and last-sync timestamp SHALL be refreshed on success

#### Scenario: ⌘R starts a sync
- **GIVEN** the vault is unlocked and no sync is in flight
- **WHEN** the user presses ⌘R
- **THEN** a vault sync SHALL be performed

#### Scenario: Sync action is disabled while syncing
- **GIVEN** a manual sync is in flight
- **WHEN** the toolbar renders
- **THEN** the sync button SHALL be disabled and SHALL show progress
- **AND** ⌘R SHALL NOT start a second sync

#### Scenario: Failure leaves the timestamp alone
- **GIVEN** a manual sync fails (network error, expired session, or any other error)
- **WHEN** the failure is handled
- **THEN** the sync error banner SHALL show the failure message
- **AND** the last-sync timestamp SHALL be unchanged
- **AND** the sync action SHALL become available again

#### Scenario: Sync action unavailable when the vault is locked
- **GIVEN** the vault is locked
- **WHEN** the user presses ⌘R
- **THEN** no sync SHALL be performed

#### Scenario: Concurrent sync is refused rather than duplicated
- **GIVEN** a sync is already running because of a login or unlock
- **WHEN** a manual sync is requested
- **THEN** the request SHALL be refused with a "sync already in progress" error rather than starting a second sync
