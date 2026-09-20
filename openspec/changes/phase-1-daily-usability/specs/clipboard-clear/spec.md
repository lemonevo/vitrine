## ADDED Requirements

### Requirement: How long a copied value stays on the clipboard is configurable

The Settings window SHALL offer a clipboard-clearing interval with the choices 10 seconds,
20 seconds, 30 seconds, 1 minute, 2 minutes and never. The default SHALL be 30 seconds, matching
the behaviour that existed before this setting was introduced. The chosen value SHALL persist
across launches.

The interval SHALL be read at the moment of copying, so a change takes effect on the next copy
without relaunching the application. When the interval elapses the clipboard SHALL be cleared only
if the value this application wrote is still on it — a value the user has since copied from
elsewhere SHALL be left untouched.

Choosing "never" SHALL leave the copied value on the clipboard indefinitely.

#### Scenario: Copied value is cleared after the configured interval
- **GIVEN** the clipboard interval is 10 seconds
- **WHEN** the user copies a password
- **THEN** the clipboard SHALL contain the password
- **AND** it SHALL be cleared once 10 seconds have passed

#### Scenario: Default interval is 30 seconds
- **GIVEN** the interval has never been written
- **WHEN** the user copies a value
- **THEN** it SHALL be cleared after 30 seconds

#### Scenario: Never leaves the value in place
- **GIVEN** the clipboard interval is set to never
- **WHEN** the user copies a password
- **THEN** the clipboard SHALL still contain the password after any length of time

#### Scenario: A newer copy supersedes the pending clear
- **GIVEN** the user copied a password 5 seconds ago
- **WHEN** the user copies a second password
- **THEN** only one clear SHALL be pending, and it SHALL be the one for the second password

#### Scenario: A value copied from elsewhere is not cleared
- **GIVEN** the user copied a value from Prizm
- **WHEN** the user copies something else from another application before the interval elapses
- **THEN** Prizm SHALL NOT clear the clipboard

#### Scenario: Interval persists
- **WHEN** the user selects an interval and relaunches the application
- **THEN** the selected interval SHALL still be in effect
