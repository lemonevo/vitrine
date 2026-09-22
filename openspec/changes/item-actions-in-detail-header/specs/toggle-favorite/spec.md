## MODIFIED Requirements

### Requirement: User can toggle favorite from the detail view
The detail pane's item header SHALL display a star toggle button at its trailing edge, beside the
item's name. It is the favourite control: there SHALL NOT be a second, display-only star elsewhere in
the header, because a state shown twice with only one of them clickable reads as a broken button.

When the item is not favorited, the button SHALL show an empty star (`star`) in the secondary colour.
When favorited, it SHALL show a filled star (`star.fill`). Tapping the button SHALL toggle the favorite
status, update the server, and refresh the item list and sidebar counts immediately. The button SHALL
carry the accessibility identifier `detail.favorite`.

#### Scenario: Favorite an unfavorited item from detail view
- **GIVEN** an unfavorited item is selected
- **WHEN** the user clicks the star button in the item header
- **THEN** the item SHALL be marked as favorite, the star SHALL become filled, the item SHALL appear in the Favorites sidebar, and the Favorites count SHALL increment

#### Scenario: Unfavorite a favorited item from detail view
- **GIVEN** a favorited item is selected
- **WHEN** the user clicks the filled star button in the item header
- **THEN** the item SHALL be unfavorited, the star SHALL become empty, and the Favorites count SHALL decrement

#### Scenario: Star button disabled for trashed items
- **GIVEN** a trashed item is selected
- **THEN** the star toggle button SHALL NOT be shown
