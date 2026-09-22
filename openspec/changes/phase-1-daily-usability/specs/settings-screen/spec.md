## ADDED Requirements

### Requirement: The Security section offers vault timeout controls

The Settings window SHALL display an idle-timeout interval picker and a timeout action picker in
the Security section, alongside the existing biometric toggle. The interval picker SHALL offer
1 minute, 5 minutes, 15 minutes, 30 minutes, 1 hour and never, defaulting to 15 minutes. The action
picker SHALL offer "Lock vault" and "Sign out", defaulting to "Lock vault". Both SHALL take effect
without relaunching the application and SHALL persist across launches.

The section footer SHALL state that the timeout applies while the vault is unlocked and that input
delivered to other applications does not count as activity.

#### Scenario: Timeout controls are visible
- **GIVEN** the user opens the Settings window
- **WHEN** the Security section renders
- **THEN** an idle-timeout picker and a timeout action picker SHALL be visible

#### Scenario: Defaults
- **GIVEN** neither setting has ever been written
- **WHEN** the Security section renders
- **THEN** the interval SHALL show 15 minutes and the action SHALL show "Lock vault"

#### Scenario: Changing the interval takes effect immediately
- **GIVEN** the vault is unlocked
- **WHEN** the user selects a different interval
- **THEN** the new interval SHALL govern the running idle timer without a relaunch

---

### Requirement: The Privacy section offers a clipboard clearing interval

The Settings window SHALL display a clipboard-clearing interval picker in the Privacy section,
alongside the existing website icons toggle. It SHALL offer 10 seconds, 20 seconds, 30 seconds,
1 minute, 2 minutes and never, defaulting to 30 seconds. The footer SHALL state that the clipboard
is cleared only if Vitrine's own value is still on it.

#### Scenario: Clipboard picker is visible
- **GIVEN** the user opens the Settings window
- **WHEN** the Privacy section renders
- **THEN** a clipboard-clearing interval picker SHALL be visible

#### Scenario: Default is 30 seconds
- **GIVEN** the setting has never been written
- **WHEN** the Privacy section renders
- **THEN** the picker SHALL show 30 seconds
