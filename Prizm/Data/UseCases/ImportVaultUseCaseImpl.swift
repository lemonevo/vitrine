import Foundation
import os.log

// MARK: - ImportVaultUseCaseImpl

/// Creates vault items from a Bitwarden unencrypted JSON export.
///
/// **Sequential, not parallel.** `POST /api/ciphers` is the only creation endpoint, and firing
/// five hundred of them concurrently would look like an attack to any rate limiter — and would
/// make a partial failure impossible to attribute. One at a time is slower and correct.
///
/// **It continues past a failure.** The same reasoning as `EmptyTrashUseCase`: N independent
/// requests produce a partial outcome, and stopping halfway leaves the user unable to tell how
/// much landed. Every outcome is recorded and reported.
///
/// **It is cancellable.** The loop checks `Task.isCancelled` and breaks, returning the partial
/// summary. The items already created stay — an import is additive, so stopping is always safe.
nonisolated struct ImportVaultUseCaseImpl: ImportVaultUseCase {

    private let vault: any VaultRepository

    private static let logger = Logger(subsystem: "com.prizm", category: "VaultImport")

    init(vault: any VaultRepository) {
        self.vault = vault
    }

    func execute(data: Data, progress: @Sendable (Int, Int) -> Void) async throws -> ImportSummary {
        let document = try VaultExportDocument.decode(from: data)
        let total    = document.items.count

        var summary = ImportSummary()
        progress(0, total)

        guard total > 0 else { return summary }

        let folderIdsByName = await resolveFolders(for: document, summary: &summary)
        let now = Date()

        for (index, item) in document.items.enumerated() {
            // Checked before each item rather than mid-request: an import that stops between
            // items always leaves a consistent vault.
            if Task.isCancelled { break }

            // Runs even when the iteration ends in `continue`, so the progress count cannot
            // stall on a skipped item.
            defer { progress(index + 1, total) }

            let displayName = Self.displayName(for: item)

            do {
                let draft = try document.makeDraft(from: item,
                                                   folderIdsByName: folderIdsByName,
                                                   now: now)
                _ = try await vault.create(draft)
                summary.imported += 1
                if item.organizationId != nil || !(item.collectionIds ?? []).isEmpty {
                    summary.organisationMembershipDropped += 1
                }
            } catch let error as VaultExportDocumentError {
                // A skip is a decision, not a fault: the item cannot be represented here.
                summary.skipped.append(.init(itemName: displayName,
                                             reason: error.errorDescription ?? L("Unsupported item.")))
            } catch {
                // A failure is the server's answer. Kept separate from a skip so the report can
                // distinguish "we chose not to" from "the server said no".
                summary.failed.append(.init(itemName: displayName,
                                            reason: error.localizedDescription))
            }
        }

        Self.logger.info("Import finished: \(summary.imported, privacy: .public) imported, \(summary.skipped.count, privacy: .public) skipped, \(summary.failed.count, privacy: .public) failed")
        return summary
    }

    // MARK: - Folders

    /// Maps each folder name the file references to a folder id on this server, creating the ones
    /// that do not exist yet.
    ///
    /// Matching is case-insensitive and **first match wins**: if the vault already has both "Work"
    /// and "work", an imported item goes to whichever the vault lists first rather than creating a
    /// third. Creating a duplicate because of letter case would be the more surprising outcome.
    ///
    /// A folder that cannot be created is counted, not thrown: the items that referenced it are
    /// imported unfoldered, which is recoverable, where refusing the whole import is not.
    private func resolveFolders(for document: VaultExportDocument,
                                summary: inout ImportSummary) async -> [String: String] {
        var byName: [String: String] = [:]
        if let existing = try? await vault.folders() {
            for folder in existing where byName[folder.name.lowercased()] == nil {
                byName[folder.name.lowercased()] = folder.id
            }
        }

        for name in document.referencedFolderNames where byName[name.lowercased()] == nil {
            do {
                let created = try await vault.createFolder(name: name)
                byName[name.lowercased()] = created.id
                summary.foldersCreated += 1
            } catch {
                summary.foldersFailed += 1
                Self.logger.error("Folder could not be created during import: \(name, privacy: .public)")
            }
        }

        return byName
    }

    // MARK: - Helpers

    /// The name to show in the report. An item the export wrote with a blank name is reported as
    /// unnamed rather than as an empty row the user cannot identify.
    private static func displayName(for item: ExportItem) -> String {
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("(unnamed)") : trimmed
    }
}
