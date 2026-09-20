## ADDED Requirements

### Requirement: A password can be scored on a five-point scale

The application SHALL provide a password-strength estimate producing a score from 0 (very weak) to
4 (very strong), derived from a guess-count model computed entirely on the device. No password
SHALL be sent anywhere to produce the score.

The estimator SHALL apply penalties for patterns that collapse the search space: repeated
characters, keyboard and alphabet sequences, date-like runs, a match against a list of common
passwords, and a match against a word list for passphrase words.

#### Scenario: A trivial password scores lowest
- **GIVEN** the password `password`
- **WHEN** it is scored
- **THEN** the score SHALL be 0

#### Scenario: A padded common password does not score highly
- **GIVEN** the password `Password1!`
- **WHEN** it is scored
- **THEN** the score SHALL be at most 1

#### Scenario: A repeated character does not score highly
- **GIVEN** the password `aaaaaaaaaaaaaaaa`
- **WHEN** it is scored
- **THEN** the score SHALL be at most 1

#### Scenario: A keyboard sequence does not score highly
- **GIVEN** the password `qwerty123`
- **WHEN** it is scored
- **THEN** the score SHALL be at most 1

#### Scenario: A long passphrase scores highly
- **GIVEN** the password `correct-horse-battery-staple`
- **WHEN** it is scored
- **THEN** the score SHALL be at least 3

#### Scenario: A long random password scores highest
- **GIVEN** a 20-character password drawn uniformly from letters, digits and symbols
- **WHEN** it is scored
- **THEN** the score SHALL be 4

#### Scenario: An empty password scores lowest
- **GIVEN** an empty password
- **WHEN** it is scored
- **THEN** the score SHALL be 0
- **AND** no weakness SHALL be named

---

### Requirement: The estimate names its dominant weakness

When a password scores below *strong*, the estimate SHALL name the single pattern contributing most
to the weakness, so the user can act on it rather than merely being told the password is bad.

#### Scenario: A common password is named as such
- **GIVEN** the password `letmein`
- **WHEN** it is scored
- **THEN** the weakness SHALL identify it as a commonly used password

#### Scenario: A short password is named as short
- **GIVEN** the password `Tr0ub4`
- **WHEN** it is scored
- **THEN** the weakness SHALL identify its length

#### Scenario: A strong password has no weakness
- **GIVEN** a password scoring 4
- **WHEN** it is scored
- **THEN** no weakness SHALL be named

---

### Requirement: The estimate is presented as an estimate

The score SHALL be labelled as an estimate wherever it is shown, and the application SHALL NOT
claim the score is a breach check or a guarantee. The leaked-password check SHALL NOT be performed,
because it would require disclosing data to a third party.

#### Scenario: The label says estimate
- **GIVEN** the strength readout is displayed
- **WHEN** the user reads it
- **THEN** it SHALL be labelled as an estimate

#### Scenario: No network request is made
- **GIVEN** a password is scored
- **WHEN** the scoring runs
- **THEN** no network request SHALL be made

---

### Requirement: The estimator's limitations are documented

The type's doc comment SHALL state that the estimator is not `zxcvbn`, SHALL state how many common
passwords the embedded list contains, and SHALL state which patterns are not modelled. `SECURITY.md`
SHALL carry the same statement in plain language.

#### Scenario: The limitation is visible in the source
- **GIVEN** a developer reads `PasswordStrength.swift`
- **WHEN** they read the doc comment
- **THEN** they SHALL find the word list size, the unmodelled patterns, and the fact that this is
  not `zxcvbn`
