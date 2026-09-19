## ADDED Requirements

### Requirement: A Privacy section offers a website icons toggle

The Settings window SHALL display a "Show website icons" toggle in a Privacy section. It SHALL
default to on. Turning it off SHALL take effect immediately without relaunching the app —
`FaviconLoader` reads the preference on every request rather than caching a decision — and SHALL
persist across launches. The section footer SHALL state that icons come from the user's own server
and that turning the setting off skips the request.

#### Scenario: Toggle is shown in the Privacy section
- **GIVEN** the user opens the Settings window
- **WHEN** the Privacy section renders
- **THEN** a "Show website icons" toggle SHALL be visible

#### Scenario: Toggle defaults to on
- **GIVEN** the preference has never been written
- **WHEN** the Settings window opens
- **THEN** the toggle SHALL be on

#### Scenario: Turning it off stops fetching immediately
- **GIVEN** website icons are enabled
- **WHEN** the user turns the toggle off
- **THEN** subsequent favicon requests SHALL return nil and no request SHALL be made
- **AND** this SHALL hold for the remainder of the session without a relaunch

#### Scenario: Preference persists
- **WHEN** the user turns the toggle off and relaunches the app
- **THEN** the toggle SHALL still be off
