## ADDED Requirements

### Requirement: The account fingerprint phrase is derived from the account's public key

The application SHALL display a five-word phrase derived from the account's public key, so the user
can confirm that two clients are talking to the same account.

The phrase SHALL be computed with the same algorithm the official Bitwarden clients use, from the
same public key and the same word list, so that it matches what another client displays. The
algorithm SHALL be verified against the reference implementation before this requirement is
implemented; if it cannot be verified, the feature SHALL NOT ship.

#### Scenario: The phrase is five words
- **GIVEN** the vault is unlocked
- **WHEN** the fingerprint phrase is displayed
- **THEN** it SHALL consist of five words

#### Scenario: The phrase is stable
- **GIVEN** the fingerprint phrase has been displayed once
- **WHEN** it is displayed again, in the same session or a later one
- **THEN** it SHALL be the same five words

#### Scenario: The phrase matches another client
- **GIVEN** the same account is open in another Bitwarden-compatible client
- **WHEN** both clients display the fingerprint phrase
- **THEN** the two phrases SHALL be identical

#### Scenario: A different account produces a different phrase
- **GIVEN** two different accounts
- **WHEN** their fingerprint phrases are displayed
- **THEN** the phrases SHALL differ

#### Scenario: The phrase is not secret
- **GIVEN** the phrase is displayed
- **WHEN** the user reads the surrounding text
- **THEN** it SHALL state that the phrase is not a secret and is safe to compare aloud

#### Scenario: The phrase is unavailable when it cannot be derived
- **GIVEN** the account has no private key on the server
- **WHEN** the phrase is requested
- **THEN** the application SHALL state that it cannot be derived
- **AND** it SHALL NOT display a placeholder phrase
