import SwiftUI

// MARK: - VerificationCodesSheet

/// Every verification code in the vault, in one list.
///
/// A sheet rather than a pane or a toggle: codes on screen are codes an onlooker can read, and this is
/// a screen the user opens when something asks them for a code and closes once they have entered it.
/// Leaving it up for the rest of the session would leave every second factor visible.
struct VerificationCodesSheet: View {

    /// Builds the list. Taken as a closure and called in `.task`, rather than being built by the caller
    /// and handed in: a view model assigned in an `onChange` that fires *after* the sheet's content is
    /// evaluated renders blank, and `.sheet(item:)` was adopted elsewhere in this file for exactly that
    /// reason. Building here has neither problem.
    let makeViewModel: () -> VerificationCodesViewModel
    let onDismiss: () -> Void

    @State private var viewModel: VerificationCodesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                VerificationCodesContent(viewModel: viewModel, onDismiss: onDismiss)
            } else {
                // One vault read, so this is a frame or two — but a sheet that renders nothing at all
                // while it waits looks broken.
                ProgressView().controlSize(.small).padding(40)
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = makeViewModel()
        }
        .accessibilityIdentifier(AccessibilityID.VerificationCodes.sheet)
    }
}

// MARK: - VerificationCodesContent

/// The list itself.
///
/// **A separate type so that it can observe the view model.** Handing the view model to a function of
/// the sheet — which is what this was — makes `rows` a plain value: the sheet rendered once, with no
/// rows, and nothing invalidated it when they arrived. The view model was correct throughout, which is
/// why every unit test passed while the screen stayed empty.
private struct VerificationCodesContent: View {

    @ObservedObject var viewModel: VerificationCodesViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if viewModel.rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            VerificationCodeRowView(
                                row: row,
                                onCopy: { viewModel.copy(row) }
                            )
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 380)
            }

            Divider()
            footer
        }
        .frame(width: 420)
        // The rows own one timer each, so they start when the list appears and are released when it
        // goes. A dismissed sheet must not leave a vault's worth of timers deriving codes.
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "lock.shield")
                .accessibilityHidden(true)
            Text(L("Verification Codes"))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(20)
    }

    /// An empty vault of codes says so, and says where codes come from. An empty list would look like
    /// a loading failure.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("No verification codes"))
                .font(Typography.fieldValue)
            Text(L("Codes appear here for any login that has a one-time-code key stored on it."))
                .font(Typography.listSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .accessibilityIdentifier(AccessibilityID.VerificationCodes.emptyState)
    }

    private var footer: some View {
        HStack {
            Text(L("Codes are derived from each item's stored key. The key itself is never shown or copied."))
                .font(Typography.listSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L("Done"), action: onDismiss)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityID.VerificationCodes.doneButton)
        }
        .padding(20)
    }
}

// MARK: - VerificationCodeRowView

/// One row: what the item is, its code, and how long the code has left.
private struct VerificationCodeRowView: View {

    let row: VerificationCodeRow
    let onCopy: () -> Void

    /// Whether the code is on screen.
    ///
    /// **This deliberately differs from the detail pane.** There, a code is masked until the user
    /// reveals it, because they are looking at one item and a shoulder-surfer is one click from it.
    /// Here the opposite is true: the screen exists to show codes, and masking all of them would make
    /// it a list of names with extra steps.
    ///
    /// What is *not* relaxed is the re-prompt gate. An item the user marked as requiring the master
    /// password stays masked until it has been given — that is the user's explicit instruction about
    /// that item, and a convenience screen does not get to overrule it.
    private var isVisible: Bool { !row.gate.isGated || row.gate.isRevealed }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(Typography.fieldValue)
                if let username = row.username, !username.isEmpty {
                    Text(username)
                        .font(Typography.listSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isVisible {
                VerificationCodeCell(code: row.code, name: row.name, id: row.id, onCopy: onCopy)
            } else {
                Button {
                    // Only ever reached for a gated row — see `isVisible`. So this asks the gate, which
                    // raises the master-password sheet.
                    row.gate.request()
                } label: {
                    Label(L("Reveal"), systemImage: "eye")
                        .labelStyle(.titleAndIcon)
                        .font(Typography.listSubtitle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier(AccessibilityID.VerificationCodes.revealButton(row.id))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.VerificationCodes.row(row.id))
    }
}

// MARK: - VerificationCodeCell

/// The code, its countdown, and the copy control.
///
/// **Its own type because it has to observe the code's view model.** `VerificationCodeRowView` holds a
/// `VerificationCodeRow`, which is a value struct carrying a `let` to `TOTPCodeViewModel` — and a plain
/// `let` to an `ObservableObject` installs no subscription. The list therefore drew every row once,
/// when the sheet opened, and never redrew it: the seconds sat still, and worse, `displayCode` never
/// changed either, so a code that expired thirty seconds later stayed on screen as the current code.
/// The same trap the sheet's own content view was split out to avoid, one level down.
private struct VerificationCodeCell: View {

    @ObservedObject var code: TOTPCodeViewModel
    let name: String
    let id: String
    let onCopy: () -> Void

    var body: some View {
        Group {
            if let value = code.displayCode {
                cell(value)
            } else if code.isUnusable {
                Text(L("No code"))
                    .font(Typography.listSubtitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// The countdown is here as well as in the detail pane because a list is scanned across rows. It is
    /// the detail pane's own shape — ring plus a number — rather than a second one: what was here
    /// before was a thin bar with no number, and a bar that is a third full is a shape, not a time.
    /// Two screens counting the same thing down in two different ways is a thing the user has to learn
    /// twice.
    private func cell(_ digits: String) -> some View {
        HStack(spacing: 10) {
            Text(digits)
                .font(Typography.fieldValue.monospaced())
                .textSelection(.enabled)

            if let seconds = code.secondsRemaining {
                CountdownRing(fraction: code.remainingFraction)
                Text(L("%ds", seconds))
                    .font(Typography.utility.monospacedDigit())
                    .foregroundStyle(.secondary)
                    // Fixed width, so a code going from ten seconds left to nine does not slide the
                    // copy button sideways underneath the pointer.
                    .frame(width: Spacing.codesCountdownWidth, alignment: .trailing)
            }

            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help(L("Copy code"))
            .accessibilityLabel(L("Copy code"))
            .accessibilityIdentifier(AccessibilityID.VerificationCodes.copyButton(id))
        }
        // Announced as a sentence: a screen reader reaching a bare six-digit number has no way to know
        // what it belongs to. The visible seconds are part of that sentence, not a second element to
        // read.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@ code for %@, %d seconds left", digits, name, code.secondsRemaining ?? 0))
    }
}
