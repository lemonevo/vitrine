## ADDED Requirements

### Requirement: Text that carries information SHALL meet 4.5:1 in both appearances

The existing requirements in this capability cover background tints and border strokes at 3:1. Text is a
different case: the resolved system label colours do not clear the WCAG AA threshold for small text in
both appearances, and the interface uses them for copy a user has to act on.

Measured on this Mac against the resolved sRGB values of the window and control backgrounds, in light
and dark aqua: `secondaryLabelColor` is 3.95:1 in light (5.89:1 in dark), and `tertiaryLabelColor` is
1.88:1 in light (2.26:1 in dark). Both were used for field hints, field labels, the entry-screen
subtitles, and the sentence under the login card that states the master password never leaves the
machine.

Any foreground used for text at or below 13 pt SHALL therefore meet 4.5:1 against the surface it is
drawn on **in each appearance**, and SHALL be reached through a `Foreground` token rather than
`.secondary` / `.tertiary` at a call site.

#### Scenario: An actionable word clears the threshold too

- **GIVEN** text whose whole purpose is to be clicked — a link, a switch, an inline command
- **WHEN** it is drawn at 13 pt or smaller
- **THEN** it SHALL meet 4.5:1 in both appearances
- **AND** `Color.accentColor` SHALL NOT be assumed to: `controlAccentColor` measures 4.02:1 in light
      and 4.15:1 in dark, and `systemBlue` 3.52:1 / 5.16:1
- **AND** `Foreground.action` (`linkColor`, 5.26:1 / 5.89:1) is the token for this role

#### Scenario: Muted text clears AA in both appearances

- **GIVEN** copy that is secondary in weight but not optional in content
- **WHEN** it is drawn with `Foreground.muted`
- **THEN** it SHALL measure at least 4.5:1 in light aqua
- **AND** at least 4.5:1 in dark aqua

#### Scenario: A warning colour is checked in the appearance it was not chosen for

- **GIVEN** a state colour picked to clear AA on a light surface
- **WHEN** it is used in dark aqua
- **THEN** it SHALL resolve to a value that clears AA there too
- **AND** it SHALL NOT be a single constant colour literal, because no amber does both
      (`#8C4700` measures 6.97:1 light / 2.39:1 dark; `#E9A23B` measures 2.17:1 / 7.69:1)

#### Scenario: Colour is never the only carrier

- **WHEN** a message is drawn in the warning foreground
- **THEN** the same information SHALL be present as text and as a glyph
- **AND** removing the colour SHALL NOT remove the meaning
