## ADDED Requirements

### Requirement: Icon requests carry the account's server trust

The icon loader SHALL fetch through the same `URLSession` the API client uses, and therefore through
the same server-trust configuration. It SHALL NOT construct or receive a session that bypasses that
trust.

The icon endpoint is served by the account's own host — the same host the API client has already
decided to trust, which for a self-hosted deployment with a non-system certificate is a decision
carried by `ServerTrustDelegate` on that one session. A request to the same host over any other
session fails TLS validation against a server the rest of the application reaches normally.

Because failed icon fetches degrade silently by requirement, this failure has no user-visible symptom
beyond a vault of placeholder glyphs. It is therefore stated as a requirement rather than left to
observation: the two network paths to one host must not differ in trust.

#### Scenario: Icons and API share one session
- **GIVEN** an account whose server is only trusted because of the app's server-trust configuration
- **WHEN** a favicon is requested
- **THEN** the request SHALL be made through the session carrying that configuration
- **AND** it SHALL succeed on a server where the API requests succeed

#### Scenario: No network constructor defaults to an untrusted session
- **WHEN** `FaviconLoader` or `PrizmAPIClientImpl` is constructed
- **THEN** the session SHALL be a required argument with no default
- **AND** for the API client the trust delegate SHALL likewise be an explicit argument

#### Scenario: Trust failure is still not surfaced to the user
- **GIVEN** an icon request that fails for any reason
- **WHEN** the item list renders
- **THEN** the row SHALL show its placeholder and no error SHALL be presented
- **AND** this SHALL NOT be read as evidence that the request succeeded
