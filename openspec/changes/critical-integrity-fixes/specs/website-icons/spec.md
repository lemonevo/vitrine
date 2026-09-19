## ADDED Requirements

### Requirement: Website icons are fetched from the account's own server

`FaviconLoader` SHALL NOT contain a hardcoded third-party icon service URL. Its icon base SHALL be
resolved from the signed-in account's `ServerEnvironment.iconsURL`, which is `{base}/icons` unless
the account overrides it. The loader SHALL start with no icon base configured, so a domain is never
requested before an account's server is known.

#### Scenario: Icons come from the self-hosted server
- **GIVEN** an account whose base URL is `https://vault.example.com`
- **WHEN** a favicon is requested for `github.com`
- **THEN** the request URL SHALL be `https://vault.example.com/icons/github.com/icon.png`

#### Scenario: A per-service override is honoured
- **GIVEN** an account whose `ServerURLOverrides.icons` is `https://icons.example.com`
- **WHEN** a favicon is requested
- **THEN** the request SHALL be made against that host

#### Scenario: No account yet, no request
- **GIVEN** no account has been signed in during this session
- **WHEN** a favicon is requested
- **THEN** no network request SHALL be made and the call SHALL return nil

#### Scenario: The official icon service is never contacted by default
- **WHEN** any favicon is requested for any domain
- **THEN** `icons.bitwarden.net` SHALL NOT appear in the request

---

### Requirement: Website icons can be turned off

The system SHALL persist a `showWebsiteIcons` preference, defaulting to on. When it is off the
loader SHALL return nil without performing any network request, and callers SHALL fall back to the
existing SF Symbol placeholder.

#### Scenario: Turning the setting off stops all fetching
- **GIVEN** website icons are enabled and one favicon has been loaded
- **WHEN** the user turns "Show website icons" off
- **THEN** subsequent favicon requests SHALL return nil
- **AND** no request SHALL leave the device

#### Scenario: Turning it back on resumes fetching
- **GIVEN** website icons are disabled
- **WHEN** the user turns the setting back on
- **THEN** favicon requests SHALL use the account's icon base again

#### Scenario: Setting persists across launches
- **WHEN** the user disables website icons and relaunches the app
- **THEN** the setting SHALL still be off

---

### Requirement: A failed icon fetch degrades silently to a placeholder

Icon fetching SHALL remain best-effort. A network error, a non-200 response, or undecodable image
data SHALL return nil and SHALL NOT surface an error to the user or block the item list.

#### Scenario: Unreachable icon service does not disturb the list
- **GIVEN** the account's icon service is unreachable
- **WHEN** the item list renders
- **THEN** each row SHALL show its SF Symbol placeholder
- **AND** no error alert SHALL be presented
