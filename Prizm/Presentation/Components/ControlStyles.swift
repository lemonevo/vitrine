import SwiftUI

// MARK: - Control styles

/// The three shapes a control in this app can take, all 26pt tall with a 12pt glyph: one filled action,
/// one bordered, one icon-only.
///
/// **Why the app has its own.** The detail header had a hand-drawn label view for the prominent action,
/// a bare `Button("Edit")` (so AppKit's bordered chrome), and a `.borderless` star — three controls on
/// one line at three heights, because nothing had said what a control is. `DesignSystem.controlHeight`
/// is now the one answer, and these are the three forms it takes.
///
/// **Why not `.borderedProminent`.** It cannot be judged from a screenshot: in a window that is not key
/// — which is every window the render harness opens — it draws grey, so the fill under review is never
/// the fill that ships. Drawing it as a `Color` makes it the same thing in both.
///
/// **Why each style takes `contrast`.** Increase Contrast has to reach the hover and border opacities,
/// and a `ButtonStyle` is not a `View`, so `@Environment` would not update inside it. The call sites
/// already read the environment; they pass it in.

// MARK: Filled

/// The pane's one filled action. White text, so the fill is chosen against that label rather than
/// inherited from the user's accent.
struct FilledControlStyle: ButtonStyle {

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.actionButton)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.actionButtonHorizontal)
            .frame(height: Spacing.controlHeight)
            .background(
                Color(nsColor: Self.fill),
                in: RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius)
            )
            .opacity(configuration.isPressed ? 0.75 : (isHovered ? 0.9 : 1))
            .onHover { isHovered = $0 }
            .contentShape(RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius))
    }

    /// 6.37:1 with a white label in light, 4.81:1 in dark.
    ///
    /// `Color.accentColor` is the obvious fill and it cannot carry that label: `controlAccentColor`
    /// measures 4.02:1 in both appearances, under the 4.5:1 floor for 12pt text. `linkColor` passes in
    /// light (5.26:1) and fails in dark (2.83:1).
    ///
    /// Hand-picked rather than accent-derived on purpose. A fill that follows the user's accent becomes
    /// unreadable the day that accent is yellow or graphite, and this is the one action in the window
    /// that has to stay legible.
    private static let fill = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.22, green: 0.44, blue: 0.80, alpha: 1)
            : NSColor(srgbRed: 0.15, green: 0.36, blue: 0.72, alpha: 1)
    }
}

// MARK: Bordered

/// A secondary action with a word on it.
struct BorderedControlStyle: ButtonStyle {

    let contrast: ColorSchemeContrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.actionButton)
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.actionButtonHorizontal)
            .frame(height: Spacing.controlHeight)
            .background(
                isHovered || configuration.isPressed
                    ? Color.primary.opacity(Opacity.controlHover(contrast))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius)
                    .stroke(Color.primary.opacity(Opacity.cardBorder(contrast)), lineWidth: 0.5)
            )
            .onHover { isHovered = $0 }
            .contentShape(RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius))
    }
}

// MARK: Glyph

/// An icon-only control.
struct GlyphControlStyle: ButtonStyle {

    let contrast: ColorSchemeContrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.controlGlyph)
            .foregroundStyle(isHovered || configuration.isPressed ? Color.primary : Foreground.muted)
            .frame(width: Spacing.controlHeight, height: Spacing.controlHeight)
            .background(
                isHovered || configuration.isPressed
                    ? Color.primary.opacity(Opacity.controlHover(contrast))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius)
            )
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
    }
}

// MARK: - GlyphControl

/// The hover target for an affordance that is *not* a button.
///
/// A detail row copies on tap along with the rest of the row, so its copy glyph cannot be a `Button`
/// without taking the gesture away from the row it sits in. This is the same 26pt square with the same
/// hover response, drawn rather than wired.
struct GlyphControl: View {

    let systemImage: String
    /// The favourite star is the one glyph that carries a state rather than inviting an action.
    var tint: Color? = nil
    var isActive: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(Typography.controlGlyph)
            .foregroundStyle(tint ?? (isHovered || isActive ? Foreground.action : Foreground.muted))
            .frame(width: Spacing.controlHeight, height: Spacing.controlHeight)
            .background(
                isHovered ? Color.primary.opacity(Opacity.controlHover(contrast)) : Color.clear,
                in: RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
