## ADDED Requirements

### Requirement: A contrast figure recorded beside a token SHALL be reproducible by a test

Design tokens carry a measured ratio in their doc comment and in `CLAUDE.md`. Those numbers are
assertions about rendering, and an assertion nobody can re-run is worth nothing the day the compositing
changes.

Any token whose stated purpose is to clear a WCAG floor SHALL have a test that recomputes the ratio from
the same values the renderer uses, and SHALL fail if the token's value changes without the measurement.
The test SHALL name the floor it enforces in its failure message, so a regression reads as "4.31 is under
4.5", not as a bare number.

#### Scenario: The alpha of a translucent system colour is part of the measurement

- **GIVEN** a foreground expressed as `Color.primary.opacity(a)`
- **WHEN** its contrast is measured
- **THEN** `labelColor`'s own alpha (84.7% on this platform) SHALL be multiplied with `a` before the ratio is taken
- **AND** a measurement that skips it SHALL NOT be considered: it reported 6.20:1 for a token that renders at 4.31:1

#### Scenario: A surface resolved outside a drawing context is not evidence

- **GIVEN** a test that needs the colour a pane is painted with
- **WHEN** it asks a dynamic system colour such as `windowBackgroundColor` for its components
- **THEN** it SHALL NOT use the answer as the background: in light aqua that resolves to pure white, which flatters dark text and lets failing values pass
- **AND** the surfaces SHALL be stated explicitly — the card asset's two appearances, `textBackgroundColor`, and a grey window

#### Scenario: A rejected value stays rejected

- **GIVEN** a token value that was replaced because it missed its floor
- **WHEN** the suite runs
- **THEN** a test SHALL assert that the old value still fails the same measurement, so it cannot be reinstated as a rounding preference

---

### Requirement: Type colours SHALL clear 3:1 on the chip fill they are always drawn over

`ItemType.tint` appears bare in the sidebar and on a `Color`-of-itself fill at `Opacity.typeChip` in the
item list and the detail header. The chip is not an edge case — it is where the glyph normally sits — and
it lightens the surface behind the glyph, so it is the measurement that decides whether a colour is usable.

A type colour SHALL clear 3:1 (WCAG 1.4.11, non-text) against its own chip fill in **both** appearances,
and SHALL be resolved per appearance rather than picked as one constant. Desaturating a system colour is
not an acceptable way to satisfy this: the result is grey, and grey beside the folder glyphs destroys the
distinction the colour exists to make.

#### Scenario: The system colours are the counterexample

- **GIVEN** the five system colours this app used for item types
- **WHEN** each is measured against its own 0.16 chip over a light surface
- **THEN** four of them SHALL be found below 3:1 — teal 1.89, green 1.95, orange 2.02, blue 2.90
- **AND** that SHALL be why they are not used

#### Scenario: Saturation is left to the accent

- **GIVEN** a window where selection is marked by the accent colour
- **WHEN** the type glyphs are drawn in high-saturation hues beside it
- **THEN** the type palette SHALL be the low-saturation set, so hue means "what kind" and accent means "which one"
