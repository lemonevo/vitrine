## ADDED Requirements

### Requirement: Search matches notes, custom fields, and folder names

In addition to the fields already searched, a search query SHALL be matched case-insensitively
against:

- the item's **notes**, for every item type
- the **name and value of every custom field**, for every item type
- the **name of the folder** the item is assigned to

Matching remains a case-insensitive substring test, and remains scoped to the active sidebar
selection.

The added fields SHALL only ever add results. Every query that matched an item before this change
SHALL still match it.

Custom field values of every type SHALL be searchable, including hidden fields — the search runs
locally over already-decrypted values and revealing a match does not display the value.

#### Scenario: Notes are searched
- **GIVEN** an item whose notes contain "renewal code"
- **WHEN** the user searches for "renewal"
- **THEN** the item SHALL appear in the results

#### Scenario: Custom field names are searched
- **GIVEN** an item with a custom field named "PIN"
- **WHEN** the user searches for "pin"
- **THEN** the item SHALL appear in the results

#### Scenario: Custom field values are searched
- **GIVEN** an item with a custom field whose value is "ACME Bank"
- **WHEN** the user searches for "acme"
- **THEN** the item SHALL appear in the results

#### Scenario: Hidden custom field values are searched
- **GIVEN** an item with a hidden custom field whose value is "correct horse"
- **WHEN** the user searches for "horse"
- **THEN** the item SHALL appear in the results
- **AND** the field's value SHALL NOT be displayed in the list

#### Scenario: Folder names are searched
- **GIVEN** an item assigned to a folder named "Contracts"
- **WHEN** the user searches for "contracts"
- **THEN** the item SHALL appear in the results

#### Scenario: Existing matching behaviour is unchanged
- **GIVEN** an item matched by its name, username, URI, cardholder name, email or company
- **WHEN** the same query is searched
- **THEN** the item SHALL still appear in the results

#### Scenario: Search remains scoped to the selection
- **GIVEN** the sidebar selection is a specific folder
- **WHEN** the user searches for a term present only on an item outside that folder
- **THEN** that item SHALL NOT appear in the results
