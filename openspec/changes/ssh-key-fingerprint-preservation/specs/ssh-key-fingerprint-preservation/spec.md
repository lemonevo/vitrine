## ADDED Requirements

### Requirement: An SSH key item's fingerprint SHALL survive an edit

The key fingerprint SHALL be treated as vault content that is read from the server, held while the
item is edited, and written back — like every other SSH key field. Saving an unrelated change to an
SSH key item SHALL NOT remove its fingerprint.

#### Scenario: Saving an unrelated change preserves the fingerprint

- **GIVEN** an SSH key item whose fingerprint was read from the server
- **WHEN** the item is saved after editing a field that is not the key material
- **THEN** the outgoing cipher SHALL carry the fingerprint
- **AND** a subsequent read of that cipher SHALL return the same fingerprint

#### Scenario: All three SSH key fields round-trip

- **GIVEN** an SSH key item with a private key, a public key and a fingerprint
- **WHEN** it is mapped to the wire format and back
- **THEN** all three SHALL be identical to their original values

#### Scenario: An item with no fingerprint stays without one

- **GIVEN** an SSH key item that carries no fingerprint
- **WHEN** it is saved
- **THEN** the outgoing cipher SHALL NOT gain one

### Requirement: The fingerprint SHALL be documented as client-derived

No comment, doc comment or test may state that the fingerprint is derived by the server or is not
sent to the API — the value is an `EncString` the server cannot read, so a write that omits it
erases it.

Where the accepted consequence is documented, it SHALL state that replacing the key material in the
edit form leaves the stored fingerprint describing the previous key, because the fingerprint is not
recomputed.
