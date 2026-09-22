import SwiftUI

/// Provides contrast-aware opacity values that increase when the user enables
/// "Increase contrast" in System Settings → Accessibility → Display.
///
/// Usage:
/// ```swift
/// @Environment(\.colorSchemeContrast) private var contrast
/// // ...
/// .background(Color.yellow.opacity(Opacity.bannerBackground(contrast)))
/// ```
enum Opacity {
    static func bannerBackground(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.5 : 0.35
    }

    static func cardBorder(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.2 : 0.12
    }

    static func trashBanner(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.3 : 0.2
    }

    static func errorBanner(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.3 : 0.2
    }

    static func dropTarget(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.4 : 0.25
    }

    // MARK: - Vault redesign tints

    /// The type-tinted chip behind an item row's icon and behind the detail header's icon.
    static func typeChip(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.28 : 0.16
    }

    /// The hairline separating item rows.
    static func hairline(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.22 : 0.12
    }

    /// The edge of the authentication card.
    ///
    /// Stronger than the vault hairlines on purpose: in dark aqua the card's fill sits only a few
    /// levels off the window background and the drop shadow is invisible, so the edge is the only
    /// thing saying "this is a panel". At the 0.12 a row divider can use, it disappears.
    static func authCardBorder(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.40 : 0.20
    }
}
