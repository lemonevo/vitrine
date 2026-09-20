import SwiftUI

// MARK: - HealthReportView

/// The vault health report sheet.
///
/// **All five sections are always shown, including the ones that found nothing.** A section that
/// disappears when it is empty makes "checked, and clean" indistinguishable from "never checked" —
/// the same failure mode as a silently swallowed error. The count badge carries the answer instead.
///
/// The sheet states what it does *not* do as well. Compromised-password checking is absent on
/// purpose, and the note above the Done button says so and gives the reason, so the omission is
/// visible rather than assumed.
struct HealthReportView: View {

    @ObservedObject var viewModel: HealthReportViewModel

    /// Opens one item in the vault browser. The caller closes the report first — the selection has
    /// to land on a vault browser that is on screen.
    let onSelect: (String) -> Void

    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footer
        }
        .frame(width: 560, height: 560)
        .task { await viewModel.load() }
        .accessibilityIdentifier(AccessibilityID.Health.sheet)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Vault Health Report")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Checking the vault…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            failure(message)

        case .loaded(let report):
            VStack(alignment: .leading, spacing: 0) {
                banner(report)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(HealthCheck.allCases) { check in
                            section(check, findings: report.findings(for: check))
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    /// The one-line verdict. It is the only place the total appears, so a vault with 40 findings
    /// says 40 rather than making the user add up five badges.
    private func banner(_ report: VaultHealthReport) -> some View {
        let tint: Color = report.isClean ? .green : .orange

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: report.isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(report.isClean
                 ? L("Nothing to fix. All five checks passed.")
                 : L("Issues found: %d", report.totalFindings))
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.12)))
        .accessibilityIdentifier(report.isClean
                                 ? AccessibilityID.Health.cleanBanner
                                 : AccessibilityID.Health.summaryBanner)
    }

    private func section(_ check: HealthCheck, findings: [HealthFinding]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(check.displayName)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("\(findings.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(countTint(findings.count).opacity(0.15)))
                    .foregroundStyle(countTint(findings.count))
                    .accessibilityLabel(L("%d findings", findings.count))
                    .accessibilityIdentifier(AccessibilityID.Health.sectionCount(check.rawValue))

                Spacer(minLength: 0)
            }

            Text(check.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if findings.isEmpty {
                Text("No issues found.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                        findingRow(finding, check: check, index: index)
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Health.section(check.rawValue))
    }

    private func countTint(_ count: Int) -> Color {
        count == 0 ? .secondary : .orange
    }

    private func findingRow(_ finding: HealthFinding, check: HealthCheck, index: Int) -> some View {
        Button {
            onSelect(finding.itemId)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(finding.itemName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
        .help(L("Open this item"))
        .accessibilityLabel("\(finding.itemName), \(finding.detail)")
        .accessibilityHint(L("Opens this item in the vault"))
        .accessibilityIdentifier(AccessibilityID.Health.findingRow(check.rawValue, index))
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.Health.errorMessage)

            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .accessibilityIdentifier(AccessibilityID.Health.retryButton)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Compromised passwords are not checked. That check would require sending part of your password to a third party, which is what a self-hosted vault exists to avoid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier(AccessibilityID.Health.breachNote)

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityID.Health.doneButton)
            }
        }
        .padding(20)
    }
}
