import SwiftUI

// MARK: - ImportReportSheet

/// What an import actually did.
///
/// **Why this is not a success alert.** An import is N independent `POST /api/ciphers` requests, so
/// a partial outcome is normal. A green tick would hide how much landed; this sheet states the
/// three counts and the reason behind every item that did not make it, because the user's next
/// action depends on which kind of failure it was — a skipped item can be re-created by hand, a
/// server failure can be retried.
struct ImportReportSheet: View {

    let summary: ImportSummary

    let onDone: () -> Void

    /// The most reasons to list per section. Beyond this the sheet would be a wall of text; the
    /// counts above still tell the truth about the total.
    private let maxReasonsShown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: summary.createdAnything ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(summary.createdAnything ? .green : .orange)
                    .accessibilityHidden(true)

                Text(summary.createdAnything ? "Import Complete" : "Nothing Was Imported")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Imported", summary.imported)
                if !summary.skipped.isEmpty { row("Skipped", summary.skipped.count) }
                if !summary.failed.isEmpty  { row("Failed",  summary.failed.count) }
                if summary.foldersCreated > 0 { row("Folders created", summary.foldersCreated) }
                if summary.foldersFailed > 0  { row("Folders not created", summary.foldersFailed) }
                if summary.organisationMembershipDropped > 0 {
                    row("Organisation membership not imported", summary.organisationMembershipDropped)
                }
            }

            if summary.organisationMembershipDropped > 0 {
                note(L("Items that belonged to an organisation were imported into your personal vault. The organisation and collection they came from cannot be recreated here."))
            }

            if !summary.skipped.isEmpty {
                reasonList(title: L("Skipped"), reasons: summary.skipped.map { ($0.itemName, $0.reason) })
            }

            if !summary.failed.isEmpty {
                reasonList(title: L("Failed"), reasons: summary.failed.map { ($0.itemName, $0.reason) })
            }

            note(L("Import only adds items. Nothing existing was changed or deleted."))

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func row(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .monospacedDigit()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func reasonList(title: String, reasons: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(reasons.prefix(maxReasonsShown).enumerated()), id: \.offset) { _, entry in
                Text("\(entry.0) — \(entry.1)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if reasons.count > maxReasonsShown {
                Text(L("…and %d more.", reasons.count - maxReasonsShown))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
