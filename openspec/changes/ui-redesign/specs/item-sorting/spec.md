## MODIFIED Requirements

### Requirement: The item list can be sorted by name, last modified, or date created

The content pane SHALL provide a sort control listing these orders:

- Name (A–Z) — the default
- Name (Z–A)
- Last modified (newest first)
- Last modified (oldest first)
- Date created (newest first)
- Date created (oldest first)

The selected order SHALL apply to every sidebar selection and to search results, and SHALL persist
across launches.

Name comparisons SHALL be case-insensitive. When two items compare equal on the selected key the
list SHALL fall back to the case-insensitive name order, so the result is stable rather than
arbitrary.

The list SHALL be rendered as a single flat list under every sort order. It SHALL NOT be grouped under
letter headings: position within an ordered list already conveys the letter, the headings occupy
vertical space the item rows need, and a heading set at a legible weight competes with the names it is
meant to introduce.

#### Scenario: Name order is the default
- **GIVEN** no sort order has ever been chosen
- **WHEN** the item list renders
- **THEN** items SHALL be ordered by name, case-insensitively, ascending

#### Scenario: Descending name order
- **GIVEN** the sort order is Name (Z–A)
- **WHEN** the item list renders
- **THEN** items SHALL be ordered by name, case-insensitively, descending

#### Scenario: Sort by last modified
- **GIVEN** the sort order is Last modified (newest first)
- **WHEN** the item list renders
- **THEN** the most recently modified item SHALL be first

#### Scenario: Sort by date created
- **GIVEN** the sort order is Date created (oldest first)
- **WHEN** the item list renders
- **THEN** the earliest-created item SHALL be first

#### Scenario: Order applies within a search
- **GIVEN** a search query is active and the sort order is Last modified (newest first)
- **WHEN** the results render
- **THEN** they SHALL be ordered by last modified, newest first

#### Scenario: Equal keys fall back to name order
- **GIVEN** two items share the same revision date
- **WHEN** the list is sorted by last modified
- **THEN** they SHALL appear in case-insensitive name order relative to each other

#### Scenario: No letter headings under any sort order
- **GIVEN** any sort order is selected
- **WHEN** the item list renders
- **THEN** no letter headings SHALL be shown
- **AND** the list SHALL be a single flat list

#### Scenario: Order persists
- **WHEN** the user selects a sort order and relaunches the application
- **THEN** the selected order SHALL still be in effect
