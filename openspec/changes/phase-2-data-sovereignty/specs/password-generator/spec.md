## ADDED Requirements

### Requirement: The generator shows a strength readout

The password generator SHALL display the strength of the value it has produced, using the shared
estimator, labelled as an estimate.

#### Scenario: The readout follows the generated value
- **GIVEN** the generator is open in password mode
- **WHEN** a new value is generated
- **THEN** the strength readout SHALL reflect that value

#### Scenario: Changing the configuration updates the readout
- **GIVEN** the generator has produced a 16-character value
- **WHEN** the length is reduced to 6
- **THEN** the readout SHALL reflect the new value

#### Scenario: The readout is labelled as an estimate
- **GIVEN** the readout is displayed
- **WHEN** the user reads it
- **THEN** it SHALL be labelled as an estimate

---

### Requirement: The generator lists its session history

The generator SHALL display the values generated and used during this session, most recent first,
with a copy action per entry and a footer stating that the list is kept in memory and cleared when
the vault locks. The section SHALL be collapsed by default.

#### Scenario: The section is collapsed by default
- **GIVEN** the generator sheet is opened
- **WHEN** it renders
- **THEN** the history section SHALL be collapsed

#### Scenario: The footer states the lifetime
- **GIVEN** the history section is expanded
- **WHEN** the user reads it
- **THEN** a footer SHALL state that the list is kept in memory and cleared when the vault locks

#### Scenario: An entry can be copied
- **GIVEN** the history contains an entry
- **WHEN** the user copies it
- **THEN** the value SHALL be on the clipboard
