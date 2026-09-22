## MODIFIED Requirements

### Requirement: Background tint colours SHALL meet WCAG non-text contrast ratio

All custom `Color.opacity()` values used as background tints on banners, borders, and interactive
indicators SHALL produce a minimum 3:1 contrast ratio against the adjacent background in both light and
dark mode.

The tints introduced by the vault redesign — the item-type chip, the selected item-list row, and the
hairline between item rows — SHALL be `Opacity` functions of `ColorSchemeContrast` like every other
tint. A literal opacity in a view SHALL NOT be used, because a literal cannot respond to the Increase
Contrast preference, which this capability separately requires.

#### Scenario: Sync error banner background meets contrast
- **WHEN** a sync error banner is displayed
- **THEN** the yellow background tint SHALL have a minimum 3:1 contrast ratio against the content column background

#### Scenario: Card border meets contrast
- **WHEN** a detail section card is displayed
- **THEN** the border stroke SHALL be visible with a minimum 3:1 contrast ratio against the card and window backgrounds

#### Scenario: Trash banner background meets contrast
- **WHEN** a trashed item is selected and the trash banner is displayed
- **THEN** the secondary background tint SHALL have a minimum 3:1 contrast ratio against the detail pane background

#### Scenario: Error banner backgrounds meet contrast
- **WHEN** an error banner is displayed in the edit form or attachment confirm sheet
- **THEN** the red background tint SHALL have a minimum 3:1 contrast ratio against the surrounding background

#### Scenario: The element that carries the type meets contrast
- **WHEN** an item row is displayed, selected and unselected
- **THEN** the colour that identifies the type SHALL be the full-opacity symbol inside the chip rather
  than the chip's fill, and that symbol SHALL meet the 3:1 non-text ratio against the chip
- **AND** the accent bar marking a selected row SHALL be full opacity

The chip fill is a pale tint and does not clear 3:1 against the list background. It carries no
information on its own — the glyph inside it does — so it is treated as decorative, as the existing
banner tints are. A requirement written against the fill would be false, or would force a saturated
block behind every row.

#### Scenario: Hairline between rows is distinguishable
- **WHEN** the item list is displayed
- **THEN** the hairline separating rows SHALL be visible in both appearances and stronger under
  Increase Contrast

---

### Requirement: Increase Contrast preference SHALL raise opacity values

When the macOS "Increase contrast" accessibility setting is enabled, all custom background tint opacity
values SHALL be increased to provide stronger visual distinction.

#### Scenario: Increase Contrast raises banner opacity
- **GIVEN** the user has enabled "Increase contrast" in System Settings → Accessibility → Display
- **WHEN** a sync error banner is displayed
- **THEN** the background tint opacity SHALL be higher than the default value

#### Scenario: Increase Contrast raises card border opacity
- **GIVEN** the user has enabled "Increase contrast"
- **WHEN** a detail section card is displayed
- **THEN** the border stroke opacity SHALL be higher than the default value

#### Scenario: Increase Contrast raises the type chip opacity
- **GIVEN** the user has enabled "Increase contrast"
- **WHEN** an item row is displayed
- **THEN** the type chip tint opacity SHALL be higher than the default value
