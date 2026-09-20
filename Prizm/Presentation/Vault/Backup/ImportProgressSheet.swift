import SwiftUI

// MARK: - ImportProgressSheet

/// Progress while an import runs.
///
/// `total` is 0 until the file has been read and counted, so the bar is indeterminate for that
/// first moment rather than showing a false "0 of 0".
struct ImportProgressSheet: View {

    let done: Int
    let total: Int

    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Importing…")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .accessibilityLabel(L("Import progress"))
                    .accessibilityValue(L("%d of %d items", done, total))
                Text(L("%d of %d items", done, total))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView()
                    .accessibilityLabel(L("Reading the file"))
                Text("Reading the file…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Items are created one at a time. Stopping keeps everything already imported.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Stop", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
