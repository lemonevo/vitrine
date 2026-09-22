## ADDED Requirements

### Requirement: An unlocked vault locks itself after a configurable idle period

The Settings window SHALL offer an idle-timeout interval with the choices 1 minute, 5 minutes,
15 minutes, 30 minutes, 1 hour and never. The default SHALL be 15 minutes. The chosen value SHALL
persist across launches.

Idle time SHALL be measured from the most recent local user input — key press, mouse button, scroll
or mouse movement — delivered to the application. Input delivered to other applications SHALL NOT
count as activity, because an idle Vitrine is an idle Vitrine regardless of what the user is doing
elsewhere.

When the interval elapses the vault SHALL be locked and the key caches cleared, using the same
teardown as the existing sleep, screensaver and screen-lock locks. Choosing "never" SHALL disable
the idle timeout entirely while leaving those event-driven locks in place.

The activity observer SHALL be an observer only: it SHALL pass every event through unchanged and
SHALL NOT suppress or alter user input.

#### Scenario: Vault locks after the interval elapses with no activity
- **GIVEN** the vault is unlocked and the idle interval is 1 minute
- **WHEN** no user input reaches the application for 1 minute
- **THEN** the vault SHALL lock and the unlock screen SHALL be shown

#### Scenario: Activity postpones the lock
- **GIVEN** the vault is unlocked and the idle interval is 1 minute
- **WHEN** the user presses a key 50 seconds after the last input
- **THEN** the vault SHALL remain unlocked at 1 minute after the original input

#### Scenario: Input to another application does not count as activity
- **GIVEN** the vault is unlocked with an idle interval of 1 minute
- **WHEN** the user types in another application for 5 minutes without interacting with Vitrine
- **THEN** the vault SHALL lock

#### Scenario: Never disables the idle timeout
- **GIVEN** the idle interval is set to never
- **WHEN** the application receives no input for any length of time
- **THEN** the vault SHALL remain unlocked

#### Scenario: The interval persists
- **WHEN** the user selects an interval and relaunches the application
- **THEN** the selected interval SHALL still be in effect

#### Scenario: A locked vault is not affected
- **GIVEN** the vault is already locked
- **WHEN** the idle interval elapses
- **THEN** nothing further SHALL happen

---

### Requirement: The timeout action is configurable between locking and signing out

The Settings window SHALL offer a timeout action with the choices "Lock vault" and "Sign out". The
default SHALL be "Lock vault". The chosen value SHALL persist across launches.

"Lock vault" SHALL clear the in-memory vault and all key material while keeping the stored session,
so the user returns to the unlock screen. "Sign out" SHALL additionally discard the stored session,
so the user returns to the sign-in screen.

#### Scenario: Lock action returns to the unlock screen
- **GIVEN** the timeout action is "Lock vault" and the vault is unlocked
- **WHEN** the idle timeout elapses
- **THEN** the vault SHALL be cleared, key caches SHALL be cleared, and the unlock screen SHALL be shown
- **AND** the stored session SHALL be kept, so the account email is still shown on the unlock screen

#### Scenario: Sign out action returns to the sign-in screen
- **GIVEN** the timeout action is "Sign out" and the vault is unlocked
- **WHEN** the idle timeout elapses
- **THEN** all session data SHALL be cleared and the sign-in screen SHALL be shown

#### Scenario: Action persists
- **WHEN** the user selects an action and relaunches the application
- **THEN** the selected action SHALL still be in effect
