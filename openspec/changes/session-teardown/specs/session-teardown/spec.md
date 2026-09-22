## ADDED Requirements

### Requirement: Ending a session SHALL remove decrypted vault content from memory

Locking the vault and signing out SHALL both clear every session-scoped holder of decrypted content
in the presentation layer — the item list, the selection, folder, organisation and collection names,
the search query, reveals, pending re-prompt state, and any error string derived from server or vault
content.

Both paths SHALL clear the same set, and the set SHALL be cleared by one routine so that a property
added later cannot be cleared on one path and missed on the other.

#### Scenario: Locking clears the item list

- **GIVEN** the vault is unlocked and items are displayed
- **WHEN** the vault is locked
- **THEN** the displayed item list SHALL be empty
- **AND** no item SHALL remain selected

#### Scenario: Locking clears decrypted names

- **GIVEN** the vault is unlocked and folders, organisations and collections have been loaded
- **WHEN** the vault is locked
- **THEN** those lists SHALL be empty

#### Scenario: Locking clears the search query

- **GIVEN** the user has typed a query into the search field
- **WHEN** the vault is locked
- **THEN** the query SHALL be cleared
- **AND** global search SHALL no longer be active

#### Scenario: Signing out clears the same set

- **GIVEN** the vault is unlocked and items are displayed
- **WHEN** the user signs out
- **THEN** every category cleared on lock SHALL also be cleared

#### Scenario: The selection-derived state goes too

- **GIVEN** an item is selected and its login content is available to the copy commands
- **WHEN** the vault is locked
- **THEN** that login content SHALL no longer be available

### Requirement: Secrets SHALL NOT be copyable while the vault is locked

The commands that copy a selected item's username, password, one-time code or website SHALL be
unavailable while the vault is locked, independently of whether any selection-derived state remains.

#### Scenario: Copy commands are disabled on the unlock screen

- **GIVEN** the user had an item selected before locking
- **WHEN** the unlock screen is showing
- **THEN** the copy commands SHALL report themselves unavailable
- **AND** invoking one SHALL copy nothing

#### Scenario: Copy commands work while unlocked

- **GIVEN** the vault is unlocked and an item with a password is selected
- **WHEN** the availability of the password copy command is queried
- **THEN** it SHALL report itself available

### Requirement: Work started in a session SHALL NOT apply its results after that session ends

A sync captures an identifier for the session it belongs to. If that session ends — by lock or by
sign-out — before the sync completes, the sync SHALL NOT write to the vault store, the key caches,
the offline cache, or the presentation layer, and SHALL report that its session ended.

#### Scenario: A sync that outlives its session writes nothing

- **GIVEN** a sync is in flight
- **WHEN** the vault is locked before it completes
- **THEN** the sync SHALL NOT populate the vault store
- **AND** it SHALL NOT populate the vault key cache or the organisation key cache
- **AND** it SHALL NOT write the offline cache
- **AND** it SHALL report that its session ended

#### Scenario: The locked session shows no items

- **GIVEN** a sync is in flight and the vault is locked before it completes
- **WHEN** the unlock screen is shown
- **THEN** the item list SHALL remain empty
- **AND** no error SHALL be presented to the user

#### Scenario: A sync within its session is unaffected

- **GIVEN** the vault is unlocked and no lock occurs
- **WHEN** a sync completes
- **THEN** it SHALL populate the store, the key caches and the presentation layer as before

#### Scenario: Locking again does not admit a stale sync

- **GIVEN** a sync started in session A and is still in flight
- **AND** the vault was locked and unlocked again, starting session B
- **WHEN** the sync from session A completes
- **THEN** it SHALL NOT write into session B

#### Scenario: The in-flight flag is released

- **GIVEN** a sync's result is discarded because its session ended
- **WHEN** the next sync is requested
- **THEN** it SHALL be allowed to start
