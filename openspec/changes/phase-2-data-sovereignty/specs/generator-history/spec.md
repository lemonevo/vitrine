## ADDED Requirements

### Requirement: Recently generated values are kept for the session

The password generator SHALL keep the most recently generated values, each with the time it was
generated, up to a maximum of 20. The list SHALL be cleared when the vault is locked or the user
signs out.

#### Scenario: A generated value is recorded
- **GIVEN** the generator has produced a value
- **WHEN** the user copies it
- **THEN** it SHALL appear in the history, most recent first

#### Scenario: The list is bounded
- **GIVEN** 25 values have been generated and copied
- **WHEN** the history is inspected
- **THEN** it SHALL contain 20 entries
- **AND** the oldest 5 SHALL be gone
- **AND** the newest SHALL be first

#### Scenario: Locking clears the history
- **GIVEN** the history contains 5 entries
- **WHEN** the vault is locked
- **THEN** the history SHALL be empty

#### Scenario: Signing out clears the history
- **GIVEN** the history contains 5 entries
- **WHEN** the user signs out
- **THEN** the history SHALL be empty

#### Scenario: A value is recorded only when it is used
- **GIVEN** the generator regenerates a value five times without the user copying any of them
- **WHEN** the history is inspected
- **THEN** it SHALL be empty

---

### Requirement: The history is never written to disk

The history SHALL be held in memory only. It SHALL NOT be persisted to `UserDefaults`, the Keychain,
or any file, and SHALL NOT survive quitting the application.

#### Scenario: Nothing is persisted
- **GIVEN** the history contains 5 entries
- **WHEN** the application is quit and relaunched
- **THEN** the history SHALL be empty

#### Scenario: The UI states the lifetime
- **GIVEN** the history section is displayed
- **WHEN** the user reads it
- **THEN** a footer SHALL state that the history is kept in memory and cleared when the vault locks

---

### Requirement: A history entry can be copied

Each history entry SHALL offer a copy action that places its value on the clipboard, applying the
configured clipboard-clearing interval.

#### Scenario: Copying from the history
- **GIVEN** the history contains an entry
- **WHEN** the user copies it
- **THEN** the value SHALL be on the clipboard
- **AND** the clipboard SHALL be cleared after the configured interval
