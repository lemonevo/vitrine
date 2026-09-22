# Vitrine Development Guidelines

**Constitution: [CONSTITUTION.md](CONSTITUTION.md) (v1.4.0) — READ THIS FIRST.**
The Constitution defines seven non-negotiable principles that govern every decision in this
codebase: Native-First (SwiftUI only), Clean Architecture (strict layer boundaries), Security-First
(vetted crypto only, no hand-rolled algorithms), TDD (Red→Green→Refactor, no exceptions),
Observability (no silent failures), Simplicity/YAGNI, and Radical Transparency (all crypto must be
publicly auditable). Before implementing any feature, adding a dependency, or making an
architectural decision, consult the Constitution. Violations are blocking PR rejections.

## Active Technologies

- **Language**: Swift 6.2 (Swift 6 language mode)
- **UI Framework**: SwiftUI (`NavigationSplitView` for three-pane layout)
- **Concurrency**: Swift async/await + Structured Concurrency
- **Platform**: macOS 26+
- **Project type**: macOS desktop app (App Sandbox + Hardened Runtime)
- **Crypto/Vault**: CommonCrypto + CryptoKit + Security.framework + `Argon2Swift` (Argon2id only) — Data layer only, behind `BitwardenCryptoService` protocol.
- **Storage**: macOS Keychain (secrets), UserDefaults (UI prefs), in-memory (decrypted vault)
- **Networking**: `URLSession` (no third-party networking library)
- **Testing**: XCTest (unit + integration), XCUITest (UI journeys)
- **Logging**: `os.Logger` with subsystem `com.prizm`

## Project Structure

```text
Prizm/
├── Prizm.xcodeproj/
├── App/                # @main, AppContainer (DI), Config
├── Domain/             # Entities, UseCase protocols, Repository protocols, Utilities
├── Data/               # Crypto, Network, Keychain, Repository impls, UseCase impls, Mappers
├── Presentation/       # SwiftUI Views, ViewModels, Components
├── PrizmTests/     # Unit + integration tests (XCTest)
└── Tests/UITests/      # UI journey tests (XCUITest)

openspec/
├── changes/            # Active and archived change specs (one dir per feature)
└── specs/              # Approved specs awaiting or under implementation
```

## Setup

**Team ID required:** Always ask the user for their Apple Developer Team ID before running any build or test command. The build will fail without `Prizm/LocalConfig.xcconfig` containing a valid `DEVELOPMENT_TEAM`. See `DEVELOPMENT.md` for full setup instructions.

## Commands

```bash
# Open project
open "Prizm/Prizm.xcodeproj"

# Build
xcodebuild -project "Prizm/Prizm.xcodeproj" \
           -scheme "Prizm" -configuration Debug build

# Run all tests — the flags are what CI passes; without them a build with no
# provisioning profile for the bundle id fails before any test runs
xcodebuild test \
  -project "Prizm/Prizm.xcodeproj" \
  -scheme "Prizm" \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Active Changes

| Change | Dir |
|---|---|
| csv-export | `openspec/changes/csv-export/` |
| ui-redesign | `openspec/changes/ui-redesign/` |
| favicon-trust-session | `openspec/changes/favicon-trust-session/` |
| encoder-invariant-tests | `openspec/changes/encoder-invariant-tests/` |
| auth-screens-redesign | `openspec/changes/auth-screens-redesign/` |
| xcode-localisation-resources | `openspec/changes/xcode-localisation-resources/` |
| item-actions-in-detail-header | `openspec/changes/item-actions-in-detail-header/` |
| biometric-system-prompt | `openspec/changes/biometric-system-prompt/` |

## Change Workflow (openspec)

Feature changes live under `openspec/changes/<name>/`. Each change has design, spec, and task
artifacts. Use `/opsx:new` to start a change, `/opsx:apply` to implement tasks, `/opsx:verify`
then `/opsx:archive` when done. Archived changes move to `openspec/changes/archive/`.

## Design System

All Presentation layer typography and spacing is defined in one place:
`Prizm/Presentation/DesignSystem.swift`

**Never use raw font or spacing literals in views.** Always reference the tokens below.

### Typography tokens (`Typography.*`)

| Token | Font | Approx pt (macOS) | Role |
|---|---|---|---|
| `pageTitle` | `.largeTitle.bold()` | 26pt | Item name on the auth screens |
| `fieldValue` | `.body` | 13pt | Primary field content outside the detail cards |
| `fieldLabel` | `.subheadline` | 11pt | Small label above a field value |
| `utility` | `.caption` | 10pt | COPY button, metadata |
| `listTitle` | `.system(size: 13, weight: .medium)` | 13pt | Item name in the list pane |
| `listSubtitle` | `.system(size: 11)` | 11pt | Secondary subtitle in list rows; sidebar sync status |
| `sectionLabel` | `.system(size: 11, weight: .semibold)` | 11pt | Uppercase category label above a detail card and a sidebar section; add `.tracking(Spacing.sectionLabelTracking)` |
| `detailTitle` | `.system(size: 22, weight: .semibold)` | 22pt | Item name in the detail header |
| `breadcrumb` | `.system(size: 12)` | 12pt | The line placing the item (username · folder · org) |
| `detailFieldLabel` | `.system(size: 11)` | 11pt | Fixed-width label column inside a detail card |
| `detailFieldValue` | `.system(size: 14)` | 14pt | Value inside a detail card; secrets add `.monospaced()` |
| `actionButton` | `.system(size: 12, weight: .medium)` | 12pt | Detail header action button label |
| `totpCode` | `.system(size: 16, weight: .medium).monospaced()` | 16pt | The live one-time code |
| `metaLine` | `.system(size: 11)` | 11pt | The created/updated line at the foot of the detail pane |
| `orgBadge` | `.system(size: 9, weight: .medium)` | 9pt | Organisation badge on an item row |
| `controlGlyph` | `.system(size: 12, weight: .medium)` | 12pt | Glyph inside a header control — see `ControlStyles.swift` |
| `screenHeading` | `.title.bold()` | ~22pt | The "Vitrine" / "Vitrine Is Locked" heading on an entry screen |
| `screenBody` | `.callout` | 13pt | The entry-screen subtitle, error banner, and sync message |
| `fieldLabelProminent` | `.callout.weight(.medium)` | 13pt | A form label that must out-rank `fieldLabel` |

### Spacing tokens (`Spacing.*`)

| Token | Value | Role |
|---|---|---|
| `pageMargin` | 20pt | Horizontal edges of the auth screens |
| `pageTop` | 28pt | Above the item title |
| `pageHeaderBottom` | 12pt | Below the item title |
| `cardTop` | 12pt | Above each section card |
| `cardBottom` | 20pt | Below each section card, and above the metadata line |
| `cardCornerRadius` | 10pt | A card, and the detail header's chip |
| `headerGap` | 8pt | Between section header label and card |
| `rowVertical` | 9pt | Generic row top/bottom padding |
| `rowHorizontal` | 12pt | Generic row left/right padding |
| `sidebarIconWidth` | 18pt | Reserved icon width in a sidebar row |
| `sectionLabelTracking` | 0.5pt | Letter-spacing on every uppercase section caption |
| `listRowHeight` | 40pt | An item row, chip and text included |
| `listChip` / `listChipIcon` / `listChipCornerRadius` | 26pt / 14pt / 7pt | The type-tinted chip on an item row |
| `listRowHorizontal` / `listRowEdgeInset` | 10pt / 6pt | Inside an item row, and the fill's inset from the pane |
| `listStarColumn` | 20pt | Reserved for the favourite star, favourited or not |
| `listDividerInset` | 52pt | Leading inset of the hairline between item rows |
| `detailContentWidth` | 480pt | The detail pane's content is capped here, then centred |
| `detailMargin` | 24pt | Horizontal edges of the detail pane |
| `detailLabelWidth` | 100pt | The label column inside a detail card |
| `detailActionSlotWidth` | 56pt | The trailing slot: copy glyphs and reveal eyes share one x |
| `detailRowMinHeight` | 42pt | A detail card row, growing when a value wraps |
| `detailRowVertical` / `detailRowHorizontal` | 9pt / 14pt | Inside a detail card field row |
| `detailHeaderTop` / `detailHeaderBottom` | 22pt / 16pt | Around the detail header |
| `detailHeaderGap` | 12pt | Across the header: chip, name block, controls |
| `detailActionsBottom` | 20pt | Between the action row and the first card |
| `detailChip` / `detailChipIcon` / `detailChipCornerRadius` | 44pt / 22pt / 10pt | The type-tinted chip in the detail header |
| `controlHeight` / `actionButtonCornerRadius` / `actionButtonHorizontal` | 26pt / 6pt / 11pt | Every header control's height, and the chrome inside it |
| `authCardWidth` / `authCardPadding` / `authCardCornerRadius` | 400pt / 24pt / 14pt | The card both entry screens are built inside |
| `authCardShadowRadius` / `authCardShadowY` | 18pt / 6pt | That card's shadow |
| `authIconSize` / `authHeaderBottom` | 56pt / 22pt | Application icon, and the gap below the entry header |
| `authBannerCornerRadius` | 7pt | Corner radius of the entry-screen error banner |
| `authFieldWidth` | 352pt | A field on an entry screen — the card's inner content width |
| `authFootnoteGap` | 14pt | Between the auth card and the caption under it |
| `authFieldGap` | 12pt | Between stacked fields inside the auth card |
| `authActionTopGap` | 14pt | Above the card's filled action, and above the banner before it |
| `authDividerVertical` | 16pt | Around the rule under the credential fields |
| `authProgressHeight` | 34pt | Height reserved while deriving or syncing, so the card does not jump |
| `authProgressLabelGap` | 6pt | Between the spinner and the sync message |
| `fieldLabelGap` | 5pt | Between a field's label, its control and its hint |
| `bannerVertical` | 8pt | Vertical padding inside status banners |

### Controls (`ControlStyles.swift`)

One height — `Spacing.controlHeight`, 26pt — and three forms: `FilledControlStyle` (the pane's single
most likely next action; never more than one on a line), `BorderedControlStyle` (a secondary action with
a word on it), `GlyphControlStyle` (icon only). `GlyphControl` is the same square for an affordance that
cannot be a `Button` because its row already owns the tap.

The filled style's colour is drawn by hand rather than `.borderedProminent` for two reasons: a white label
on `controlAccentColor` measures 4.02:1, under the floor for its own 12pt text, and `.borderedProminent`
renders grey in any window that is not key — including every window the screenshot harness opens — so the
fill under review would never be the fill that ships.

`BorderedControlStyle` and `GlyphControlStyle` take `contrast` as a parameter. A `ButtonStyle` is not a
`View`, so `@Environment` would not update inside one; call sites already have the value.

### Contrast-aware opacity (`Opacity.*`)

Fills and strokes derived from `Color.primary` or a semantic colour take their alpha from
`Prizm/Presentation/ContrastAwareOpacity.swift`, keyed on `@Environment(\.colorSchemeContrast)`, so
"Increase contrast" in System Settings actually changes something. Never write `.opacity(0.12)` in a
view.

| Function | normal / increased | Role |
|---|---|---|
| `bannerBackground` | 0.35 / 0.50 | Status banner fill |
| `cardBorder` | 0.12 / 0.20 | Section card border |
| `trashBanner` | 0.20 / 0.30 | Trash notice fill |
| `errorBanner` | 0.20 / 0.30 | Entry-screen error fill |
| `dropTarget` | 0.25 / 0.40 | Attachment drop target |
| `typeChip` | 0.16 / 0.28 | Tinted chip behind a type icon |
| `hairline` | 0.12 / 0.22 | Divider between item rows |
| `selectionFill` | 0.12 / 0.22 | Accent fill behind a selected row, in the list and the sidebar |
| `controlHover` | 0.08 / 0.14 | A control under the pointer or mid-press |
| `authCardBorder` | 0.20 / 0.40 | Edge of the auth card — stronger, because it is the only thing marking the panel in dark mode |

`AccessibilityTier2Tests` asserts the direction for **every** function in that list, in one table. It
covered five of eight when the three unlisted ones were the ones a contrast delta required.

### Text foreground (`Foreground.*`)

`.secondary` and `.tertiary` are **not** safe for copy a user has to act on. Measured on this Mac
against the resolved sRGB system surfaces, light / dark: `secondaryLabel` 3.95:1 / 5.89:1 (fails AA in
light), `tertiaryLabel` 1.88:1 / 2.26:1 (fails both). AA for text at 13pt and below is 4.5:1, which
`ACCESSIBILITY.md` claims.

| Token | Light / dark | Use for |
|---|---|---|
| `Foreground.muted` (`Color.primary.opacity(Foreground.mutedAlpha)`, currently 0.68) | 5.18:1 on the light card, 5.24:1 on light grey, 5.70:1 / 6.34:1 dark | Secondary-in-weight, mandatory-in-content: field labels and hints, entry-screen subtitles, section captions, list subtitles, sidebar counts, breadcrumbs, the "COPIED" word |
| `Foreground.action` (`Color(nsColor: .linkColor)`) | 5.26:1 / 5.89:1 | Text that is a way to do something: a link, a switch, an inline command. `accentColor` measures 4.02:1 / 4.15:1 and `systemBlue` 3.52:1 / 5.16:1 — neither clears AA at these sizes |
| `Foreground.warning` (resolves per appearance: `#8C4700` / `#E9A23B`) | 6.97:1 / 7.69:1 | A state to act on. No single amber clears both modes, so this one is a dynamic `NSColor`, never a constant |
| `Foreground.success` (`Foreground.successComponents`) | 5.59:1 / 8.23:1 | The sync dot. `Color.green` is 2.22:1 in light — under the 3:1 non-text floor, and it was the at-a-glance signal |
| `Foreground.favorite` (`Foreground.favoriteComponents`) | 5.49:1 light / 9.97:1 dark | The favourite star, in the list row, the detail header and the sidebar. `Color.yellow` measured 1.28:1 on the light window — including in the design mock, which was reviewed as a picture and cannot show a ratio |

**Measure the compositing, not the number you wrote.** `Foreground.muted` shipped as `0.62` with
"6.20:1" beside it; the real figure was **4.31:1**, because `labelColor` is itself 84.7% opaque and the
two alphas multiply. `ContrastTokenTests` now does that arithmetic against the surfaces the panes
actually paint, and one of its tests asserts that 0.62 fails — so the token cannot drift back quietly.
It also means `NSColor.windowBackgroundColor` cannot be used as the background in such a test: read
outside a drawing context it resolves to pure white, which flatters dark text.

Never write `.foregroundStyle(.tertiary)` on text, and never pick a warning colour at a call site.
Neither token is ever the only signal — pair it with a glyph and plain words. See
`openspec/changes/unlock-credential-layering/design.md` (D5).

### Type colours (`ItemType.tint`)

One definition, five types, drawn in the sidebar's type rows, the list's icon chip and the detail
header's chip. They are **not** the system `.blue/.purple/.teal/.orange/.green` they replaced: those
measured 2.90:1, 3.33:1, 1.89:1, 2.02:1 and 1.95:1 against their own `Opacity.typeChip` fill in light
aqua, under the 3:1 floor for non-text content. The palette is per-appearance
(`ItemType.tintComponents`) and clears 3.86:1 in its worst case.

They are deliberately low-saturation: the accent colour now carries selection, and a row of five
saturated hues competed with it for "this is the important one".

### Interface strings

Every user-facing literal goes through `L("key")` (`Prizm/App/LocalizationManager.swift`), and the
key must be added to **both** `Prizm/Resources/en.lproj/Localizable.strings` and
`zh-Hans.lproj/Localizable.strings`. A missing key does not fail: it renders the key itself, so
Chinese silently reads as English. `LocalizationResourcesTests` checks key parity, and that the
English table's values *are* its keys — an English entry with a pasted-in Chinese value is a bug, not
a translation.

The two files reach the app bundle through a `PBXVariantGroup` in the Xcode project. They are **not**
covered by the app target's file-system-synchronised group, which only spans `Prizm/Prizm`
(assets, `Info.plist`); a new resource under `Prizm/Resources/` has to be registered the same way or
it will silently not ship.

Switching language at runtime is `LocalizedBundle.overrideBundle`, not
`ActiveLocalization.languageCode` — the latter only feeds date and number formatting. Anything that
renders a screen in a chosen language has to set both, and a screenshot taken without checking will
happily photograph English and look fine.

The test run is pinned to English by `Prizm/PrizmTests.xctestplan`, referenced from the shared scheme.
Without it the suite resolves strings against whatever language System Settings is set to, and passes
on one Mac while failing on another.

### Item type tint

`ItemType.tint` (a Presentation extension on the Domain enum, in `DesignSystem.swift`) is the one
definition of the colour per item type. Use it with `Opacity.typeChip(contrast)` rather than naming a
colour at a call site, so the sidebar, the item list and the detail header cannot drift apart.

### Adding new views

When building a new view that needs fonts or spacing:
1. Check if an existing token fits — use it.
2. If a genuinely new role is needed, add it to `DesignSystem.swift` with a comment.
3. Never hardcode a size that should be consistent with existing UI.

## Architecture Rules

1. **Domain layer** — `import Foundation` only. No crypto imports, no `SwiftUI`, no `AppKit`.
2. **Data layer** — Only place that imports CommonCrypto, CryptoKit, Security, or `Argon2Swift`.
   All crypto behind `BitwardenCryptoService` protocol. Translate types to Domain entities via
   mappers in `Data/Mappers/`.
3. **Presentation layer** — Only place that imports `SwiftUI`. Uses Domain use cases; never
   imports Data layer or crypto modules directly.
4. **TDD enforced** — Write failing test before writing implementation. Domain use cases and
   Data mappers require unit tests. Critical UI journeys require XCUITest.
5. **No swallowed errors** — Every `catch {}` must either rethrow or log + surface to Presentation
   via a typed `Error`.

## Code Style (Swift)

- `async/await` for all async code — no callbacks or Combine publishers in new code
- `struct` over `class` for Domain entities (value semantics)
- `actor` for shared mutable state in Data layer (e.g. `FaviconLoader`)
- `protocol` + `impl` naming: protocol = `AuthRepository`, impl = `AuthRepositoryImpl`
- Constants in `enum` namespaces, not loose `let` at file scope
- `os.Logger` levels: `.debug` trace, `.info` normal flow, `.error` recoverable, `.fault` unrecoverable
- Secrets MUST NOT appear in log output
- **Item-level commands go in the item's header, not the window toolbar.** `NavigationSplitView` lays
  each column's `ToolbarItem`s out in column order, so item commands there produce a row of
  equal-weight circles that changes shape every time the selection changes. See
  `openspec/changes/item-actions-in-detail-header/design.md` (D1) for the test applied to each control.
- **A view that shows a published value must observe the model that publishes it.** `let model: X`
  where `X: ObservableObject` installs no subscription: the view draws once and freezes, while every
  unit test stays green because the model is correct. When a row struct carries its own view model, the
  cell that reads it needs `@ObservedObject` — its own type. This has now happened twice in
  `VerificationCodes/` (the sheet's content, then the code cell).
- **A user-facing string is `L("key")`, never a bare literal.** Three controls in the vault chrome
  (`Edit`, `Restore`, `Delete Permanently`) were literals and showed English in the Chinese interface.
- **`VaultBrowserView`'s `NavigationSplitView` sits at the type checker's limit.** When it reports
  "unable to type-check this expression in reasonable time", extract a named `some View` or
  `some ToolbarContent` property — adding one more closure argument to `ItemDetailView(...)` was enough
  to trip it. The error points at whichever sub-expression it gave up on, not at the cause.

## Code Comments (Open Source Standard)

Comments are a first-class public artifact — explain *why*, not *what*. Key rules:

- Don't restate the code; add information the code can't express on its own.
- Don't excuse unclear code with a comment — rename the variable or refactor.
- Explain non-obvious or unidiomatic code (platform quirks, intentional no-ops, workarounds).
- Link RFCs and specs at the point of use: `// Argon2id per RFC 9106 §4`
- Link bug fixes to their issue: `// Fix: keychain returned nil on first launch — #42`
- Mark gaps: `// TODO: what + why deferred` / `// FIXME: what is broken + workaround`

**Security-critical functions** (crypto, keychain, auth) must document:
- Security goal (what threat this defends against)
- Algorithm + spec reference
- Any deviation from the standard and why it is safe
- What is intentionally NOT done (if the omission could look like a bug)
