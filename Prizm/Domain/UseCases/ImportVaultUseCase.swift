import Foundation

// MARK: - ImportSummary

/// What an import actually did, item by item.
///
/// **Why this is a report and not a boolean.** An import is N independent `POST /api/ciphers`
/// requests, so a partial result is the normal outcome, not an edge case. Returning "success"
/// would be a lie the user cannot check; returning this lets the UI say exactly how many items
/// landed, how many were skipped and why, and how many the server rejected.
nonisolated struct ImportSummary: Equatable, Sendable {

    /// An item that was not imported because it cannot be represented here.
    struct Skip: Equatable, Sendable {
        let itemName: String
        let reason: String
    }

    /// An item that was not imported because the server rejected it.
    struct Failure: Equatable, Sendable {
        let itemName: String
        let reason: String
    }

    /// Items successfully created in the vault.
    var imported: Int = 0

    /// Items deliberately not imported, each with the reason.
    var skipped: [Skip] = []

    /// Items the server refused, each with the error.
    var failed: [Failure] = []

    /// Folders created because the file referenced a name the vault did not have.
    var foldersCreated: Int = 0

    /// Folders that could not be created. Items that referenced them were imported unfoldered
    /// rather than dropped — losing an item because its folder failed would be the wrong trade.
    var foldersFailed: Int = 0

    /// Imported items that arrived with organisation or collection membership, which is not
    /// carried over (design D4). Reported so the user is not surprised by where the items landed.
    var organisationMembershipDropped: Int = 0

    /// How many items the file contained.
    var total: Int { imported + skipped.count + failed.count }

    /// Whether anything at all was created. Drives whether the UI shows a success tone or not.
    var createdAnything: Bool { imported > 0 }
}

// MARK: - ImportVaultUseCase

/// Reads a Bitwarden unencrypted JSON export and creates the items it contains.
///
/// **Additive only.** Nothing is deleted, modified or merged, so importing the same file twice
/// produces two copies. That is what the official clients do and it is the only behaviour that
/// cannot lose data.
protocol ImportVaultUseCase: Sendable {

    /// - Parameter progress: called with `(processed, total)` after each item. `@Sendable` because
    ///   the run does not happen on the caller's actor.
    /// - Returns: what happened to each item. Never throws for a per-item failure — only for a
    ///   file that cannot be read at all.
    /// - Throws: `VaultExportDocumentError` when the file is not an unencrypted export.
    func execute(data: Data, progress: @Sendable (Int, Int) -> Void) async throws -> ImportSummary
}
