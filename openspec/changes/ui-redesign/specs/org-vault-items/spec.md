## MODIFIED Requirements

### Requirement: Org items appear in All Items and in their collection sidebar selection

Org items SHALL be included in the "All Items" sidebar selection alongside personal items. Org items
SHALL appear when the user selects `.collection(id)` where `id` is in the item's `collectionIds`. Org
items SHALL be excluded from folder selections (personal folders are not org collections). Org items
SHALL appear in type-based sidebar selections (Login, Card, etc.) regardless of org membership.

The item's organization name SHALL be displayed read-only in the detail pane's header breadcrumb,
which is where the item's placement is stated. It previously had a card of its own at the bottom of
the scroll; with the header present that card repeated what the breadcrumb already said, and sat below
every field — the one place a user checks to confirm they are looking at the right account, parked out
of sight.

#### Scenario: Org items visible in All Items
- **GIVEN** the user has 3 personal items and 2 org items
- **WHEN** the user selects All Items
- **THEN** all 5 items SHALL appear in the item list

#### Scenario: Org items filterable by collection
- **GIVEN** item X has `collectionIds = ["col1"]`
- **WHEN** the user selects `.collection("col1")` in the sidebar
- **THEN** item X SHALL appear in the item list

#### Scenario: Org items excluded from folder selections
- **GIVEN** an org item exists with `organizationId = "org1"`
- **WHEN** the user selects a personal folder in the sidebar
- **THEN** the org item SHALL NOT appear in the item list

#### Scenario: Org item detail pane names its organization
- **GIVEN** the user selects an org item in the item list
- **WHEN** the detail pane renders
- **THEN** the item's organization name SHALL appear, read-only, in the header breadcrumb
- **AND** no separate organization card SHALL be rendered below the field cards

#### Scenario: Organization name resolves from the in-memory list
- **GIVEN** an item has `organizationId` matching organization "Acme Inc"
- **WHEN** the detail pane renders
- **THEN** the breadcrumb SHALL display "Acme Inc", not the raw identifier
