## MODIFIED Requirements

### Requirement: DetailSectionCard header style (MODIFIED)

Section headers ("Credentials", "Websites", etc.) SHALL use `Typography.sectionLabel` — a 10pt semibold
face — rendered uppercase and in the secondary text colour. The header SHALL carry the `isHeader`
accessibility trait. Spacing between the header and the card content SHALL be 5pt.

An uppercase secondary label reads as a category; a semibold primary label at body size reads as
content, which is why the previous style competed with the field values beneath it.

#### Scenario: Section header renders as an uppercase label
- **WHEN** a `DetailSectionCard` is displayed with a non-empty title
- **THEN** the title SHALL render uppercase in `Typography.sectionLabel` with the secondary text colour
- **AND** it SHALL carry the `isHeader` accessibility trait

#### Scenario: A blank title still renders no header
- **WHEN** a `DetailSectionCard` is created with a nil or whitespace-only title
- **THEN** no header SHALL be rendered

---

### Requirement: FieldRowView uses horizontal layout for all field types (MODIFIED)

The system SHALL display field rows with the label on the left and the value on the right. The label
SHALL render in `Typography.detailFieldLabel` in the secondary text colour, occupying a fixed-width
column so that labels and values line up down the card. Multi-line fields (notes) SHALL use a stacked
layout. Masked fields SHALL display the label on the left with the masked value and eye toggle on the
right.

Field values SHALL render in `Typography.detailFieldValue` in a proportional face, except for values
that are transcribed character by character — masked values, card numbers, security codes, SSH private
keys and SSH fingerprints — which SHALL be monospaced.

#### Scenario: Single-line field renders horizontally
- **WHEN** a `FieldRowView` is displayed with `isMultiLine` false (default) and `isMasked` false
- **THEN** the label SHALL appear on the left in the secondary colour and the value on the right, on the same line

#### Scenario: Labels align across rows
- **WHEN** two or more field rows are stacked in one card
- **THEN** their labels SHALL occupy the same width, so every value starts at the same x position

#### Scenario: Multi-line field renders stacked
- **WHEN** a `FieldRowView` is displayed with `isMultiLine` true
- **THEN** the label SHALL appear above the value in a vertical stack

#### Scenario: Masked field renders horizontally
- **WHEN** a `FieldRowView` is displayed with `isMasked` true
- **THEN** the label SHALL appear on the left, and the masked value with eye toggle SHALL appear on the right

#### Scenario: Only transcribed values are monospaced
- **WHEN** a password field and a username field are displayed in the same card
- **THEN** the password SHALL be monospaced and the username SHALL be proportional

---

### Requirement: Copy affordance on every field row (MODIFIED)

Each field row that holds a copyable value SHALL show a copy icon (`doc.on.doc`) at its trailing edge
at all times, not only while the pointer is over the row. Clicking anywhere on the row SHALL copy the
field value. After a copy the icon SHALL be replaced by a "COPIED" confirmation for 0.8 seconds, then
revert. The icon SHALL take the accent colour while the row is hovered and the secondary colour
otherwise.

A masked row SHALL NOT show the copy icon, because the reveal eye already occupies the trailing slot
and the detail header's Copy password button is the discoverable way to copy that value.

This replaces the previous rule that a "COPY" label appear to the left of the value only while the row
is hovered. On a Mac that meant the way to copy a password was invisible until you already knew it
existed, and it displaced the value as it appeared. The open-in-browser icon has always been visible,
for exactly this reason; this makes the two consistent.

#### Scenario: Copy icon visible without hovering
- **WHEN** a field row with a non-empty value is displayed and the pointer is nowhere near it
- **THEN** the copy icon SHALL be visible at the row's trailing edge

#### Scenario: Click row copies value
- **WHEN** the user clicks anywhere on a field row
- **THEN** the field value SHALL be copied to the clipboard

#### Scenario: COPIED feedback after copy
- **GIVEN** the user has copied a field value
- **THEN** the icon SHALL be replaced by a "COPIED" confirmation for 0.8 seconds, then revert

#### Scenario: Masked row shows the eye, not a second control
- **WHEN** a masked field row is displayed
- **THEN** the reveal toggle SHALL occupy the trailing edge and no copy icon SHALL be drawn beside it

---

### Requirement: Metadata footer displays created and updated dates (MODIFIED)

The system SHALL display a single metadata line below the last card section, left-aligned, in the
secondary text colour, using `Typography.metaLine`. The line SHALL report the last-modified date and
the creation date, separated by a middle dot.

The creation date SHALL always be an absolute date ("Created Mar 12, 2024"). The last-modified date
SHALL be an age while it is within 30 days of now ("Updated 4 days ago") and an absolute date beyond
that.

**Why the modified date switches form and the created date does not.** The modified date is the one the
user is judging — is this credential stale? — and while the answer is small, an age beats a date the
reader has to subtract from today. Past about a month the relative formatter starts producing
"last month" and "1 year ago", which are *vaguer* than the dates they replace, on the one value whose
purpose is precision about age. The creation date is a fact about the item rather than a judgement, so
it never needs the convenience.

#### Scenario: Dates render below cards
- **WHEN** an item detail is displayed
- **THEN** one line SHALL appear below the last card, left-aligned, in the secondary colour
- **AND** it SHALL contain both the last-modified date and the creation date

#### Scenario: A recently revised item reports its age
- **GIVEN** an item was last revised four days ago
- **WHEN** the detail pane renders
- **THEN** the modification SHALL be given as an age rather than a date

#### Scenario: An old revision reports a date
- **GIVEN** an item was last revised two years ago
- **WHEN** the detail pane renders
- **THEN** the modification SHALL be given as an absolute date
- **AND** it SHALL NOT say "2 years ago", which is less precise than the date it would replace

#### Scenario: The boundary is 30 days inclusive
- **GIVEN** an item was last revised exactly 30 days ago
- **WHEN** the detail pane renders
- **THEN** the modification SHALL still be an age
- **AND** at 31 days it SHALL be an absolute date

#### Scenario: A future revision is not read as the future
- **GIVEN** an item whose revision date is three days ahead of this machine's clock
- **WHEN** the detail pane renders
- **THEN** the modification SHALL be shown as an absolute date
- **AND** the line SHALL NOT claim anything will happen in the future

#### Scenario: The creation date is always absolute
- **GIVEN** an item created yesterday
- **WHEN** the detail pane renders
- **THEN** the creation date SHALL be an absolute date, not "yesterday"

---

### Requirement: Sections whose content loads on demand name themselves in the card header

The password-history and passkey sections render a card whose contents are decrypted only when the
reader expands it. Each SHALL carry its name in the section label above the card, like every other
card in the pane, and the collapsed row inside SHALL carry the one fact the header cannot: how many
entries there are, or the action that would reveal them.

The collapsed row SHALL NOT repeat the section name. It SHALL NOT claim to be loading while it is
closed and nothing has been requested.

**Why this is a requirement and not a style note.** Both sections used to render as a card with no
header, with their title inside it in `.headline`. Beside Credentials and Websites — each of which has
an uppercase label above its card — that made them read as a rendering glitch rather than as a section
deliberately waiting to be opened.

#### Scenario: The section is labelled like its neighbours
- **WHEN** either on-demand section is displayed
- **THEN** an uppercase section label SHALL appear above its card, naming it

#### Scenario: The collapsed row does not repeat the name
- **WHEN** the card header says "Passkeys"
- **THEN** the row inside SHALL NOT also say "Passkeys"

#### Scenario: A closed section offers, it does not report
- **GIVEN** a section that has never been opened, so its count is unknown
- **WHEN** it is displayed collapsed
- **THEN** the row SHALL read as an offer to expand
- **AND** it SHALL NOT claim to be loading, because nothing has been requested

#### Scenario: An opened section reports its count
- **GIVEN** a section that has been loaded and found to hold two entries
- **WHEN** it is displayed, collapsed or expanded
- **THEN** the row SHALL state the count

---

## ADDED Requirements

### Requirement: The detail pane presents an item header

The detail pane SHALL render a header above the first section card containing a type-tinted icon chip,
the item's name, and a breadcrumb line. The breadcrumb SHALL list the fields that place the item —
the login username where there is one, the folder name where the item is foldered, and the
organisation name where the item belongs to one — separated by middle dots, and SHALL read "Personal
vault" when there is nothing to list. The item's own commands — the favourite toggle and Edit — sit at
the header's trailing edge; see `item-actions-in-detail-header`, which moved them there out of the
window toolbar.

#### Scenario: Header shows type, name and placement
- **WHEN** a login item in a folder belonging to an organisation is selected
- **THEN** the header SHALL show a login-tinted icon, the item's name, and a breadcrumb naming the username, the folder and the organisation

#### Scenario: Header falls back when there is nothing to place the item
- **WHEN** a personal, unfoldered item with no username is selected
- **THEN** the breadcrumb SHALL read "Personal vault"

#### Scenario: Favourite state is visible in the header
- **GIVEN** the selected item is marked favourite
- **WHEN** the header renders
- **THEN** the favourite control SHALL show a filled star at the trailing edge, and SHALL NOT be duplicated by a separate display-only star

---

### Requirement: The detail pane presents an action row

The detail pane SHALL render an action row between the header and the first section card. The row SHALL
offer only the actions the selected item can supply:

- **Copy password** — for items with a password
- **Copy code** — for login items whose stored authenticator key yields a code
- **Open website** — for items with at least one URI

Each action SHALL take the path that already exists for the same value elsewhere in the app. Copy
password SHALL go through the master-password re-prompt gate when the item is protected by it. Copy
code SHALL place the **derived code**, never the stored authenticator key, on the clipboard. Open
website SHALL open the item's first URI in the default browser.

An action the item cannot supply SHALL NOT be rendered, and the row SHALL NOT render at all when no
action applies.

#### Scenario: Actions match the item type
- **WHEN** a secure note is selected
- **THEN** no copy-password, copy-code or open-website action SHALL be offered

#### Scenario: Re-prompt-protected item gates the header action
- **GIVEN** the selected login is re-prompt protected and no grant has been given this session
- **WHEN** the user presses Copy password in the header
- **THEN** the master-password prompt SHALL be shown
- **AND** the password SHALL NOT be placed on the clipboard until it is answered

#### Scenario: Copy code never copies the stored key
- **GIVEN** a login with a stored authenticator key
- **WHEN** the user presses Copy code in the header
- **THEN** the clipboard SHALL hold the current one-time code
- **AND** it SHALL NOT hold the stored key
