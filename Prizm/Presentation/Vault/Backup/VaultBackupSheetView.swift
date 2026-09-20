import SwiftUI

// MARK: - VaultBackupSheetView

/// Renders whichever backup surface is current.
///
/// One entry point for the four sheets so `VaultBrowserView` gains a single `.sheet` modifier
/// rather than four, and so the switch lives next to the enum it switches on.
struct VaultBackupSheetView: View {

    let sheet: VaultBackupSheet

    /// The vault-wide item count, shown on the consent sheet so the number is concrete.
    let itemCount: Int

    /// Closes the sheet. Stops an in-flight import first.
    let onDismiss: () -> Void

    /// Runs the export, after the consent sheet has been confirmed.
    let onConfirmExport: () -> Void

    var body: some View {
        switch sheet {
        case .exportConsent:
            ExportConsentSheet(
                itemCount: itemCount,
                onCancel:   onDismiss,
                onConfirm:  onConfirmExport
            )

        case .exportDone(let url, let exportedItems, let organisationItems):
            ExportDoneSheet(
                url: url,
                itemCount: exportedItems,
                organisationItemCount: organisationItems,
                onDone: onDismiss
            )

        case .importing(let done, let total):
            ImportProgressSheet(done: done, total: total, onCancel: onDismiss)

        case .importReport(let summary):
            ImportReportSheet(summary: summary, onDone: onDismiss)
        }
    }
}
