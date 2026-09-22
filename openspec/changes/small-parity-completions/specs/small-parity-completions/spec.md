## ADDED Requirements

### Requirement: The generator SHALL offer a username mode

The password generator SHALL offer a username alongside passwords and passphrases, drawn from the
word list the passphrase mode already uses, and SHALL be configurable independently of the other two
modes.

#### Scenario: Generating a username

- **GIVEN** the generator is in username mode
- **WHEN** a username is generated
- **THEN** it SHALL be composed of words from the configured word list
- **AND** it SHALL carry the configured number of digits

#### Scenario: The modes do not share settings

- **GIVEN** a configured passphrase word count
- **WHEN** the username mode is selected
- **THEN** the passphrase's setting SHALL be unchanged
- **AND** changing the username mode's settings SHALL NOT change the passphrase's

#### Scenario: A generated username can be copied

- **GIVEN** a generated username
- **WHEN** it is copied
- **THEN** it SHALL reach the clipboard through the same path as the other modes
- **AND** the configured clipboard clear interval SHALL apply to it

### Requirement: The Trash SHALL state that its contents expire

When the Trash holds items, the app SHALL state that they are permanently deleted automatically. It
SHALL NOT state an interval it cannot know, because the retention period is a server setting.

#### Scenario: The notice appears with contents

- **GIVEN** the Trash holds at least one item
- **WHEN** the Trash is displayed
- **THEN** the notice about automatic deletion SHALL be shown

#### Scenario: No notice for an empty Trash

- **GIVEN** the Trash is empty
- **WHEN** the Trash is displayed
- **THEN** no notice about automatic deletion SHALL be shown
