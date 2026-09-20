import SwiftUI

// MARK: - PasswordHistorySection

/// The previous passwords of a login item, collapsed by default.
///
/// **Collapsed by default, and it clears what it loaded when it closes.** Opening it is what
/// triggers the decryption — until then nothing has been decrypted at all (design D10).
///
/// **There is no reveal button yet.** The re-prompt gate that has to stand in front of one arrives
/// in wave C, and shipping the button first would mean shipping a control that shows a previous
/// password to anyone at the keyboard. The footnote says so rather than leaving the omission to be
/// guessed at, which is the same reason the health report states the check it does not run.
struct PasswordHistorySection: View {

    @ObservedObject var viewModel: PasswordHistoryViewModel

    /// Copies one value. Cleared on the configured interval by the caller, the same as every other
    /// copy in the app — see `VaultBrowserViewModel.copy`.
    let onCopy: (String) -> Void

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

                Text(L("Previous passwords stay masked. Revealing one will require confirming your master password."))
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

            Text(MaskedFieldState.maskedPlaceholder)
                .font(Typography.fieldValue.monospaced())
                .accessibilityIdentifier(AccessibilityID.PasswordHistory.value(index))

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
