## ADDED Requirements

### Requirement: The detail pane is a column, not a stretch

The pane's content SHALL be capped at `Spacing.detailContentWidth` (480pt) and centred in whatever width
the window gives it. Past that point extra width SHALL become margin rather than distance between a
field's label and the value that belongs to it.

The reason is a relationship that does not survive stretching: a label and its value are read as a pair,
and the pair is the only thing that says so. At full-pane width the distance between them grows without
the relationship growing with it, and the pane reads as two columns of unrelated text.

#### Scenario: A wide window does not widen the reading line

- **WHEN** the detail pane is given more than 480pt
- **THEN** its content SHALL stay 480pt and centre
- **AND** the gap between a label and its value SHALL NOT grow with the window

---

### Requirement: A card's columns are fixed, across every card in the pane

Every card row SHALL share two columns: a label column of `Spacing.detailLabelWidth` (100pt) at the
leading edge, and a trailing action slot of `Spacing.detailActionSlotWidth` (56pt) at the other. A row
SHALL be at least `Spacing.detailRowMinHeight` (42pt) tall and SHALL grow beyond it when a value wraps.

The slot belongs to the row that owns the affordance, which includes the masked row's reveal eye: an eye
placed after the dots rather than in the slot sits at a different x from every copy glyph in the pane,
and the pane is read by scanning that column.

#### Scenario: The affordances of three cards land on one line

- **WHEN** a pane shows a credentials card, a websites card and a notes card
- **THEN** their copy glyphs and reveal eyes SHALL share one trailing x
- **AND** their values SHALL share one leading x

#### Scenario: A wrapped value grows the row, not the layout

- **GIVEN** a note body longer than one line
- **WHEN** the row renders
- **THEN** the row SHALL exceed the minimum height
- **AND** the trailing slot SHALL stay where it is

---

### Requirement: The detail header's controls share a height and differ by role

The header's controls SHALL all be `Spacing.controlHeight` (26pt) tall with `Typography.controlGlyph`
glyphs, and SHALL take exactly one of three forms: one filled action, bordered actions, and icon-only
glyphs. The filled form is the item's single most likely next action; more than one filled control in the
row means the row points at nothing.

The filled control's label is white, so its fill SHALL be chosen against that label rather than
inherited from the user's accent: `controlAccentColor` measures 4.02:1 under a white label in both
appearances and `linkColor` measures 2.83:1 in dark, both under the 4.5:1 floor for 12pt text. The
accepted fill measures 6.37:1 light and 4.81:1 dark, and is deliberately accent-independent — a fill that
followed the accent would become unreadable the day a user set their accent to yellow or graphite.

A copy action SHALL confirm: the control that sent the value to the clipboard shows the confirmation, as
the row it mirrors already does.

#### Scenario: Three controls, one line, one height

- **WHEN** a login item's header renders its copy, code, website and edit controls
- **THEN** all of them SHALL be 26pt tall
- **AND** exactly one SHALL be filled

#### Scenario: The fill survives the user's accent setting

- **GIVEN** a System Settings accent of yellow
- **WHEN** the filled action renders
- **THEN** its white label SHALL still clear 4.5:1

#### Scenario: A copy says it happened

- **WHEN** the user presses a header copy control and the value is delivered
- **THEN** that control SHALL show a confirmation for 0.8s
- **AND** the confirmation SHALL name the action, not merely change colour

---

## Deliberate deviation from the design pass

The pass drew cards on a white (light) / `#212121` (dark) fill. This requirement set does **not** adopt
it, and the existing `#FAFAFA` / `#2C2C2C` asset stays: in light aqua the pane's own background resolves
to white, so a white card would be separated from its window by nothing but the hairline, and in dark the
proposed fill is *closer* to the window than the current one, not further. The asset was measured against
its surfaces; the mock's value was picked to look right in a picture.
