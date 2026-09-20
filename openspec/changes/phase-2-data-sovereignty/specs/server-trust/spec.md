## ADDED Requirements

### Requirement: A custom certificate authority can be trusted for the user's own server

The application SHALL allow the user to select a certificate file and trust it as the certificate
authority for the configured server. When a certificate authority is trusted, the server's
certificate chain SHALL be evaluated against it and only it, so a self-signed deployment becomes
usable without weakening the default evaluation for any other host.

Trusting a certificate SHALL NOT enable `NSAllowsArbitraryLoads` or any other App Transport
Security exception.

#### Scenario: A self-signed server becomes reachable
- **GIVEN** the server presents a certificate from a private authority
- **AND** the user has trusted that authority's certificate
- **WHEN** the application connects to that server
- **THEN** the connection SHALL succeed

#### Scenario: The trusted authority is the only anchor
- **GIVEN** the user has trusted a private authority
- **AND** the server presents a certificate chaining to a different authority
- **WHEN** the application connects
- **THEN** the connection SHALL be refused

#### Scenario: Other hosts are unaffected
- **GIVEN** the user has trusted a private authority for their own server
- **WHEN** the application connects to a different host, such as a blob storage endpoint
- **THEN** the default system evaluation SHALL be used

#### Scenario: An unreadable file is rejected
- **GIVEN** the user selects a file that is not a certificate
- **WHEN** the trust is added
- **THEN** an error SHALL be reported
- **AND** nothing SHALL be stored

---

### Requirement: The server certificate can be pinned

The application SHALL offer an opt-in pinning setting. When enabled, the SHA-256 fingerprint of the
server's leaf certificate SHALL be recorded on the first successful connection, and every later
connection SHALL be required to present a certificate with the same fingerprint.

Pinning SHALL be off by default.

#### Scenario: Pinning is off by default
- **GIVEN** the setting has never been changed
- **WHEN** the Security section renders
- **THEN** the pinning toggle SHALL be off

#### Scenario: The first connection records the fingerprint
- **GIVEN** pinning is enabled and no fingerprint has been recorded
- **WHEN** the application connects successfully
- **THEN** the leaf certificate's SHA-256 fingerprint SHALL be stored
- **AND** it SHALL be displayed in Settings

#### Scenario: A matching certificate is accepted
- **GIVEN** pinning is enabled and a fingerprint is recorded
- **WHEN** the server presents a certificate with that fingerprint
- **THEN** the connection SHALL succeed

#### Scenario: A changed certificate is refused
- **GIVEN** pinning is enabled and a fingerprint is recorded
- **WHEN** the server presents a certificate with a different fingerprint
- **THEN** the connection SHALL be refused
- **AND** the error SHALL state that the server's certificate changed
- **AND** the error SHALL NOT be a generic network failure

#### Scenario: The pin can be forgotten
- **GIVEN** a fingerprint is recorded
- **WHEN** the user chooses to forget it
- **THEN** the stored fingerprint SHALL be removed
- **AND** the next connection SHALL record a new one

---

### Requirement: Trust material is stored per server in the Keychain

The trusted authority and the recorded fingerprint SHALL be stored in the Keychain, scoped to the
server's host, accessible only while the device is unlocked and never synchronisable. They SHALL NOT
be stored in `UserDefaults`.

#### Scenario: Material is scoped to the server
- **GIVEN** a certificate is trusted for `vault.example.com`
- **WHEN** the user points the application at a different server
- **THEN** that trust SHALL NOT apply

#### Scenario: Material is not in UserDefaults
- **GIVEN** a certificate has been trusted and a fingerprint recorded
- **WHEN** the application's `UserDefaults` domain is inspected
- **THEN** neither the certificate nor the fingerprint SHALL be present

#### Scenario: Forgetting one server leaves others alone
- **GIVEN** trust material exists for two servers
- **WHEN** the user forgets the pinned certificate for one
- **THEN** the other server's material SHALL remain
