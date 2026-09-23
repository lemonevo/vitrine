import SwiftUI

// MARK: - ExportDoneSheet

/// Confirms where the export went, and repeats the one thing the user has to act on: the file is
/// plaintext and should be deleted when it is no longer needed.
///
/// The path is selectable rather than merely displayed. A save panel can be pointed anywhere, and
/// a user who chose a location by accident needs to be able to copy the path to go and find it.
struct ExportDoneSheet: View {

    let url: URL
    let itemCount: Int
    let organisationItemCount: Int
    /// Items the format could not carry. Non-zero for CSV.
    var omittedItemCount: Int = 0
    /// Items that could not be read at all, so no format could carry them. Non-zero for either
    /// format, and the reason a JSON export can be smaller than the vault it came from.
    var unreadableItemCount: Int = 0

    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("Export Complete")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            Text(L("%d items were written.", itemCount))
                .fixedSize(horizontal: false, vertical: true)

            if unreadableItemCount > 0 {
                Text(UnreadableItemsLabel.exportOmission(count: unreadableItemCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if omittedItemCount > 0 {
                Text(L("%d items were not written: this format holds logins only. Export as JSON to include everything.", omittedItemCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.Vault.omittedCount)
            }

            if organisationItemCount > 0 {
                Text(L("This includes %d items that belong to an organisation. The official Bitwarden export leaves those out.", organisationItemCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Saved to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(url.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("This file is not encrypted. Delete it when you no longer need it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
