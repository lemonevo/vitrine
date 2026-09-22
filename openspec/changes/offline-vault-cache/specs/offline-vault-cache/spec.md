# Offline vault cache

An unlock with no network connection opens the vault from a locally stored copy of the server's
encrypted payload.

Everything here follows from one property: the cache holds **ciphertext only**, and the keys that
unwrap it live in the Keychain, wrapped by the master password. The cache being on disk therefore
changes what an attacker can do with the *file*, and nothing about what they can do without the
master password.

## ADDED Requirements

### Requirement: A successful sync SHALL persist the server payload

After a sync populates the vault, the exact bytes received from the server SHALL be stored for the
signed-in user. The stored bytes SHALL be the response body as received; they SHALL NOT be produced
by re-encoding a decoded model.

#### Scenario: The payload is stored

- **GIVEN** the vault is unlocked and a sync completes successfully
- **WHEN** the sync returns
- **THEN** the response body SHALL be readable from the cache for that user id
- **AND** it SHALL decode to the same `SyncResponse` as the live response

#### Scenario: A field the client does not model survives the cache

- **GIVEN** the server response contains a field the client's models do not decode
- **WHEN** the payload is cached and read back
- **THEN** the field SHALL still be present in the stored bytes

#### Scenario: A failed sync does not damage the cache

- **GIVEN** a usable cache exists
- **WHEN** a sync fails
- **THEN** the cached payload SHALL remain readable and unchanged

### Requirement: An unreachable server SHALL fall back to the cache

When the server cannot be reached, `sync` SHALL populate the vault from the cache instead of failing,
and SHALL report that the data came from the cache together with the payload's age.

#### Scenario: Unlock without a network

- **GIVEN** a usable cache for the signed-in user and no network connection
- **WHEN** the user unlocks with the correct master password
- **THEN** the vault SHALL be opened and populated
- **AND** the result SHALL report the cache as its source
- **AND** the user SHALL be told the data is not live, and how old it is

#### Scenario: A transport failure is distinguishable from a rejection

- **GIVEN** the access token has expired and the server cannot be reached to refresh it
- **WHEN** the user unlocks
- **THEN** the failure SHALL be treated as a transport failure
- **AND** the cache SHALL be used

### Requirement: An answer from the server SHALL NOT be served from the cache

A failure that the server itself reported SHALL NOT fall back to cached data.

#### Scenario: A rejected session is not hidden

- **GIVEN** a usable cache and a server that answers with an authentication rejection
- **WHEN** the user unlocks
- **THEN** the unlock SHALL fail
- **AND** the cached payload SHALL NOT be served

#### Scenario: A key failure is not masked

- **GIVEN** a usable cache
- **WHEN** decryption of the vault fails
- **THEN** the failure SHALL be reported
- **AND** the cached payload SHALL NOT be served as if it were an answer

### Requirement: Missing or unusable cache data SHALL surface the original failure

If the cache cannot be used, the unlock SHALL report the failure that made it necessary, and the vault
SHALL NOT be presented as an empty vault.

#### Scenario: Offline with no cache

- **GIVEN** no usable cache for the signed-in user and no network connection
- **WHEN** the user unlocks with the correct master password
- **THEN** the user SHALL be told the server could not be reached
- **AND** the vault SHALL NOT be shown as unlocked and empty

#### Scenario: Unreadable cache degrades to no cache

- **GIVEN** a cache file that is truncated, corrupt, or written by an unknown schema version
- **WHEN** the cache is read
- **THEN** it SHALL be treated as absent
- **AND** no error from reading it SHALL reach the user in place of the network failure

### Requirement: The cache SHALL be scoped to the account

The cache SHALL be stored per user id, and SHALL be ignored when it was written for a different server
than the account is configured to use.

#### Scenario: Two accounts do not see each other's data

- **GIVEN** a cache exists for one user id
- **WHEN** a different user id unlocks
- **THEN** the first user's cache SHALL NOT be used

#### Scenario: A server change invalidates the cache

- **GIVEN** a cache written for one server URL
- **WHEN** the account's configured server differs
- **THEN** the cache SHALL be treated as absent

### Requirement: The cache SHALL be deleted when the account is signed out

#### Scenario: Sign-out removes the cached payload

- **GIVEN** a signed-in user with a cached payload
- **WHEN** the user signs out
- **THEN** the cached payload SHALL no longer be readable

#### Scenario: Locking does not remove the cached payload

- **GIVEN** a signed-in user with a cached payload
- **WHEN** the vault is locked (by timeout, by sleep, or manually)
- **THEN** the cached payload SHALL remain readable
- **AND** reading it SHALL still require the master password
