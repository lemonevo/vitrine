## ADDED Requirements

### Requirement: Saving a cipher SHALL NOT lose a field the client received

`PUT /ciphers/{id}` replaces the entire cipher, and Vaultwarden stores the object verbatim, so a field
absent from the request body is deleted rather than left alone. The system SHALL therefore be covered
by an automated check that, for every field the decoder can read out of a cipher, the encoder writes
something back.

The check SHALL be expressed wire → model → wire, comparing the two wire forms by JSON path. It SHALL
NOT be expressed as a `VaultItem` round-trip: a field with no place in the model cannot be asserted
about from the model, which is why four separate instances of this defect survived a suite that
contained round-trip tests.

The check SHALL waive value equality for re-encrypted fields, which legitimately differ on every save,
and SHALL NOT waive their presence.

Every exception to the rule SHALL state a reason, and the check SHALL verify that each exception still
corresponds to something the encoder actually drops, so a stale exception cannot quietly excuse the
next lost field.

#### Scenario: A dropped field is reported by name
- **GIVEN** an encoder that stops sending a field the decoder reads
- **WHEN** the invariant check runs
- **THEN** it SHALL fail, naming the JSON path that arrived and did not go back out

#### Scenario: A rewritten value is reported
- **GIVEN** an encoder that substitutes a default for a stored value it does not model — the
  secure-note subtype, for example
- **WHEN** the invariant check runs
- **THEN** it SHALL fail, naming the path and both values

#### Scenario: An encrypted field that vanishes is still reported
- **GIVEN** an encoder that sends `nil` for a field whose stored form is an EncString
- **WHEN** the invariant check runs
- **THEN** it SHALL fail despite the equality waiver for encrypted values

#### Scenario: A stale exception fails the check
- **GIVEN** an omitted path listed as tolerated that the encoder now sends
- **WHEN** the invariant check runs
- **THEN** it SHALL fail, asking for the entry to be removed

### Requirement: Key caches SHALL be covered by clearing tests

Each in-memory key cache SHALL have tests asserting that nothing is reachable through it after
`clear()`, and that storing again afterwards still works.

The tests SHALL NOT claim that key bytes are erased from memory. `Data` is copy-on-write, so zeroing
one value reaches its own storage and leaves any other live reference holding the original bytes; the
boundary SHALL be stated as a test rather than left implied by a passing suite.

#### Scenario: Nothing survives clearing
- **WHEN** an org key cache or the account key cache is cleared
- **THEN** every lookup SHALL return nothing
- **AND** a subsequent store SHALL be readable

#### Scenario: The limit of the guarantee is written down
- **WHEN** the zeroing behaviour is tested
- **THEN** a test SHALL assert that another live copy of the buffer is unaffected
- **AND** no test SHALL assert that `clear()` erases key material from memory
