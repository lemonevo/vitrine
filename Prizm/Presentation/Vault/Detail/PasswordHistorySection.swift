import SwiftUI

// MARK: - PasswordHistorySection

/// The previous passwords of a login item, collapsed by default.
///
/// **Collapsed by default, and it clears what it loaded when it closes.** Opening it is what
/// triggers the decryption — until then nothing has been decrypted at all (design D10).
///
/// **Revealing is gated; copying is not.** Revealing a previous password is one of the five
/// disclosures the spec puts behind the master password, so it goes through `gate`. Copying one is
/// not on that list, and it is no more exposed than copying the *current* password, which the
/// detail pane has always allowed — see the wave B note on that decision.
struct PasswordHistorySection: View {

    @ObservedObject var viewModel: PasswordHistoryViewModel

    /// Copies one value. Cleared on the configured interval by the caller, the same as every other
    /// copy in the app — see `VaultBrowserViewModel.copy`.
    let onCopy: (String) -> Void

    /// Decides whether a previous password may be shown. Wired for every item, protected or not:
    /// for an unprotected item the gate answers immediately, which keeps this view from having a
    /// second, local reveal state that ignores the gate.
    var gate: RevealGateBinding = .none

    @State private var isExpanded = false

    var body: some View {
        DetailSectionCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                content
                    .padding(.top, 6)
            } label: {
                HStack(spacing: 6) {
                    Text(L("Password history"))
                        .font(.headline)

                    if let count = viewModel.entryCount {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L("%d entries", count))
                            .accessibilityIdentifier(AccessibilityID.PasswordHistory.countBadge)
                    }
                }
            }
            .padding(.horizontal, Spacing.rowHorizontal)
            .padding(.vertical, 14)
            .accessibilityIdentifier(AccessibilityID.PasswordHistory.section)
        }
        .onChange(of: isExpanded) { _, expanded in
            // Expanding is the request; collapsing is the discard. Both live here rather than in
            // the view model so the "nothing is held while closed" rule is visible at the one place
            // that decides whether the section is open.
            if expanded {
                Task { await viewModel.load() }
            } else {
                viewModel.clear()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(AccessibilityID.PasswordHistory.progress)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.PasswordHistory.errorMessage)

        case .loaded(let entries):
            VStack(alignment: .leading, spacing: 6) {
                if entries.isEmpty {
                    Text(L("No previous passwords recorded."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.PasswordHistory.emptyState)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        row(entry, index: index)
                    }
                }

                // Only promise a prompt when one will actually appear. After the password has been
                // given once this session the reveal is instant, and a footnote still promising a
                // prompt would be describing a gate that is already open.
                Text(gate.requiresPrompt
                     ? L("Previous passwords stay masked. Revealing one will require confirming your master password.")
                     : L("Previous passwords stay masked until you reveal them."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.PasswordHistory.revealNote)
            }
        }
    }

    private func row(_ entry: PasswordHistoryEntry, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dateText(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 8)

            Text(gate.isRevealed ? entry.password : MaskedFieldState.maskedPlaceholder)
                .font(Typography.fieldValue.monospaced())
                .accessibilityIdentifier(AccessibilityID.PasswordHistory.value(index))

            Button {
                gate.request()
            } label: {
                Image(systemName: gate.isRevealed ? "eye.slash" : "eye")
                    .imageScale(.medium)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(gate.isRevealed ? L("Hide") : L("Reveal"))
            .accessibilityLabel(gate.isRevealed ? L("Hide this previous password")
                                                : L("Reveal this previous password"))
            .accessibilityIdentifier(AccessibilityID.PasswordHistory.revealButton(index))

            Button {
                onCopy(entry.password)
            } label: {
                Image(systemName: "doc.on.doc")
                    .imageScale(.medium)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(L("Copy"))
            .accessibilityLabel(L("Copy this previous password"))
            .accessibilityIdentifier(AccessibilityID.PasswordHistory.copyButton(index))
        }
    }

    private func dateText(_ entry: PasswordHistoryEntry) -> String {
        guard let date = entry.lastUsedDate else { return L("Unknown date") }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
    }
}
