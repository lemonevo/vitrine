## ADDED Requirements

### Requirement: A secure note's subtype SHALL be preserved

The secure note subtype SHALL be read from the server, held while the item is edited, and written
back. A subtype this build does not recognise SHALL be preserved as it arrives rather than
normalised to Generic.

#### Scenario: A subtype set elsewhere survives an edit

- **GIVEN** a secure note whose subtype was set to Passport by another client
- **WHEN** the item is opened and saved in Prizm without changing the subtype
- **THEN** the outgoing cipher SHALL carry Passport
- **AND** re-reading that cipher SHALL yield Passport

#### Scenario: Every documented subtype round-trips

- **GIVEN** a secure note of any of the documented subtypes
- **WHEN** it is mapped to the wire format and back
- **THEN** the subtype SHALL be unchanged

#### Scenario: An unrecognised subtype is not flattened

- **GIVEN** a secure note whose subtype integer this build does not know
- **WHEN** the item is mapped to the wire format and back
- **THEN** the subtype integer SHALL be unchanged
- **AND** it SHALL NOT be reported as Generic

#### Scenario: A note with no payload is Generic

- **GIVEN** a cipher whose `secureNote` payload is absent
- **WHEN** it is decoded
- **THEN** its subtype SHALL be Generic

### Requirement: The subtype SHALL survive export and import

An exported document SHALL carry the note's actual subtype, and importing it SHALL restore that
subtype.

#### Scenario: A passport note exports as a passport

- **GIVEN** a secure note of subtype Passport
- **WHEN** the vault is exported
- **THEN** the exported note's type SHALL be the Passport value

#### Scenario: Export and import round-trip an unknown subtype

- **GIVEN** a secure note whose subtype this build does not recognise
- **WHEN** the vault is exported and that document is imported
- **THEN** the subtype integer SHALL be unchanged

### Requirement: The subtype SHALL be visible and selectable

The subtype SHALL be selectable when editing a secure note and shown when viewing one. Generic SHALL
be the default and SHALL NOT be displayed as a row, because it is the absence of a subtype rather
than one.

#### Scenario: Choosing a subtype

- **GIVEN** the secure note edit form
- **WHEN** the subtype is set to Bank Account and saved
- **THEN** the stored item's subtype SHALL be Bank Account

#### Scenario: Generic is not announced

- **GIVEN** a secure note of subtype Generic
- **WHEN** its detail view is shown
- **THEN** no subtype row SHALL be displayed

### Requirement: A card field the brand list does not contain SHALL be preserved

The card brand SHALL be selectable from Bitwarden's list of brands. A brand that is not in the list
SHALL keep its existing value.

#### Scenario: An unfamiliar brand is not rewritten

- **GIVEN** a card whose brand is a value not in the brand list
- **WHEN** the item is opened and saved
- **THEN** the brand SHALL be unchanged

#### Scenario: A brand from the list is stored

- **GIVEN** the card edit form
- **WHEN** a brand is chosen from the list and saved
- **THEN** the stored card's brand SHALL be that brand

### Requirement: Expiry month and year SHALL be selectable

The expiry month and year SHALL be choosable from pickers rather than typed, and the values SHALL
remain the strings the wire format uses.

#### Scenario: Choosing an expiry

- **GIVEN** the card edit form
- **WHEN** a month and year are chosen and saved
- **THEN** the stored card SHALL carry those values

#### Scenario: An out-of-range expiry is preserved

- **GIVEN** a card whose expiry year is outside the range the picker offers
- **WHEN** the item is opened and saved
- **THEN** the year SHALL be unchanged
