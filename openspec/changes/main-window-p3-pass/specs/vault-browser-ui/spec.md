## ADDED Requirements

### Requirement: The item list marks its own rows

The middle column is the one place in the browser where the app draws the selection rather than leaving
it to `List`. `List(selection:)` SHALL still own the selection itself — the binding, keyboard arrow
navigation, extension clicks and VoiceOver row traits all depend on AppKit's list, and none of that is
reimplemented here.

What the app draws is the marking: a rounded fill inset from the pane edge at
`Opacity.selectionFill(_:)`, and a 3pt full-opacity accent bar at the row's leading edge. The fill is
faint on purpose; the bar is the mark that carries the state, and it is the thing AppKit cannot be asked
for.

The separator between rows is drawn by the app for a different reason: `ui-redesign`'s contrast
requirement is that the hairline between item rows respond to Increase Contrast, and a native `List`
separator does not. It SHALL be inset to the text column, so it reads as a break between items rather
than a line through them, and the last row SHALL NOT draw one beneath itself.

#### Scenario: A selected row is marked twice and owned by AppKit once

- **WHEN** a row is selected
- **THEN** it SHALL show the inset accent fill and the leading bar
- **AND** arrow keys, ⌘-click and the row's VoiceOver selection trait SHALL keep working, because the
      selection still comes from `List(selection:)`

#### Scenario: The fill is never a literal

- **WHEN** either mark is drawn
- **THEN** its opacity SHALL come from an `Opacity` function of `ColorSchemeContrast`
- **AND** the bar SHALL be full opacity, so it survives a fill the user cannot see

#### Scenario: The row's height is the row's own

- **WHEN** an item row is laid out
- **THEN** it SHALL be a fixed 40pt with a 26pt type chip, so the chip, the name and the subtitle sit at
      the same y in every row rather than wherever the previous row's text ended
