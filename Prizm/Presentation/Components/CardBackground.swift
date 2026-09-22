import SwiftUI

// MARK: - CardBackground

/// A `ViewModifier` that renders any view inside a card-style container:
/// rounded corners, a named background color that adapts for light/dark mode,
/// and a soft drop shadow.
///
/// Adapted from: https://danijelavrzan.com/posts/2023/02/card-view-swiftui/
///
/// The background uses the `CardBackground` named colour asset — white in light aqua, `#212121` in
/// dark — with a hairline stroke and **no shadow**. The stroke is what separates a card from the pane:
/// a black shadow is invisible on a dark background, and the asset's two values sit only a few levels
/// off their window, so without the edge the card would not be a card.
///
/// The radius is `Spacing.cardCornerRadius`, the same value the detail header's chip uses, because a
/// card and the chip above it disagreeing by 4pt is visible immediately.
struct CardBackground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Color("CardBackground"))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius)
                    .stroke(Color.primary.opacity(Opacity.cardBorder(contrast)), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Applies the card background modifier: rounded corners, adaptive background, and shadow.
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}

// MARK: - SectionCountLabel

/// The collapsed row's text inside a titled section card whose content loads on demand — the
/// password history and the passkey list.
///
/// **Why it says a number rather than the section's name.** These two sections used to render as a
/// `DetailSectionCard` with no title, with the heading inside the card in `.headline`. That left them
/// looking like a rendering glitch next to Credentials and Websites, each of which has an uppercase
/// label above its card. The fix is to give them that label like everyone else — which then means the
/// row inside cannot repeat it, the same rule that removes duplicate labels elsewhere in the pane. So
/// the header names the section and this row carries the one fact the header cannot: how many there
/// are, before anything is decrypted to find out.
struct SectionCountLabel: View {

    /// `nil` until the section has been opened once and the count is known.
    let count: Int?

    /// Whether the disclosure is open. Needed because the same absence means two different things:
    /// closed-and-not-yet-loaded, versus open-and-fetching-right-now. Saying "Loading…" to the first
    /// would invent a request that is not happening.
    let isExpanded: Bool

    /// Kept as a parameter because each section has its own identifier, and a test asserts on the
    /// one belonging to the section it is looking at.
    let identifier: String

    var body: some View {
        Group {
            if let count {
                Text(L("%d entries", count))
                    .accessibilityIdentifier(identifier)
            } else if isExpanded {
                Text(L("Loading…"))
            } else {
                // "Expand" rather than "Show": the latter would collide in the string table with the
                // reveal controls, which mean "display the secret" — a different verb entirely.
                Text(L("Expand"))
            }
        }
        .font(Typography.detailFieldLabel)
        .foregroundStyle(Foreground.muted)
        .monospacedDigit()
    }
}

// MARK: - DetailSectionCard

/// A card-style section container for vault item detail views.
///
/// Renders an optional section header label above a group of field rows,
/// all wrapped in a `cardBackground()`. Used by all five type-specific detail
/// views to group related fields visually.
///
/// Usage:
/// ```swift
/// DetailSectionCard(L("Credentials")) {
///     FieldRowView(label: L("Username"), ...)
///     Divider()
///     FieldRowView(label: L("Password"), ...)
/// }
/// ```
struct DetailSectionCard<Content: View>: View {

    private let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionLabelGap) {
            if Self.hasHeader(title) {
                // Uppercase and secondary: a category label, not content. At `.headline` in the
                // primary colour it read as a heading and competed with the values beneath it.
                Text(title!.uppercased())
                    .font(Typography.sectionLabel)
                    .tracking(Spacing.sectionLabelTracking)
                    .foregroundStyle(Foreground.muted)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(
                        AccessibilityID.Detail.cardHeader(title!)
                    )
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .cardBackground()
        }
        .padding(.horizontal, Spacing.detailMargin)
        .padding(.bottom, Spacing.cardBottom)
    }

    // MARK: - Testable header logic

    /// Returns `true` when the card should render a visible section header.
    ///
    /// A nil or whitespace-only title means no header is rendered — the card
    /// appears without a label above it.
    static func hasHeader(_ title: String?) -> Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
