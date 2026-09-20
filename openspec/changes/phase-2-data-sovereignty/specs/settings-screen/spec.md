## ADDED Requirements

### Requirement: The Security section offers server certificate controls

The Settings window SHALL display a server-certificate subsection in the Security section
containing: a certificate-pinning toggle, the currently recorded fingerprint when one exists, an
action to trust a certificate authority from a file, and an action to forget the recorded
fingerprint. The forget action SHALL be available whenever a fingerprint exists.

The subsection footer SHALL state that the trust applies only to the configured server and that a
changed certificate will be refused while pinning is on.

#### Scenario: The controls are visible
- **GIVEN** the user opens the Settings window
- **WHEN** the Security section renders
- **THEN** a pinning toggle SHALL be visible
- **AND** a trust-a-certificate action SHALL be visible

#### Scenario: No fingerprint is shown before one is recorded
- **GIVEN** no fingerprint has been recorded
- **WHEN** the Security section renders
- **THEN** no fingerprint SHALL be displayed

#### Scenario: The fingerprint is shown once recorded
- **GIVEN** a fingerprint has been recorded
- **WHEN** the Security section renders
- **THEN** the fingerprint SHALL be displayed in a copyable form

#### Scenario: Forget is available only when there is something to forget
- **GIVEN** no fingerprint has been recorded
- **WHEN** the Security section renders
- **THEN** the forget action SHALL be disabled

#### Scenario: Trusting a certificate does not require pinning
- **GIVEN** pinning is off
- **WHEN** the user trusts a certificate authority
- **THEN** the authority SHALL be trusted
- **AND** pinning SHALL remain off

---

### Requirement: Certificate settings state their scope

The subsection SHALL state which host the trust material applies to, and SHALL state that a
self-signed server will fail to connect until its authority is trusted.

#### Scenario: The host is named
- **GIVEN** the configured server is `vault.example.com`
- **WHEN** the certificate subsection renders
- **THEN** it SHALL name that host
