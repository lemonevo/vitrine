## ADDED Requirements

### Requirement: A test SHALL NOT read or write the application's real preference domain

Any test that exercises a persisted preference SHALL use a storage domain of its own, so that
parallel test processes cannot observe or destroy each other's state.

#### Scenario: Two suites exercise the same preference concurrently

- **GIVEN** two test suites that each set and then read a persisted preference
- **WHEN** both run in the same parallel test process group
- **THEN** neither SHALL observe the other's writes or deletions
- **AND** both SHALL pass on every run

#### Scenario: The application's own domain is untouched by tests

- **GIVEN** a test that constructs the view model with a private domain
- **WHEN** it changes the sort order
- **THEN** the value SHALL be written to that private domain
- **AND** the application's shared preference domain SHALL NOT be written to
