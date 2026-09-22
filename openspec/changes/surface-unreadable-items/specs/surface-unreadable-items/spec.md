## ADDED Requirements

### Requirement: Items that could not be read SHALL be reported to the user

A sync that cannot decrypt some of the vault's items SHALL present the number of those items to the
user, and SHALL keep presenting it for as long as the condition holds. The user SHALL NOT be required
to dismiss it, and dismissing SHALL NOT be possible, because the underlying condition — the vault on
screen is incomplete — persists independently of whether the message has been read.

The count SHALL cover every item the sync could not produce, whether the item is personal or
belongs to an organisation.

The presentation SHALL state that the items still exist on the server, so that a user does not
conclude they were deleted.

#### Scenario: A partial vault is reported

- **GIVEN** a sync that could not read some items
- **WHEN** the vault is displayed
- **THEN** the number of unreadable items SHALL be shown
- **AND** the rest of the vault SHALL remain usable

#### Scenario: Organisation items are included

- **GIVEN** a sync in which an organisation item could not be read and no personal item failed
- **WHEN** the vault is displayed
- **THEN** the reported number SHALL include that item

#### Scenario: A complete vault reports nothing

- **GIVEN** a sync that read every item
- **WHEN** the vault is displayed
- **THEN** no unreadable-item message SHALL be shown

#### Scenario: The report clears when the condition does

- **GIVEN** the vault previously reported unreadable items
- **WHEN** a later sync reads every item
- **THEN** the report SHALL no longer be shown

#### Scenario: The report does not outlive its session

- **GIVEN** the vault reported unreadable items
- **WHEN** the vault is locked or the user signs out
- **THEN** the report SHALL be cleared with the rest of the session's state

#### Scenario: One item is described in the singular

- **GIVEN** exactly one item could not be read
- **WHEN** the message is shown
- **THEN** it SHALL read as a singular sentence

### Requirement: The sync's diagnostic log SHALL label cipher types correctly

The debug breakdown of cipher types SHALL use the same type-to-name mapping as the mapper and the
wire model (1=Login, 2=SecureNote, 3=Card, 4=Identity, 5=SSHKey). A mislabelled breakdown sends
diagnosis in the wrong direction, which is the only thing the line exists to prevent.

#### Scenario: A secure note is not labelled an identity

- **GIVEN** sync debug logging is enabled
- **AND** the response contains a cipher of type 2
- **WHEN** the breakdown is logged
- **THEN** it SHALL be labelled as a secure note
