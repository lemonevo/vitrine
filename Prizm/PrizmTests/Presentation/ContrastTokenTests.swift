import AppKit
import SwiftUI
import XCTest
@testable import Prizm

// MARK: - ContrastTokenTests

/// Measures the `Foreground` and type-tint tokens against the surfaces they are drawn on.
///
/// **Why this file exists.** `Foreground.muted` shipped as `primary.opacity(0.62)` with `6.20:1` written
/// beside it, and the number was wrong: `labelColor` is itself 84.7% opaque, so the two alphas compose
/// and the real figure was **4.31:1** — under the 4.5:1 floor the token was introduced to satisfy. The
/// arithmetic that caught it is here, so the next value has to survive it.
///
/// **Why the surfaces are literals.** `NSColor.windowBackgroundColor` resolves to pure white when read
/// outside a drawing context, which is the *most favourable* background for dark text: a test built on
/// it would pass at alphas the interface then fails. The surfaces below are the values the panes
/// actually paint — the card asset's two appearances, `textBackgroundColor` for the list, and a grey
/// window for the sidebar rather than the white the resolver reports.
@MainActor
final class ContrastTokenTests: XCTestCase {

    // MARK: Surfaces

    private struct Surface {
        let name: String
        let rgb: (Double, Double, Double)
    }

    private var lightSurfaces: [Surface] {
        [
            Surface(name: "card #FAFAFA",  rgb: (0.979, 0.979, 0.979)),
            Surface(name: "list white",    rgb: (1.000, 1.000, 1.000)),
            Surface(name: "window #ECECEC", rgb: (0.925, 0.925, 0.925)),
        ]
    }

    private var darkSurfaces: [Surface] {
        [
            Surface(name: "card #2C2C2C",   rgb: (0.173, 0.173, 0.173)),
            Surface(name: "list #1E1E1E",   rgb: (0.118, 0.118, 0.118)),
            Surface(name: "window #1E1E1E", rgb: (0.118, 0.118, 0.118)),
        ]
    }

    // MARK: Colour maths

    private func labelComponents(_ appearance: NSAppearance.Name) -> (r: Double, g: Double, b: Double, a: Double) {
        var out: (Double, Double, Double, Double) = (0, 0, 0, 1)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let s = NSColor.labelColor.usingColorSpace(.sRGB)!
            out = (s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent)
        }
        return out
    }

    private func luminance(_ p: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(p.0) + 0.7152 * linear(p.1) + 0.0722 * linear(p.2)
    }

    private func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        (max(luminance(a), luminance(b)) + 0.05) / (min(luminance(a), luminance(b)) + 0.05)
    }

    /// `fg` at `alpha` over `bg`, both already opaque.
    private func blend(_ fg: (Double, Double, Double), _ alpha: Double, _ bg: (Double, Double, Double)) -> (Double, Double, Double) {
        (fg.0 * alpha + bg.0 * (1 - alpha), fg.1 * alpha + bg.1 * (1 - alpha), fg.2 * alpha + bg.2 * (1 - alpha))
    }

    /// The rendered colour of `Foreground.muted` on `surface`: the token's alpha multiplied by
    /// `labelColor`'s own, which is the step the original measurement skipped.
    private func mutedOn(_ appearance: NSAppearance.Name, _ surface: Surface) -> Double {
        let label = labelComponents(appearance)
        let solid = (label.r, label.g, label.b)
        let effectiveAlpha = label.a * Foreground.mutedAlpha
        let fg = blend(solid, effectiveAlpha, surface.rgb)
        return ratio(fg, surface.rgb)
    }

    // MARK: Foreground.muted — text, floor 4.5:1

    /// The regression this test was written for.
    func test_mutedClearsTheSmallTextFloorInBothAppearances() {
        for (appearance, surfaces) in [(NSAppearance.Name.aqua, lightSurfaces), (.darkAqua, darkSurfaces)] {
            for surface in surfaces {
                let measured = mutedOn(appearance, surface)
                XCTAssertGreaterThanOrEqual(
                    measured, 4.5,
                    "Foreground.muted is \(String(format: "%.2f", measured)):1 on \(appearance == .aqua ? "light" : "dark") \(surface.name) — "
                    + "section labels, subtitles, counts and breadcrumbs are drawn at 10–13 pt and need 4.5:1"
                )
            }
        }
    }

    /// Guards the guard: if the compositing above ignored `labelColor`'s alpha, this would pass.
    func test_mutedAlphaIsNotTheValueThatFailedTheFloor() {
        let lightCard = lightSurfaces[0]
        let as062 = mutedOnComposed(alpha: 0.62, on: lightCard)
        XCTAssertLessThan(as062, 4.5, "0.62 is the value this file exists to reject; it measures \(as062)")
    }

    private func mutedOnComposed(alpha: Double, on surface: Surface) -> Double {
        let label = labelComponents(.aqua)
        return ratio(blend((label.r, label.g, label.b), label.a * alpha, surface.rgb), surface.rgb)
    }

    // MARK: Type tints — non-text glyphs, floor 3:1

    /// Every type glyph is drawn twice: bare in the sidebar, and on its own `typeChip` fill in the
    /// list and the detail header. The chip is the harder case because the tint lightens the surface
    /// it sits on, so it is measured rather than assumed.
    func test_typeTintsClearTheNonTextFloorOnTheirOwnChips() {
        let chipAlpha = Opacity.typeChip(.standard)

        for type in ItemType.allCases {
            let palette = type.tintComponents
            for (appearance, tint, surfaces) in [(NSAppearance.Name.aqua, palette.light, lightSurfaces),
                                                 (.darkAqua, palette.dark, darkSurfaces)] {
                let mode = appearance == .aqua ? "light" : "dark"
                for surface in surfaces {
                    let bare = ratio(tint, surface.rgb)
                    XCTAssertGreaterThanOrEqual(
                        bare, 3.0,
                        "\(type): \(String(format: "%.2f", bare)):1 bare on \(mode) \(surface.name)"
                    )
                    let chip = blend(tint, chipAlpha, surface.rgb)
                    let onChip = ratio(tint, chip)
                    XCTAssertGreaterThanOrEqual(
                        onChip, 3.0,
                        "\(type): \(String(format: "%.2f", onChip)):1 on its own \(chipAlpha) chip over \(mode) \(surface.name)"
                    )
                }
            }
        }
    }

    /// The point of the palette being per-appearance: one value that clears both is the exception, not
    /// the rule, and a single colour chosen for light fails dark and vice versa.
    func test_typeTintsDifferBetweenAppearances() {
        for type in ItemType.allCases {
            let c = type.tintComponents
            XCTAssertNotEqual(c.light.0, c.dark.0, "\(type) resolves to the same red in both appearances")
        }
    }

    // MARK: Foreground.favorite — the star

    func test_favoriteStarClearsTheNonTextFloor() {
        let palette = Foreground.favoriteComponents
        for (appearance, rgb, surfaces) in [(NSAppearance.Name.aqua, palette.light, lightSurfaces),
                                            (.darkAqua, palette.dark, darkSurfaces)] {
            let mode = appearance == .aqua ? "light" : "dark"
            for surface in surfaces {
                let measured = ratio(rgb, surface.rgb)
                XCTAssertGreaterThanOrEqual(
                    measured, 3.0,
                    "Foreground.favorite is \(String(format: "%.2f", measured)):1 on \(mode) \(surface.name) — "
                    + "the star is the only mark saying an item is favourited"
                )
            }
        }
    }

    /// The star was `Color.yellow` in the app *and* in the design mock, which was reviewed as a
    /// picture. A still image cannot report a ratio, so this is the measurement the review could not
    /// have made.
    func test_systemYellowWouldFailTheSameMeasurement() {
        var rgb: (Double, Double, Double) = (0, 0, 0)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            let s = NSColor.systemYellow.usingColorSpace(.sRGB)!
            rgb = (s.redComponent, s.greenComponent, s.blueComponent)
        }
        for surface in lightSurfaces {
            let measured = ratio(rgb, surface.rgb)
            XCTAssertLessThan(measured, 3.0,
                "system yellow measured \(String(format: "%.2f", measured)):1 on \(surface.name); if that is now true, correct DesignSystem.swift's comment")
        }
    }

    // MARK: Foreground.success — the sync dot

    func test_successDotClearsTheNonTextFloor() {
        let palette = Foreground.successComponents
        for (appearance, rgb, surfaces) in [(NSAppearance.Name.aqua, palette.light, lightSurfaces),
                                            (.darkAqua, palette.dark, darkSurfaces)] {
            let mode = appearance == .aqua ? "light" : "dark"
            for surface in surfaces {
                let measured = ratio(rgb, surface.rgb)
                XCTAssertGreaterThanOrEqual(
                    measured, 3.0,
                    "Foreground.success is \(String(format: "%.2f", measured)):1 on \(mode) \(surface.name) — "
                    + "the 6pt sync dot is the at-a-glance signal beside the label"
                )
            }
        }
    }

    /// `Color.green` is what the dot used to be, and it is the reason the token exists.
    func test_systemGreenWouldFailTheSameMeasurement() {
        var rgb: (Double, Double, Double) = (0, 0, 0)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            let s = NSColor.systemGreen.usingColorSpace(.sRGB)!
            rgb = (s.redComponent, s.greenComponent, s.blueComponent)
        }
        let onWindow = ratio(rgb, (0.925, 0.925, 0.925))
        XCTAssertLessThan(onWindow, 3.0, "system green measured \(onWindow):1 — if that changed, say so in DesignSystem.swift")
    }
}
