# Main window, P3 pass — Proposal

## Why

The third design pass for the browser window was drawn and reviewed as a mock
(`Prizm/PrizmTests/Presentation/Design/P3MainWindow.swift`), which the user accepted with "我想要这样的".
The mock stays in the tree until cut ③ lands — it is the reference being implemented — and is deleted by
`tasks.md` §5. Its seven sections are all about the same failure: the panes carry a second tier of
information — subtitles, counts, section captions, breadcrumbs, type glyphs — and that tier is drawn
with colours that either cannot be read comfortably or compete for a role they do not have.

Implementing it surfaced two defects that the mock itself was right about and the code was not.

**`Foreground.muted` did not clear the floor it was chosen for.** It shipped as
`Color.primary.opacity(0.62)` with "6.20:1 in light" written beside it, in the token table and in the
source comment. Measured again, properly: **4.31:1 on the light card, 4.35:1 on light white.** The
original arithmetic multiplied the token's alpha against the surface and stopped there — but
`labelColor` is itself 84.7% opaque, so `0.62 × 0.847 = 52.7%` is what actually reaches the eye. The
rule the token exists to satisfy is 4.5:1 for text at 13pt and below. The alpha is now 0.68, which
measures 5.18:1 on the light card and 5.24:1 on light grey, and `ContrastTokenTests` asserts both the
new value and the failure of the old one.

**Four of the five type colours were below the non-text floor.** `ItemType.tint` used the system
colours, drawn on a chip of themselves at `Opacity.typeChip` (0.16). Against that fill in light aqua:
teal 1.89:1, green 1.95:1, orange 2.02:1, blue 2.90:1 — the WCAG 1.4.11 floor is 3:1, and the chip is
not an edge case, it is where the glyph always sits. Purple alone passed, at 3.33:1. The palette is now
per-appearance and hand-picked rather than derived (desaturating the system purple lands on grey, and
grey beside the grey folder glyphs is the outcome the change exists to avoid); its worst case measures
3.86:1.

## What the mock got wrong

The favourite star. Both the app and the accepted mock draw it `Color.yellow`, which measures **1.51:1 on
white and 1.28:1 on the light window** — under half the 3:1 floor, on the glyph whose only job is to be
spotted. A picture reviewed on a retina display shows a pale star as a pale star; nothing in a still
image reports a ratio, and the mock was reviewed as a still image. `Foreground.favorite` is a bronze in
light (5.49:1) and the bright gold in dark (9.97:1), and `test_systemYellowWouldFailTheSameMeasurement`
records the number the review could not have made.

## What changes

Cut ① — colour and contrast, no layout:

- `Foreground.muted` 0.62 → 0.68, with `mutedAlpha` exposed so the test measures the same number the
  renderer composites.
- `ItemType.tint` replaced by the measured per-appearance palette (`tintComponents`), same one
  definition, all eight consumers unchanged.
- `Foreground.success` added for the sync dot, which was `Color.green` at 2.22:1 in light, and
  `Foreground.favorite` for the star, which was `Color.yellow` at 1.28–1.51:1 (see above) in the list
  row, the detail header's toggle and the sidebar's "Favourites" icon.
- `FaviconView`'s fallback glyph defaulted to `.secondary`; it is content, not a placeholder, so the
  default is `Foreground.muted`.
- `.secondary` and `.tertiary` removed from every foreground in the main window's views — sidebar,
  list, detail, trash, and the card/field components they compose — 40 call sites, in favour of
  `Foreground.muted` / `Foreground.action`. The "COPIED" confirmation was accent-coloured text at 10pt
  (4.02:1); it is `Foreground.action` now.
- `ContrastTokenTests`: the compositing done in a test, against the surfaces the panes actually paint.

Cuts ② and ③ are listed in `tasks.md` and land in this change.

## What the measurement says about the harness

`NSColor.windowBackgroundColor` resolves to **pure white** when read outside a drawing context, in
light aqua. Any contrast test that uses it as the background flatters dark text and will pass values
the interface fails, so the tests measure against explicit surfaces — the card asset's two appearances,
`textBackgroundColor`, and a grey window. This is recorded because it is the second way this particular
number went wrong.

## Deliberate limits

- **Sheets and edit forms keep `.secondary` for now.** Import/export/health/attachment/verification
  sheets and the edit forms are separate screens with their own surfaces; the P3 pass is about the main
  window. They carry the same 3.95:1 defect and are listed as remaining work rather than swept silently
  into a UI change.
- **`Color.secondary.opacity(...)` fills stay.** The trash banner's background and the TOTP countdown
  ring's track are non-text fills at a different floor, not foregrounds.
- **The prominent action button's white-on-accent label is not fixed here.** It measures about 3.5:1 in
  light, which fails AA for its 12pt text; the fix belongs to the button styles in cut ③, where the
  fill can be chosen and measured together with the label rather than patched from here.
- **Increase Contrast does not change `muted`.** The token clears AA at standard contrast with margin;
  the `Opacity` functions exist for tints whose *whole job* is to be faint.

## Impact

- 1 new test file, 6 tests. No new strings, no new files in the app target (`DesignSystem.swift` and
  `ContrastAwareOpacity.swift` already exist and are registered).
- Visual: every secondary label in the window is slightly darker, and the type glyphs change hue.
  Screenshots re-rendered for both appearances; the auth screens move with the token because they use
  it.
- `CLAUDE.md`'s foreground table corrected, including the method that failed.
