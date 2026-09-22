import SwiftUI

// MARK: - Item type tint

/// The colour that stands for each vault item type across the browser: the sidebar's type rows, the
/// item list's icon chip, the detail header's icon chip, the breadcrumb.
///
/// **Why this is an extension here and not a property on `ItemType`.** `ItemType` lives in the Domain
/// layer, which imports Foundation only (Constitution §II) — `Color` is SwiftUI. Extending the type
/// from Presentation keeps the single definition without moving a presentation concern into Domain,
/// and without an enum of colour *names* whose only job would be to be translated back into a `Color`.
/// `ItemType.sfSymbol` stays in Domain for the opposite reason: a symbol name is a `String`.
///
/// **Why one definition matters.** Three views draw this colour. Three `switch` statements would agree
/// on the day they were written and drift afterwards, and the sidebar would be the one nobody
/// re-checked.
extension ItemType {

    /// The sRGB components of this type's colour, per appearance.
    ///
    /// Authored as numbers rather than only as a `Color` so `ContrastTokenTests` measures the palette
    /// the interface draws with. A test that read the `Color` back would be asserting on the
    /// SwiftUI→AppKit bridge, not on these values.
    nonisolated var tintComponents: (light: (Double, Double, Double), dark: (Double, Double, Double)) {
        switch self {
        // Two hand-picked values per type rather than one colour with its saturation pulled out:
        // desaturating the system purple lands on grey, and grey beside the grey folder glyphs is the
        // outcome this palette exists to avoid. Both branches keep a readable hue.
        case .login:      return (light: (0.24, 0.40, 0.68), dark: (0.47, 0.64, 0.90))
        case .card:       return (light: (0.48, 0.32, 0.65), dark: (0.74, 0.62, 0.87))
        case .identity:   return (light: (0.16, 0.46, 0.47), dark: (0.44, 0.73, 0.73))
        case .secureNote: return (light: (0.63, 0.40, 0.13), dark: (0.87, 0.70, 0.47))
        case .sshKey:     return (light: (0.17, 0.46, 0.28), dark: (0.52, 0.77, 0.59))
        }
    }

    /// The tint for this item type: the sidebar's type rows, the icon chip in the list and the detail
    /// header, and the fallback glyph behind a favicon.
    ///
    /// **These are not the system colours they replace.** `Color.teal`, `.orange` and `.green` measured
    /// 1.89:1, 2.02:1 and 1.95:1 against their own `Opacity.typeChip` fill in light aqua — under the
    /// 3:1 floor for non-text content, on the one surface where the glyph actually sits. `blue` was
    /// next at 2.90:1. The values here clear 3.86:1 in the worst case of the same measurement, in both
    /// appearances.
    ///
    /// They are also lower-saturation than the system set on purpose: with the accent colour now
    /// carrying selection, a row of five saturated hues competed with it for the "this is the important
    /// one" role.
    var tint: Color {
        let components = tintComponents
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? components.dark : components.light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

// MARK: - Typography
//
// All font roles for the Prizm Presentation layer.
//
// Use these constants instead of raw `.font(...)` values to keep
// the type scale consistent across every view. Change a role here
// and every consumer updates automatically.
//
// macOS type scale reference (approximate pt sizes at default size):
//   .largeTitle 26 · .title 22 · .title2 17 · .title3 15
//   .headline 13 semibold · .body 13 · .callout 12
//   .subheadline 11 · .footnote 10 · .caption 10
enum Typography {
    /// Item name in the detail pane — the largest text on screen.
    static let pageTitle: Font     = .largeTitle.bold()


    /// Primary field content — the value the user cares about.
    static let fieldValue: Font    = .body

    /// Small label rendered above a field value.
    static let fieldLabel: Font    = .subheadline

    /// Utility text: COPY button, footer dates, metadata.
    static let utility: Font       = .caption

    /// Item name in the list pane.
    static let listTitle: Font     = .system(size: 13, weight: .medium)

    /// Secondary subtitle in the list pane (username, last 4 digits, etc.).
    static let listSubtitle: Font  = .system(size: 11)

    /// Uppercase category label above a detail card and above a sidebar section.
    static let sectionLabel: Font  = .system(size: 10, weight: .semibold)

    /// The item's name in the detail pane header.
    static let detailTitle: Font   = .system(size: 20, weight: .semibold)

    /// The line under the detail header that places the item (username · folder · organisation).
    static let breadcrumb: Font    = .system(size: 12)

    /// Field label inside a detail card — a fixed-width column, so every value starts at one x.
    static let detailFieldLabel: Font = .system(size: 12)

    /// Field value inside a detail card. Proportional; secrets are set monospaced on top of it.
    static let detailFieldValue: Font = .system(size: 13)

    /// Label on a detail header action button.
    static let actionButton: Font  = .system(size: 12, weight: .medium)

    /// The live one-time code — larger than surrounding text because it is transcribed by eye.
    static let totpCode: Font      = .system(size: 16, weight: .medium).monospaced()

    /// The single created/updated line at the foot of the detail pane.
    static let metaLine: Font      = .system(size: 11)

    /// The organisation badge on an item row.
    static let orgBadge: Font      = .system(size: 9, weight: .medium)

    /// The type symbol inside an item row's tinted chip.
    static let chipIcon: Font      = .system(size: 14)

    /// Status banner text (e.g. "This item is in Trash.") — slightly larger than utility/caption.
    static let bannerText: Font    = .callout

    /// Prominent status label on loading/syncing screens (e.g. "Fetching vault…").
    /// Semibold weight distinguishes it from regular body copy in loading contexts.
    static let progressLabel: Font = .headline

    /// Inline field label shown above a form input (e.g. "Authentication code").
    /// Slightly heavier than `fieldLabel` to visually separate it from body content.
    static let fieldLabelProminent: Font = .callout.weight(.medium)

    /// Top-level sidebar rows (All Items, Favorites, item types, Trash).
    static let sidebarRow: Font = .system(size: 13)


    /// Large icon on the Login, TOTP, and Unlock screens (keyhole / app symbol).
    static let screenIcon: Font    = .system(size: 48)

    /// Primary heading on the Login, TOTP, and Unlock screens ("Welcome to Vitrine").
    static let screenHeading: Font = .title.bold()

    /// Secondary body copy on the Login, TOTP, and Unlock screens.
    static let screenBody: Font    = .callout
}

// MARK: - Foreground
//
// Text colours that carry information. These exist because `.secondary` and `.tertiary` are not
// safe for copy a user has to read: measured on this Mac against the resolved sRGB values of the
// system surfaces, `secondaryLabelColor` is **3.95:1 in light aqua** (it passes in dark, at 5.89:1),
// and `tertiaryLabelColor` is **1.88:1 in light / 2.26:1 in dark**. Both sit under the 4.5:1 that
// `ACCESSIBILITY.md` claims for the interface, and `tertiary` is under the 3:1 floor for large text.
//
// **`Foreground.muted` used to be 0.62, and the ratio recorded beside it was wrong.** The measurement
// that picked that value multiplied `Color.primary` by 0.62 and compared the result to the surface —
// but `labelColor` is itself 84.7% opaque, so the two alphas compose to 52.7% and the real figure was
// **4.31:1 on the light card and 4.35:1 on light white**, not the 6.20:1 written down. Under the floor
// this file exists to enforce, 0.62 failed it. The alpha is now a named constant so
// `ContrastTokenTests` measures the number the interface draws with rather than a copy of it.
enum Foreground {

    /// The alpha `Foreground.muted` applies to `Color.primary`.
    ///
    /// Kept separate from the `Color` so the contrast test can compute the same compositing the
    /// renderer does. Changing it without re-running `ContrastTokenTests` is the mistake this exists
    /// to prevent.
    static let mutedAlpha: Double = 0.68

    /// Copy that is secondary in weight but not optional in content: the field hints on the entry
    /// screens, the sentence under the login card, section labels, subtitles, counts, breadcrumbs.
    ///
    /// Measured with `labelColor`'s own 84.7% alpha included: **5.18:1 on the light card (#FAFAFA),
    /// 5.24:1 on light white, 5.70:1 on the dark card, 6.34:1 on the dark window** — one value that
    /// clears AA in either appearance, which is why it needs no `colorScheme` branch, unlike the
    /// warning colour below.
    static let muted: Color = .primary.opacity(mutedAlpha)

    /// Text that is a way to do something — a link, a switch, an inline command.
    ///
    /// `Color.accentColor` is the obvious choice and it does not clear AA at the sizes this appears at:
    /// `controlAccentColor` measures 4.02:1 in light and 4.15:1 in dark, and `systemBlue` is worse
    /// (3.52:1 / 5.16:1). `linkColor` is the platform's own semantic "this is actionable" colour and it
    /// measures 5.26:1 / 5.89:1 — one value, both appearances, and it follows the user's System Settings
    /// accent the way a hand-picked blue would not.
    static let action: Color = Color(nsColor: .linkColor)

    /// The sRGB components behind `Foreground.success`, per appearance — authored as numbers so
    /// `ContrastTokenTests` measures what is drawn, not a bridge back to it.
    nonisolated static let successComponents: (light: (Double, Double, Double), dark: (Double, Double, Double)) =
        (light: (0.17, 0.46, 0.28), dark: (0.52, 0.77, 0.59))

    /// The sRGB components behind `Foreground.favorite`, per appearance.
    nonisolated static let favoriteComponents: (light: (Double, Double, Double), dark: (Double, Double, Double)) =
        (light: (0.55, 0.38, 0.00), dark: (0.95, 0.76, 0.28))

    /// The favourite marker, in the list row, the detail header's toggle and the sidebar's row icon.
    ///
    /// **Not `Color.yellow`.** System yellow measures **1.51:1 on white, 1.28:1 on the light window** —
    /// under half the 3:1 floor for non-text content, on the glyph whose entire job is to be spotted at
    /// a glance. It is also what the design mock drew, unchanged from the app: a picture reviewed on a
    /// retina display shows a pale star as a pale star, and nothing in a still image reports a ratio.
    ///
    /// Gold rather than a darkened yellow, and per appearance like `warning`: the light value is a
    /// bronze that keeps reading as "starred" (5.49:1), and the dark one is the bright gold (9.97:1).
    static let favorite: Color = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rgb = isDark ? favoriteComponents.dark : favoriteComponents.light
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    })

    /// A state that is good and current — the sidebar's "synced" dot.
    ///
    /// `Color.green` measured **2.22:1** against the light window, under the 3:1 floor for non-text
    /// content, so the dot that is supposed to make the sync state readable from across the room was
    /// the weakest thing on the pane. These two clear 5.59:1 light and 8.23:1 dark.
    static let success: Color = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rgb = isDark ? successComponents.dark : successComponents.light
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    })

    /// A state that needs acting on — the remaining PIN attempts.
    ///
    /// A single amber cannot serve both appearances: `#8C4700` measures 6.97:1 on a light surface and
    /// 2.39:1 on a dark one, and `#E9A23B` is the exact reverse (7.69:1 dark, 2.17:1 light). So the
    /// colour resolves per appearance at draw time rather than being picked by each call site, which
    /// is how it stays correct in a screenshot of the wrong mode.
    ///
    /// It is never the only signal: the row that shows it carries a warning glyph and plain words.
    static let warning: Color = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.914, green: 0.635, blue: 0.231, alpha: 1)   // #E9A23B
            : NSColor(srgbRed: 0.549, green: 0.278, blue: 0.000, alpha: 1)   // #8C4700
    })
}

// MARK: - Spacing
//
// Named spacing tokens for the Prizm Presentation layer.
//
// Prefer these over inline CGFloat literals so that layout rhythm
// stays consistent and tweaks propagate everywhere at once.
enum Spacing {
    /// Horizontal margin at the left and right edges of the detail pane.
    static let pageMargin:    CGFloat = 20

    /// Top padding above the item title / page header.
    static let pageTop:       CGFloat = 28

    /// Bottom padding below the item title before the first section card.
    static let pageHeaderBottom: CGFloat = 12

    /// Vertical padding above a section card (between cards or from the top).
    static let cardTop:       CGFloat = 12

    /// Vertical padding below a section card.
    static let cardBottom:    CGFloat = 18

    /// Gap between a section header label and the card below it.
    static let headerGap:     CGFloat = 8

    /// Vertical padding inside a field row (top and bottom).
    static let rowVertical:   CGFloat = 9

    /// Horizontal padding inside a field row (left and right).
    static let rowHorizontal: CGFloat = 12


    /// Horizontal padding inside status banners (sync error, trash banner).
    static let bannerHorizontal: CGFloat = 12

    /// Horizontal padding for sidebar footer elements (e.g. sync status label).
    /// Matches the visual inset of sidebar section headers.
    static let sidebarHorizontal: CGFloat = 20

    /// Bottom padding for the sidebar sync status label — slightly more than `rowVertical`
    /// to give the footer visual breathing room above the window edge.
    static let sidebarStatusBottom: CGFloat = 14

    /// Vertical padding inside status banners.
    static let bannerVertical: CGFloat = 8

    // MARK: Authentication screens

    /// Width of the card the login and unlock screens are built inside. Fixed, so the two entry
    /// screens are the same shape and switching between them does not resize anything.
    static let authCardWidth: CGFloat = 400

    /// Inner padding of that card.
    static let authCardPadding: CGFloat = 24

    /// Corner radius of the auth card.
    static let authCardCornerRadius: CGFloat = 14

    /// Radius and vertical offset of the auth card's shadow.
    static let authCardShadowRadius: CGFloat = 18
    static let authCardShadowY: CGFloat = 6

    /// Side of the application icon shown at the head of both entry screens.
    static let authIconSize: CGFloat = 56

    /// Gap between the auth header and the first field.
    static let authHeaderBottom: CGFloat = 22

    /// Gap between a field's label, its control, and its hint.
    static let fieldLabelGap: CGFloat = 5

    /// Corner radius of the error banner on an entry screen.
    static let authBannerCornerRadius: CGFloat = 7

    /// Width of the master-password field on the unlock screen. Matches the card's inner content
    /// width, so the field is no longer the narrowest element on the screen.
    static let authFieldWidth: CGFloat = 352

    /// Gap between the auth card and the caption under it. Small enough that the two read as one
    /// group, large enough that the caption is not mistaken for text inside the card.
    static let authFootnoteGap: CGFloat = 14

    /// Gap between stacked fields inside the auth card.
    static let authFieldGap: CGFloat = 12

    /// Gap above the card's one filled action, and above an error banner that precedes it.
    static let authActionTopGap: CGFloat = 14

    /// Vertical padding around the rule that separates the credential fields from what is below it.
    static let authDividerVertical: CGFloat = 16

    /// Height reserved while the vault is being derived or synced, so the card does not change height
    /// under the user's cursor between asking and answering.
    static let authProgressHeight: CGFloat = 34

    /// Gap between the spinner and the sync message shown while the vault is being fetched.
    static let authProgressLabelGap: CGFloat = 6


    /// Horizontal inner padding for inline badge labels (e.g. org membership badge on item rows).
    static let badgeHorizontal: CGFloat = 5

    /// Vertical inner padding for inline badge labels.
    static let badgeVertical: CGFloat = 1

    /// Corner radius for inline badge labels.
    static let badgeCornerRadius: CGFloat = 4

    /// Horizontal padding on full-screen auth/sync flows (Login, TOTP, Unlock, SyncProgress).
    static let screenHorizontal: CGFloat = 40

    // MARK: Sidebar rows



    /// Width reserved for a sidebar row's icon, so labels line up down the column.
    static let sidebarIconWidth: CGFloat = 16



    // MARK: Item list

    /// Vertical padding inside an item row.
    static let listRowVertical: CGFloat = 7


    /// Side of the square type-tinted chip holding an item row's icon.
    static let listChip: CGFloat = 30

    /// Side of the favicon inside the item row's type chip.
    static let listChipIcon: CGFloat = 18

    /// Corner radius of the item row's type chip.
    static let listChipCornerRadius: CGFloat = 7

    /// Gap between the item row's chip and its text.
    static let listRowSpacing: CGFloat = 10

    /// Gap between an item row's subtitle and the organisation badge beside it.
    static let listRowBadgeSpacing: CGFloat = 5

    /// Leading inset of the hairline between item rows, so it starts clear of the chip.
    static let listDividerInset: CGFloat = 52

    // MARK: Detail pane

    /// Horizontal margin at the left and right edges of the detail pane's content.
    static let detailMargin: CGFloat = 24

    /// The label column inside a detail card. Fixed, so values line down the card.
    ///
    /// Wide enough for the longest built-in label ("Verification Code"), and `DetailFieldLabel` wraps
    /// rather than truncates so a user-authored custom-field name still arrives in full.
    static let detailLabelWidth: CGFloat = 130

    /// Vertical padding inside a detail card field row.
    static let detailRowVertical: CGFloat = 9

    /// Horizontal padding inside a detail card field row.
    static let detailRowHorizontal: CGFloat = 14

    /// Top padding above the detail pane header.
    static let detailHeaderTop: CGFloat = 22

    /// Gap between the detail pane header and the action row.
    static let detailHeaderBottom: CGFloat = 14

    /// Gap between the action row and the first card.
    static let detailActionsBottom: CGFloat = 18

    /// Side of the square type-tinted chip in the detail header.
    static let detailChip: CGFloat = 44

    /// Side of the favicon inside the detail header's chip.
    static let detailChipIcon: CGFloat = 24

    /// Corner radius of the detail header's type chip.
    static let detailChipCornerRadius: CGFloat = 10

    /// Gap between a detail card's section label and the card.
    static let sectionLabelGap: CGFloat = 5

    /// Diameter of the one-time code's countdown ring.
    static let totpRing: CGFloat = 14

    /// Stroke width of the one-time code's countdown ring.
    static let totpRingLineWidth: CGFloat = 2

    /// Width reserved for the "21s" countdown in the verification-codes list. Fixed so the copy
    /// button does not shift as the number loses a digit.
    static let codesCountdownWidth: CGFloat = 26

    /// Gap between a detail row's value and its trailing affordances.
    static let detailRowGap: CGFloat = 8

    /// Corner radius of a detail header action button.
    static let actionButtonCornerRadius: CGFloat = 6

    /// Horizontal padding inside a detail header action button.
    static let actionButtonHorizontal: CGFloat = 11

    /// Vertical padding inside a detail header action button.
    static let actionButtonVertical: CGFloat = 5
}
