## ADDED Requirements

### Requirement: A collection's membership SHALL survive a rename

The members and groups associated with a collection SHALL be read from the server, carried while the
collection is edited, and sent back with any rename, so that renaming a collection does not change who
can reach it.

#### Scenario: Renaming keeps the groups

- **GIVEN** a collection that one or more groups can access
- **WHEN** the collection is renamed
- **THEN** the request SHALL carry those groups
- **AND** the collection SHALL still be reachable by them afterwards

#### Scenario: Renaming keeps the members

- **GIVEN** a collection that one or more users can access
- **WHEN** the collection is renamed
- **THEN** the request SHALL carry those users

#### Scenario: An unknown permission field survives

- **GIVEN** a collection whose group entries carry a permission field this build does not model
- **WHEN** the collection is renamed
- **THEN** that field SHALL be sent back unchanged

#### Scenario: The external id survives

- **GIVEN** a collection carrying an `externalId`
- **WHEN** the collection is renamed
- **THEN** the same `externalId` SHALL be sent

#### Scenario: The local view agrees with what was sent

- **GIVEN** a collection with membership
- **WHEN** it is renamed
- **THEN** the collection held locally SHALL still carry that membership

### Requirement: Creating a collection SHALL start it with no membership

A newly created collection SHALL be created without members or groups, because there are none to
preserve.

#### Scenario: A new collection has no members

- **GIVEN** the create-collection flow
- **WHEN** a collection is created
- **THEN** the request SHALL carry empty member and group lists
