## MODIFIED Requirements

### Requirement: Favourite indicator on item list rows

The item list rows SHALL display a filled star (`star.fill`) for a favourited item, at the row's
trailing edge. A row for an unfavourited item SHALL show nothing there — an empty star on every row
would make the mark meaningless.

**This resolves a contradiction the redesign walked into.** This requirement said the rows SHALL NOT
display a star; `vault-browser-ui`'s item-list scenario said each row shows "a favorite star if marked
as favorite". Both were in the canonical specs at the same time, and the code followed this one, so
`vault-browser-ui` described something the app did not do. The redesign draws the star because a list
row is the only place the favourite status is visible while scanning, and the sidebar's Favorites
category answers "what is favourited" only by replacing the list.

#### Scenario: Star on a favourited row
- **GIVEN** an item is marked favourite
- **WHEN** it appears in the item list
- **THEN** a filled star SHALL appear at the row's trailing edge

#### Scenario: Nothing on an unfavourited row
- **GIVEN** an item is not marked favourite
- **WHEN** it appears in the item list
- **THEN** no star SHALL appear

#### Scenario: Toggling updates the row
- **WHEN** the user toggles an item's favourite status from the detail toolbar or the row's context
  menu
- **THEN** the star SHALL appear or disappear without a re-sync
