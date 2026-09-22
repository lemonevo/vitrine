## ADDED Requirements

### Requirement: URI match strategies are the Bitwarden wire integers
A website entry's matching strategy SHALL be stored, exported and displayed as Bitwarden's
`UriMatchStrategySetting` integer: 0 default, 1 base domain, 2 host, 3 starts with, 4 exact,
5 regular expression, 6 never. The values SHALL be mapped explicitly in both directions rather than
inherited from an `Int`-backed enum, and the numbers SHALL be asserted case by case in tests.

This is stated as a requirement because a mapping that is wrong identically in both directions
round-trips perfectly. Every consistency check passes while the app writes a different rule than the
one the user chose, and the only thing that catches it is an assertion about the numbers themselves.

#### Scenario: Never is 6, not 5
- **GIVEN** a user sets a website entry's match type to "Never"
- **WHEN** the item is saved
- **THEN** the request body SHALL carry `match: 6`
- **AND** it SHALL NOT carry 5, which the browser reads as a regular expression and acts on by autofilling

#### Scenario: A rule set elsewhere is not erased by a save
- **GIVEN** a vault item whose entry carries `match: 6` from another client
- **WHEN** Prizm displays it and later saves the item for any reason
- **THEN** the entry SHALL still carry 6 afterwards

#### Scenario: A favourite toggle does not rewrite the rules
- **GIVEN** a login with URI entries carrying strategies 1 through 6
- **WHEN** the user toggles its favourite state
- **THEN** each entry's strategy SHALL be unchanged on the server

---

### Requirement: A strategy this build cannot name is carried, not normalised
An incoming integer outside the known range SHALL be held as an unknown value and written back
unchanged. It SHALL NOT decode to "no strategy chosen", and the edit form SHALL show it as the number
it is rather than offering it as a choice.

Decoding to nothing and re-encoding as nothing is how an unrecognised value becomes a deletion, which is
the same failure the SSH key fingerprint, the secure-note subtype and the collection permissions each
already had.

#### Scenario: An unknown strategy survives
- **GIVEN** an entry arrives with `match: 7`
- **WHEN** the item is saved again
- **THEN** the body SHALL carry `match: 7`
- **AND** the edit form SHALL label the row with 7 rather than "Default"

#### Scenario: The picker does not offer what it cannot name
- **WHEN** the match-type picker is opened
- **THEN** it SHALL list the named strategies only
- **AND** an already-stored unknown value SHALL remain selected and visible
