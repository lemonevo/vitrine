import Foundation
import os.log

// MARK: - ExportVaultUseCaseImpl

/// Builds a Bitwarden-compatible unencrypted JSON export from the in-memory vault.
///
/// **Security.** The output contains every password in the vault in plaintext, plus every TOTP
/// seed and every previous password. It is produced only after the user has confirmed the consent
/// sheet, it is written by the App layer with owner-only permissions, and nothing about it is
/// logged — the log records the item count and nothing else (Constitution §V, §VII).
///
/// **It never writes.** Writing is the caller's job, so this type has no file-system dependency
/// and can be tested without touching disk.
nonisolated struct ExportVaultUseCaseImpl: ExportVaultUseCase {

    private let vault: any VaultRepository

    private static let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "VaultExport")

    init(vault: any VaultRepository) {
        self.vault = vault
    }

    func execute(format: VaultExportFormat) async throws -> VaultExport {
        let items = try await vault.allItems()
        guard !items.isEmpty else { throw ExportVaultError.emptyVault }

        let folders = try await vault.folders()

        // Password history is decrypted only for the items that actually have some, and only here.
        // Most items have none, so this is one cheap check per item rather than a decrypt pass over
        // the whole vault. A history that fails to decrypt degrades to "no history" for that item
        // rather than failing the export: an unreadable history is not a reason to refuse the user
        // a backup of everything else.
        var history: [String: [PasswordHistoryEntry]] = [:]
        for item in items where !item.preserved.passwordHistory.isEmpty {
            do {
                history[item.id] = try await vault.passwordHistory(for: item.id)
            } catch {
                Self.logger.error("Password history skipped during export for cipher \(item.id, privacy: .public)")
            }
        }

        let document = VaultExportDocument(items: items, folders: folders, passwordHistory: history)

        let organisationItemCount = items.filter { $0.organizationId != nil }.count

        switch format {
        case .csv:
            // Rendered off the caller's actor: this writes the whole vault into one string, and
            // `-default-isolation MainActor` means a `nonisolated struct`'s synchronous body runs on
            // whichever actor called it — so this was vault-sized string work on the thread drawing
            // the progress sheet.
            let rendered = try await offMain(document) { VaultExportCSV.serialise($0) }
            // A header-only file is refused for the same reason an empty JSON vault is: a file the user
            // believes is a backup, and which restores nothing.
            guard rendered.omittedCount < items.count else {
                throw ExportVaultError.nothingInThisFormat
            }
            Self.logger.info("CSV export built: \(items.count - rendered.omittedCount, privacy: .public) row(s), \(rendered.omittedCount, privacy: .public) item(s) omitted")
            return VaultExport(
                data: Data(rendered.csv.utf8),
                suggestedFilename: Self.filename(format: .csv),
                itemCount: items.count - rendered.omittedCount,
                organisationItemCount: organisationItemCount,
                omittedItemCount: rendered.omittedCount
            )

        case .json:
            return try await jsonExport(
                document: document, items: items, folders: folders,
                organisationItemCount: organisationItemCount
            )
        }
    }

    private func jsonExport(
        document: VaultExportDocument,
        items: [VaultItem],
        folders: [Folder],
        organisationItemCount: Int
    ) async throws -> VaultExport {
        // Encoded off the caller's actor — see the CSV branch above for why a `nonisolated struct`
        // does not by itself keep this off the main thread.
        //
        // `.withoutEscapingSlashes` is not cosmetic: without it every `https://…` in the file is
        // written as `https:\/\/…`. That is valid JSON and every parser reads it, but it makes the
        // file unreadable to a human trying to verify their own backup, and it differs from what
        // the reference implementation produces.
        // `.sortedKeys` makes the output deterministic, so two exports of the same vault differ
        // only where the vault does.
        let data = try await offMain(document) { document in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(document)
        }

        Self.logger.info("JSON export built: \(items.count, privacy: .public) items, \(folders.count, privacy: .public) folders")

        return VaultExport(
            data: data,
            suggestedFilename: Self.filename(format: .json),
            itemCount: items.count,
            organisationItemCount: organisationItemCount
        )
    }

    /// `prizm_export_YYYYMMDDHHmmss.json`.
    ///
    /// The time is included, not just the date, so that two exports in one session do not offer
    /// the same name and silently overwrite the first file — which is the one a user is most
    /// likely to do while checking that the feature works.
    ///
    /// The shape mirrors the reference's `bitwarden_export_<timestamp>.json`.
    static func filename(format: VaultExportFormat, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        // The extension follows the format: a `.csv` containing JSON, or the reverse, is the kind of
        // thing a user would reasonably not think to check.
        return "prizm_export_\(formatter.string(from: now)).\(format.fileExtension)"
    }
}
