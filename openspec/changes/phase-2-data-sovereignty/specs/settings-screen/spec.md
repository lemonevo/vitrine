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

---

### Requirement: The SSH agent section states whether the agent is running, and why not

The Settings window SHALL display an SSH agent section containing: a switch for the feature, a
one-line status, the socket path, the shell line that points `SSH_AUTH_SOCK` at it, and the keys the
agent offers. It SHALL also list the keys it does **not** offer, each with the reason.

The status SHALL distinguish four states — switched off, switched on while the vault is locked,
listening, and failed — and SHALL report a recorded failure in preference to any other state, so a
failed start is never presented as listening. When a start has failed the reason SHALL be shown, not
the word "unavailable". The status SHALL reflect the agent's current state while the pane is open.

#### Scenario: The switch is off
- **GIVEN** the user has not enabled the agent
- **WHEN** the section renders
- **THEN** the status SHALL say the agent is off
- **AND** it SHALL NOT indicate that keys are being served

#### Scenario: Enabled while the vault is locked
- **GIVEN** the switch is on and the vault is locked
- **WHEN** the section renders
- **THEN** the status SHALL say the agent is waiting for the vault to be unlocked
- **AND** it SHALL NOT say the agent is off, and SHALL NOT say it is listening

#### Scenario: A failed start is reported with its reason
- **GIVEN** the agent was enabled and its start failed
- **WHEN** the section renders
- **THEN** the recorded reason SHALL be shown
- **AND** the status SHALL NOT say the agent is listening

#### Scenario: A key the agent cannot use is listed with its reason
- **GIVEN** the vault holds a key in a format Prizm cannot use
- **WHEN** the section renders
- **THEN** that key SHALL appear in the not-offered list
- **AND** the reason SHALL be shown with it, never the name alone

#### Scenario: The vault locks while the pane is open
- **GIVEN** the section is open and the agent is listening
- **WHEN** the vault locks
- **THEN** the status SHALL return to waiting for unlock
- **AND** the key lists SHALL be empty
