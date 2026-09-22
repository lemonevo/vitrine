# Vault UI redesign — Proposal

## Why

The vault browser works and every feature in it is reachable, but it reads as a form rather than as a
password manager. Rendering the real panes with a realistic fixture vault
(`Prizm/PrizmTests/Presentation/Design/`) made four things concrete rather than a matter of taste:

1. **The list is too sparse to scan.** At a 720pt window height, seven items are visible and four of
   those slots are occupied by A/B/C/D letter headings. The headings are set in the same weight as the
   content, so the eye lands on them first and the items second.
2. **Item type is invisible.** All five types share one grey outline glyph. Nothing distinguishes a
   login from a card from a note without reading the subtitle.
3. **The detail pane has no head.** An item opens onto a very large title and then a stack of cards.
   Which folder and organisation it belongs to is in a footer at the bottom, below the fold; the
   commands a user actually wants on arrival — copy the password, copy the code, open the site — live
   in the toolbar, the Item menu, or on hover over an individual row.
4. **Every value is monospaced.** Usernames, URLs and dates are set in a monospace face, which is the
   right choice for a password and the wrong one for everything else.

## What changes

- **Sidebar.** A search field moves into the sidebar (the field the app already has, relocated — not a
  second one). Section headers become small uppercase labels, rows become denser, type rows get the
  same per-type tint the list uses, and the selection is a filled accent row. A status line with a dot
  replaces the bare timestamp.
- **Item list.** Letter headings are removed: the list is one flat, dense list under every sort order.
  Each row gains a 30pt tinted chip that holds the favicon where one exists and the type symbol where
  it does not, so type is legible at a glance without losing the favicon feature. Rows carry the org
  badge and the favourite star.
- **Detail pane.** A proper header — tinted type chip, the item's name, and a breadcrumb of username,
  folder and organisation — followed by an action row (Copy password, Copy code, Open website). Section
  headers become uppercase small labels; field rows get a fixed-width label column and proportional
  values, with monospace kept for secrets. The two-line date footer becomes one relative line.

## What this deliberately does not change

- **The three-pane structure.** Still a `NavigationSplitView` with the same columns and the same
  minimum widths.
- **The sidebar's section order.** `vault-browser-ui` pins Menu Items → Folders → Types →
  Organizations → Trash, and the mockup that prompted this change happened to draw them in a different
  order. The pinned order wins; only the styling changes.
- **Behaviour.** No command is added, removed or rewired. Every action the redesign surfaces in the
  detail header already existed in a menu or on hover; the header only stops hiding it.
- **`CardBackground`.** Already `#FAFAFA`/`#2C2C2C`, radius 10, border, no shadow — which is what the
  redesign wants.

## Substituted requirements

Three pinned requirements contradict the approved design and are replaced rather than quietly broken.
Each has a delta spec in `specs/`:

- `item-sorting` — headings under name orders are removed; the list is always flat.
- `detail-card-view` — section-header style, field-row layout and typography, and the metadata footer.
- `accessibility-contrast` — the three new background tints are held to the same 3:1 rule and the same
  Increase-Contrast behaviour as the existing ones.

One pinned statement becomes *more* true and needs no change: `settings-screen` requires the gear
button to sit "next to the search field". Today the gear is in the sidebar's toolbar and the field is
in the detail column's, so the requirement is already inaccurate; moving the field into the sidebar
satisfies it.

## Non-goals

- **New commands.** The action row is a resurfacing, not a feature.
- **A theme system.** Colours stay semantic and adapt to light/dark; no user-selectable palette.
- **Icons or illustrations.** The redesign uses SF Symbols that are already in the app.
