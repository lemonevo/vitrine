## ADDED Requirements

### Requirement: Locking clears every session-scoped secret

Locking the vault or signing out SHALL clear, in the same teardown that clears the vault store and
the key caches:

- the re-prompt grants for every item
- the generator history

#### Scenario: Re-prompt grants are cleared on lock
- **GIVEN** the user has entered the master password for two re-prompt-protected items
- **WHEN** the vault is locked
- **THEN** no item SHALL remain granted
- **AND** revealing a protected secret after unlocking SHALL prompt again

#### Scenario: Generator history is cleared on lock
- **GIVEN** the generator history contains entries
- **WHEN** the vault is locked
- **THEN** the history SHALL be empty

#### Scenario: Grants and history are cleared on sign-out
- **GIVEN** the user has entered the master password for an item and the generator history is not
  empty
- **WHEN** the user signs out
- **THEN** the grants SHALL be discarded
- **AND** the history SHALL be empty

#### Scenario: The idle timeout clears them too
- **GIVEN** the idle timeout is configured to lock the vault
- **WHEN** the timeout elapses
- **THEN** the grants SHALL be discarded
- **AND** the history SHALL be empty
