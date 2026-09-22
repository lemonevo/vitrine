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

    /// How many vault items the format could not carry.
    ///
    /// Zero for JSON, which holds all five item types. Non-zero for CSV, whose columns are login-shaped
    /// — and for CSV the official documentation says the unencrypted formats exclude cards,
    /// identities, passkeys and SSH keys, so the omission is the documented behaviour rather than a
    /// shortfall. Doing it **quietly** would not be: "I exported 400 items and the file has 300 rows"
    /// is a discrepancy the user must not have to count to discover.
    var omittedItemCount: Int = 0
}

// MARK: - VaultExportFormat

/// Which file format an export produces.
nonisolated enum VaultExportFormat: String, CaseIterable, Identifiable, Sendable {
    /// Bitwarden-compatible unencrypted JSON. Carries every item type.
    case json
    /// Bitwarden's CSV. Carries logins only — see `VaultExportCSV`.
    case csv

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .json: return L("JSON (all item types)")
        case .csv:  return L("CSV (logins only)")
        }
    }
}

// MARK: - ExportVaultUseCase

/// Serialises the decrypted vault into a Bitwarden-compatible unencrypted document, in either of the
/// two plaintext formats the official client offers.
///
/// Returns the bytes; it does **not** write them. The file is written by an App-layer closure
/// wrapping `NSSavePanel`, which keeps the Presentation layer free of AppKit (Constitution §II)
/// and keeps this use case unit-testable without a file system.
///
/// The defaulted parameter is what keeps the format a presentation choice: every existing call site
/// keeps compiling and keeps producing JSON.
protocol ExportVaultUseCase: Sendable {
    func execute(format: VaultExportFormat) async throws -> VaultExport
}

extension ExportVaultUseCase {
    /// The JSON export, which is what every call site predating the format choice wanted.
    func execute() async throws -> VaultExport { try await execute(format: .json) }
}

nonisolated enum ExportVaultError: Error, LocalizedError, Equatable {

    /// There is nothing to export. Refused rather than writing an empty file: a zero-item backup
    /// that the user believes is a backup is worse than no backup.
    case emptyVault

    /// The vault has items, but none of a type this format can carry — a vault of cards and SSH keys
    /// exported as CSV. Refused rather than written as a header row, for the same reason as
    /// `emptyVault`.
    case nothingInThisFormat

    var errorDescription: String? {
        switch self {
        case .emptyVault:
            return L("There is nothing to export — the vault is empty.")
        case .nothingInThisFormat:
            return L("This format cannot carry any of your items. CSV holds logins only — use JSON to export everything.")
        }
    }
}
