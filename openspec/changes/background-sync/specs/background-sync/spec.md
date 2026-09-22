## ADDED Requirements

### Requirement: The vault SHALL refresh on a timer while the session is unlocked

While the vault is unlocked, the app SHALL re-sync the vault without user action, on an interval
measured from the last **successful** sync. The interval SHALL be a fixed constant, not a setting.

The refresh SHALL reuse the sync path that the manual sync uses, so a background refresh produces the
same result as a manual one: refreshed items, counts, folders, organisations and last-sync timestamp.

A refresh SHALL NOT be started while the vault is locked.

#### Scenario: An interval passes while unlocked

- **GIVEN** the vault is unlocked
- **AND** at least one interval has elapsed since the last successful sync
- **WHEN** the timer fires
- **THEN** a vault sync SHALL be performed
- **AND** on success the item list, counts, folders, organisations and last-sync timestamp SHALL be refreshed

#### Scenario: The interval has not elapsed

- **GIVEN** the vault is unlocked
- **WHEN** the timer fires less than one interval after the last successful sync
- **THEN** no sync SHALL be performed

#### Scenario: A failed attempt does not shorten the interval

- **GIVEN** a background refresh has failed
- **WHEN** the timer fires again shortly after
- **THEN** no sync SHALL be performed until a full interval has elapsed since the last **successful** sync

#### Scenario: Locked means no refresh

- **GIVEN** the vault is locked
- **WHEN** the interval elapses
- **THEN** no sync SHALL be performed
- **AND** no vault key material SHALL be required to remain resident for one

### Requirement: The vault SHALL refresh when the app or the machine becomes active again

A periodic interval alone does not cover the case of a session that was suspended. The app SHALL
refresh when it becomes active again and when the machine wakes, subject to the same interval and
busy-session rules as a timer tick, so that reactivation cannot produce a burst of syncs.

#### Scenario: The app becomes active after a long absence

- **GIVEN** the vault is unlocked and was not the active application
- **AND** at least one interval has elapsed since the last successful sync
- **WHEN** the app becomes active
- **THEN** a vault sync SHALL be performed

#### Scenario: Rapid switching does not sync repeatedly

- **GIVEN** a sync succeeded a moment ago
- **WHEN** the user switches away from the app and back, repeatedly
- **THEN** no further sync SHALL be performed until an interval has elapsed

#### Scenario: The machine wakes

- **GIVEN** the machine has been asleep with the session unlocked
- **WHEN** the machine wakes and an interval has elapsed
- **THEN** a vault sync SHALL be performed without user action

### Requirement: A refresh SHALL NOT run while another sync or a mutation is in flight

At most one sync SHALL run at a time, and the in-flight state SHALL be shared with the manual sync
rather than duplicated. A refresh whose tick lands while a sync is already running SHALL be dropped,
not queued.

A refresh SHALL NOT run while the session is mid-edit or a mutation is in flight, because completing
one replaces the selected item and the item list from the store.

#### Scenario: A tick during a manual sync is dropped

- **GIVEN** a manual sync is in flight
- **WHEN** a background tick fires
- **THEN** no second sync SHALL be started
- **AND** the manual sync SHALL be unaffected

#### Scenario: A tick during an edit is dropped

- **GIVEN** the edit sheet is open on an item
- **WHEN** a background tick fires
- **THEN** no sync SHALL be performed
- **AND** the draft in the edit sheet SHALL be unchanged

#### Scenario: A tick during a mutation is dropped

- **GIVEN** a delete, duplicate or save is in flight
- **WHEN** a background tick fires
- **THEN** no sync SHALL be performed

#### Scenario: A dropped tick does not disable later ones

- **GIVEN** a tick was dropped because the session was busy
- **WHEN** the session becomes idle and an interval has elapsed
- **THEN** a later tick SHALL perform a sync

### Requirement: A failed refresh SHALL NOT interrupt the user

A background refresh that fails SHALL NOT present the dismissable sync error banner that a manual
sync presents, SHALL NOT move the last-sync timestamp, and SHALL be recorded in the log.

The last-sync timestamp SHALL continue to reflect the most recent successful sync, so that the
sidebar's relative label ages while refreshes are failing.

#### Scenario: Failure is quiet but visible

- **GIVEN** the vault is unlocked and the server is unreachable
- **WHEN** a background refresh fails
- **THEN** no dismissable error banner SHALL be shown
- **AND** the failure SHALL be logged
- **AND** the last-sync label SHALL continue to age from the last successful sync

#### Scenario: A manual failure still interrupts

- **GIVEN** the user triggers a manual sync
- **WHEN** it fails
- **THEN** the sync error banner SHALL be shown

#### Scenario: Recovery is silent

- **GIVEN** background refreshes have been failing
- **WHEN** one succeeds
- **THEN** the last-sync timestamp SHALL advance
- **AND** no error SHALL be shown
