# Vault UI redesign — Design

## D1 — A per-type tint, defined once

Five colours, one per `ItemType`, derived in a single place so the sidebar, the list chip, the detail
chip and the breadcrumb cannot drift apart:

| Type | Symbol | Tint |
|---|---|---|
| Login | `key` | blue |
| Card | `creditcard` | purple |
| Identity | `person.crop.rectangle` | teal |
| Secure Note | `note.text` | orange |
| SSH Key | `terminal` | green |

Exposed as `ItemType.tint` so the sidebar, the list chip, the detail chip and the breadcrumb cannot
drift apart — three views each deciding "what colour is a card" is how they end up disagreeing.

It is declared as an extension **in the Presentation layer**, not as a property in Domain. `ItemType`
lives in Domain, and Domain imports Foundation only (Constitution §II) — `Color` is SwiftUI. An
extension is enough: Swift lets another module add a computed property to a type it does not own, so
the single definition still exists, and Domain stays Foundation-only with no enum of colour names to
translate. `ItemType.sfSymbol` stays where it is because a symbol *name* is a `String`.

## D2 — The chip keeps the favicon

The obvious reading of the mockup is "replace the favicon with a coloured type glyph". That would
delete a feature: `FaviconLoader` exists, the site icons are a Settings toggle, and a login row that
stops showing the GitHub mark is a regression dressed as a redesign.

So the chip holds `FaviconView` unchanged, on a tinted rounded rectangle, and the tint stays visible
around whatever the favicon does not cover. A login with an icon gets a favicon on a blue chip; a login
without one gets the blue key glyph. `vault-browser-ui`'s existing scenario — "favicon (or type-icon
fallback)" — stays true as written.

## D3 — Search moves, ⌘F does not

`.searchable` moves from the detail column to the sidebar column (`placement: .sidebar`). The text
binding, `isPresented: $isSearchFieldFocused`, `activateGlobalSearch()` / `deactivateGlobalSearch()`,
`isGlobalSearch`, the Trash-clears-query rule and the hidden ⌘F button are all untouched. The change is
a placement argument, not a search rewrite; `global-search`'s requirements are about behaviour and
remain satisfied.

A hand-drawn `TextField` was rejected: it would have to re-implement focus-on-⌘F, the clear button,
Escape handling and the accessibility traits the native control already provides correctly.

## D4 — Letter headings are removed, not restyled

The mockup has none, and the honest options were to keep a smaller version of them or drop them.

Dropped, for a reason that shows up in the screenshot: the headings and the rows compete. A heading
that is visually quieter than the item names it groups is decoration; one that is louder is a
distraction. Since `item-sorting` already concedes that headings "describe nothing" for date orders,
the same argument applies to a dense name-ordered list — position within an alphabetically sorted list
already encodes the letter, so the heading restates what the order says.

## D5 — The detail action row routes through the existing gates

Three buttons, and each one takes the path that already exists rather than a shortcut to the value:

- **Copy password** → `gate.copyGated` when the item is re-prompt protected, `onCopy` otherwise. The
  header button must not become the way around the gate that every other copy path respects.
- **Copy code** → a `TOTPCodeViewModel` built from the injected factory; the copied value is
  `copyValue`, which is the derived code and never the stored seed.
- **Open website** → a SwiftUI `Link`. Not `NSWorkspace`: `Presentation` does not import AppKit
  (Constitution §II), and `Link` is what `FieldRowView` already uses for the same purpose.

No button renders for an item that cannot supply it — a secure note has no password button.

## D6 — Field rows: a label column, and monospace only for secrets

The label becomes a fixed-width, secondary-coloured column, and the value proportional. Monospace is
kept for the values that are transcribed character by character — passwords, card numbers, security
codes, private keys, fingerprints — because that is what monospace is for, and dropped for usernames,
URLs and dates, which are read as words.

`detail-card-view` currently requires *all* values to be monospaced and *all* labels to be primary
text. That requirement is replaced (delta spec).

## D7 — New tints are contrast-aware from the start

`accessibility-contrast` requires every custom background tint to clear 3:1 and to strengthen when
Increase Contrast is on. Three new tints arrive with this change — the type chip, the list selection
and the hairline — so all three are `Opacity` functions taking `ColorSchemeContrast`, not literals in a
view. A literal would satisfy the redesign and quietly fail the accessibility requirement.

## D8 — Tokens before views

`CLAUDE.md` forbids raw font and spacing literals in views, and the redesign changes nearly every
measurement on screen. Every new value is added to `Typography` / `Spacing` first, and the token table
in `CLAUDE.md` is updated in the same change — the table is the only place the tokens are enumerated,
so leaving it stale makes the rule unenforceable.

## D9 — The mockup is scaffolding, and stays out of the shipping target

`Prizm/PrizmTests/Presentation/Design/` holds the fixture vault, the mockup and the screenshot
harness. They live in the test target deliberately: the harness renders the *real* views, so it is
useful after this change rather than only during it, and nothing it contains ships. The mockup itself
(`ProposedDesignMockup.swift`) is deleted once the real views match it — it is a picture of an
intention, not a component.
