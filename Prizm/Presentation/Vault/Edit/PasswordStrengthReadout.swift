import SwiftUI

// MARK: - PasswordStrengthReadout

/// The single place a strength score is drawn, so the generator popover and the login form cannot
/// drift apart in wording or in colour.
///
/// **It says "estimate", and that is a requirement rather than a style choice.** The score comes
/// from a local guess-count model with 609 common passwords behind it — enough to steer someone
/// away from `Password1!`, not a verdict on whether a password is safe, and not a breach check.
/// `PasswordStrengthEstimator` documents what it does and does not model.
struct PasswordStrengthReadout: View {

    /// `nil` when there is nothing to score — an empty field, or a generation that failed.
    ///
    /// Nothing is drawn in that case. An empty password has no weakness to report, and a readout
    /// that says "very weak" before the user has typed anything reads as an accusation.
    let estimate: StrengthEstimate?

    /// Accessibility identifier. Defaults to the generator's; the login form passes its own so a
    /// test can tell the two readouts apart.
    var identifier: String = AccessibilityID.Generator.strengthReadout

    /// The scale is five points wide, taken from the enum rather than written as `5` so a new case
    /// cannot leave the bar one segment short.
    private static var segmentCount: Int { PasswordStrength.allCases.count }

    @ViewBuilder
    var body: some View {
        if let estimate {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    segments(for: estimate.score)
                    Text(L("Estimated strength: %@", estimate.score.displayName))
                        .font(Typography.utility)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                if let weakness = estimate.weakness {
                    Text(weakness)
                        .font(Typography.utility)
                        .foregroundStyle(.secondary)
                }
            }
            .help(L("Estimated from the patterns this app recognises — repeated characters, common passwords, sequences and dates. It is not a breach check, and no password is sent anywhere to produce it."))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(for: estimate))
            .accessibilityIdentifier(identifier)
        }
    }

    // MARK: - Bar

    /// Five capsules, filled up to the score.
    ///
    /// Colour carries the same information as the label, so it is redundant on purpose: the label
    /// is the accessible channel and the colour is the glanceable one. Nothing here is the *only*
    /// signal — colour-blind users get the words, and VoiceOver gets the combined label below.
    @ViewBuilder
    private func segments(for score: PasswordStrength) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index <= score.rawValue
                          ? Self.tint(for: score)
                          : Color.secondary.opacity(0.25))
                    .frame(width: 14, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private static func tint(for score: PasswordStrength) -> Color {
        switch score {
        case .veryWeak:   return .red
        case .weak:       return .orange
        case .fair:       return .yellow
        case .strong:     return .green
        case .veryStrong: return .green
        }
    }

    // MARK: - Accessibility

    /// The bar is hidden from VoiceOver, so the score and the weakness have to be spoken here.
    private func accessibilityText(for estimate: StrengthEstimate) -> String {
        guard let weakness = estimate.weakness else {
            return L("Estimated strength: %@", estimate.score.displayName)
        }
        return L("Estimated strength: %@. %@", estimate.score.displayName, weakness)
    }
}
