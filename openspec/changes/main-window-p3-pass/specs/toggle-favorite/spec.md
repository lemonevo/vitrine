## ADDED Requirements

### Requirement: A favourited item is marked in its row, in a column that always exists

This resolves a contradiction the specs have carried since the P3 pass began: `toggle-favorite` records
"Remove star indicator from item list rows (REMOVED)" — rows SHALL NOT show the star — while
`vault-browser-ui` describes the row as showing "a favorite star if marked as favorite", and the code has
shown it the whole time (`FR-022`). The accepted design keeps the star, so it stays, and the REMOVED
record above no longer describes this application.

Its reasoning was also wrong in a way worth writing down: "the item's presence in the Favorites sidebar
category indicates it" describes a different screen. A user reading *All Items* — the default view, and
the one they are in when scanning for an account — cannot see which of its rows are favourited without
navigating away from the list they are reading.

The star SHALL occupy a fixed trailing column that is reserved whether or not the item is favourited.
A conditional glyph makes the row it appears on narrower than its neighbours, so the name that needed
reading most is the one given least room, and the column edges do not line up down the list.

The colour SHALL be `Foreground.favorite`, not `Color.yellow`: system yellow measures 1.28:1 on the light
window and 1.51:1 on white, under half the 3:1 floor for non-text content, on a glyph whose entire purpose
is to be noticed at a glance.

#### Scenario: The column exists on every row

- **WHEN** the item list renders a row whose item is not favourited
- **THEN** the trailing 20pt column SHALL still be reserved
- **AND** the name and subtitle SHALL run to the same width as on a favourited row

#### Scenario: The mark is reachable without changing view

- **WHEN** a user is reading the "All Items" list
- **THEN** they SHALL be able to tell which items are favourited from the rows themselves
- **AND** the detail view's toggle SHALL keep working as the way to change it
