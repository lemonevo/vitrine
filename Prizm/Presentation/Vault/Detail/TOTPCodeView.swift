import SwiftUI

// MARK: - TOTPCodeView

/// The current one-time code for a login item, and how long it remains valid.
///
/// **The row shows a derived code and never the stored key.** `LoginContent.totp` is the
/// long-lived shared secret — anyone who reads it can generate valid codes forever. It reaches the
/// view model and goes no further: the value on screen, and the value that goes on the clipboard,
/// are both the derived code. That distinction is the whole of `FEATURE-GAP-ANALYSIS.md` §2.1,
/// where `Item ▸ Copy Code` put the secret itself on the clipboard.
///
/// **Masked until revealed, and gated when the item is.** The password row directly above behaves
/// this way, and a live code shown openly beside it would be a second, unexamined rule about which
/// secrets may be shown — a worse one, since a live code is what an attacker at the keyboard
/// actually wants. The masking rule is not re-implemented: the value goes through
/// `MaskedFieldState`, whose `displayValue` is already the tested answer to "what do we print".
///
/// **No countdown while masked** (design D3). A timer ticking beside eight bullets is a timer for
/// something the user cannot see, and it leaks the step boundary — the one fact here worth
/// something to somebody watching the screen.
///
/// **No Option-key peek** (design D6). Revealing is what starts the countdown, and the countdown is
/// the reason to reveal; a peek would show a code with no indication of how long it lasts, which is
/// the one thing this row exists to add.
struct TOTPCodeView: View {

    @ObservedObject var viewModel: TOTPCodeViewModel

    /// The master-password gate for this row, for the items it covers.
    var gate: RevealGateBinding = .none

    /// Copies a value, ungated. Nil means the row offers no copy control.
    var onCopy: ((String) -> Void)? = nil

    /// The local reveal state, used only for an item the gate does not cover.
    @State private var isRevealedLocally = false
    @State private var isHovered = false
    @State private var showCopied = false

    /// The row's own name, used for the reveal control's label.
    private static var label: String { L("Verification Code") }

    /// Whether the code is on screen. When the gate covers the row, the gate decides; otherwise the
    /// local toggle does.
    private var isRevealed: Bool {
        gate.isGated ? gate.isRevealed : isRevealedLocally
    }

    /// What to print, routed through `MaskedFieldState` so the masking rule is the tested one
    /// rather than a second implementation of it.
    private var displayValue: String {
        MaskedFieldState(value: viewModel.displayCode ?? "", isRevealed: isRevealed).displayValue
    }

    /// Whether there is a code to copy. Not the same as "revealed": the password row above can be
    /// copied while masked, and this row follows it.
    private var hasCode: Bool { viewModel.copyValue != nil }

    var body: some View {
        HStack(spacing: 0) {
            DetailFieldLabel(text: Self.label)

            if viewModel.isUnusable {
                unusableValue
            } else {
                codeValue
                Spacer(minLength: Spacing.detailRowGap)
                copyAffordance
                revealButton
            }
        }
        .padding(.vertical, Spacing.detailRowVertical)
        .padding(.horizontal, Spacing.detailRowHorizontal)
        .contentShape(Rectangle())
        .onTapGesture { copyCode() }
        .onHover { hovering in
            optionalAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityIdentifier(AccessibilityID.TOTP.row)
        // The clock runs only while the row is on screen. `onAppear`/`onDisappear` rather than
        // `.task`, because starting a timer is not work that finishes — the row is here, or it is
        // not, and the second case has to stop the timer rather than wait for a task to complete.
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        // The row is reused across a selection change — and across an edit that replaces the stored
        // key — so `onAppear` does not fire for the next view model and it would never be started.
        // Keyed on the instance rather than on `itemId`, because a replaced key for the same item is
        // a new view model with the same id. The reveal state is dropped at the same time: it
        // belongs to the item, not to the row (FR-027).
        .onChange(of: ObjectIdentifier(viewModel)) { _, _ in
            isRevealedLocally = false
            showCopied = false
            viewModel.start()
        }
    }

    // MARK: - Value

    /// The code, or the eight bullets while it is hidden.
    ///
    /// Masked shows the bullets and nothing else — no countdown, see the type comment. Revealed adds
    /// the ring and the seconds beside the digits, so the number that answers "how long do I have"
    /// sits with the number the user is about to type.
    @ViewBuilder
    private var codeValue: some View {
        if isRevealed {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.badgeHorizontal) {
                Text(displayValue)
                    .font(Typography.totpCode)
                    .textSelection(.enabled)
                    // Spelled out digit by digit: read as a number, a six-digit code comes out as
                    // "one hundred twenty-three thousand…", which is not what the user needs to
                    // transcribe. The countdown is a separate element so that the code's announcement
                    // does not change as the seconds tick.
                    .accessibilityLabel(Self.spelledOut(viewModel.copyValue))
                    .accessibilityIdentifier(AccessibilityID.TOTP.value)

                if let seconds = viewModel.secondsRemaining {
                    CountdownRing(fraction: viewModel.remainingFraction)
                    Text(L("%ds", seconds))
                        .font(Typography.utility.monospacedDigit())
                        .foregroundStyle(Foreground.muted)
                        .accessibilityLabel(L("%d seconds remaining", seconds))
                        .accessibilityIdentifier(AccessibilityID.TOTP.countdown)
                }
            }
        } else {
            Text(MaskedFieldState.maskedPlaceholder)
                .font(Typography.detailFieldValue.monospaced())
                .accessibilityLabel(L("%@ hidden", Self.label))
                .accessibilityIdentifier(AccessibilityID.TOTP.maskedValue)
        }
    }

    /// What the row says when the stored key yields no code.
    ///
    /// Shown rather than hidden: the key *is* stored, the edit form already warns that it produces
    /// nothing, and a missing row reads as "this item has no authenticator key" — a different claim,
    /// and the one that makes a user give up on the item (design D5).
    private var unusableValue: some View {
        Text(L("This key will not produce a code."))
            .font(Typography.detailFieldValue)
            .foregroundStyle(Foreground.muted)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AccessibilityID.TOTP.unusable)
    }

    /// The trailing copy control, visible without hovering — the same rule the field rows follow.
    ///
    /// Shown only once the code is revealed. Beside eight bullets it asked what it copied, and the
    /// answer — a code nobody can see — is not something to discover after the click. Revealing is one
    /// press away, and the row itself still copies either way.
    @ViewBuilder
    private var copyAffordance: some View {
        if hasCode, isRevealed {
            if showCopied {
                Text(L("copied"))
                    .font(Typography.utility)
                    .textCase(.uppercase)
                    .foregroundStyle(Foreground.action)
                    .transition(.opacity)
            } else {
                Image(systemName: "doc.on.doc")
                    .imageScale(.medium)
                    .foregroundStyle(isHovered ? Foreground.action : Foreground.muted)
                    .accessibilityLabel(L("Copy %@", Self.label))
            }
        }
    }

    // MARK: - Controls

    private var revealButton: some View {
        Button {
            if gate.isGated {
                // The gate decides, and it toggles: hiding again is always allowed, and
                // re-revealing does not re-prompt because the grant outlives the reveal.
                gate.request()
            } else {
                isRevealedLocally.toggle()
            }
        } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .imageScale(.medium)
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .help(isRevealed ? L("Hide") : L("Reveal"))
        .accessibilityLabel(isRevealed ? L("Hide %@", Self.label) : L("Reveal %@", Self.label))
        .accessibilityIdentifier(AccessibilityID.TOTP.revealButton)
    }

    private func copyCode() {
        guard let value = viewModel.copyValue else { return }
        // Tapping the row copies it, so a protected row's tap has to take the same route as the
        // `Copy Code` command. Routing only the menu item would leave the gate walkable in one
        // click — and the value copied is the **code**, never the stored key.
        if gate.isGated {
            gate.copyGated?(value)
            return
        }
        guard let onCopy else { return }
        onCopy(value)
        optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = false }
        }
    }

    // MARK: - Pure logic

    /// The code with its digits separated, for the accessibility label. `nil` becomes empty.
    nonisolated static func spelledOut(_ code: String?) -> String {
        guard let code else { return "" }
        return code.map { String($0) }.joined(separator: " ")
    }
}

// MARK: - CountdownRing

/// The step's remaining time, as a ring that empties as the code ages.
///
/// The fraction *remaining*, not elapsed: a bar that fills up as a code approaches expiry reads as
/// "almost ready", which is the opposite of what it means.
///
/// Shared with the verification-codes list so the two screens say the same thing the same way. It
/// lives here, beside its first user, rather than in a file of its own — the ring is the TOTP
/// countdown's shape, and nothing that does not count a TOTP step should be reaching for it.
struct CountdownRing: View {

    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: Spacing.totpRingLineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: Spacing.totpRingLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Spacing.totpRing, height: Spacing.totpRing)
        .animation(.linear(duration: 1), value: fraction)
        .accessibilityHidden(true)
    }
}
