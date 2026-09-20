import Foundation

// MARK: - VaultExport

/// A finished export: the bytes to write, and what is in them.
///
/// **The bytes are plaintext.** Everything in this value is a secret the user has just agreed to
/// put on disk. It is held only long enough to be written and is never logged.
nonisolated struct VaultExport: Equatable, Sendable {

    /// The encoded document, ready to write.
    let data: Data

    /// The filename to offer in the save panel.
    let suggestedFilename: String

    /// How many items the file contains.
    let itemCount: Int

    /// How many of them belong to an organisation.
    ///
    /// Reported because the official individual export omits these, so a user who has used that
    /// client will not expect them — and a user who has not deserves to know the file is more
    /// complete than the one Bitwarden produces.
    let organisationItemCount: Int
}

// MARK: - ExportVaultUseCase

/// Serialises the decrypted vault into a Bitwarden-compatible unencrypted JSON document.
///
/// Returns the bytes; it does **not** write them. The file is written by an App-layer closure
/// wrapping `NSSavePanel`, which keeps the Presentation layer free of AppKit (Constitution §II)
/// and keeps this use case unit-testable without a file system.
protocol ExportVaultUseCase: Sendable {
    func execute() async throws -> VaultExport
}

nonisolated enum ExportVaultError: Error, LocalizedError, Equatable {

    /// There is nothing to export. Refused rather than writing an empty file: a zero-item backup
    /// that the user believes is a backup is worse than no backup.
    case emptyVault

    var errorDescription: String? {
        switch self {
        case .emptyVault:
            return L("There is nothing to export — the vault is empty.")
        }
    }
}
