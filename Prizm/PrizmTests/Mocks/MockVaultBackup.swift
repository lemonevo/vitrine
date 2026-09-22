import Foundation
@testable import Prizm

// MARK: - Vault backup doubles
//
// Shared because six suites construct a `VaultBrowserViewModel`, and every one of them has to
// supply the backup dependencies even when it is testing something else entirely. Duplicating
// these in each file would be six copies of the same twenty lines.

/// Returns a fixed payload and records that it was asked.
@MainActor
final class MockExportVaultUseCase: ExportVaultUseCase {

    private(set) var callCount = 0
    /// The format the last call asked for, so a suite can assert the sheet's choice reached here.
    private(set) var lastFormat: VaultExportFormat?

    /// The result to return. Defaults to a one-item export so a suite that only wants the sheet to
    /// advance does not have to configure anything.
    var stubbedResult = VaultExport(
        data: Data("{}".utf8),
        suggestedFilename: "prizm_export_test.json",
        itemCount: 1,
        organisationItemCount: 0
    )

    var stubbedError: Error?

    func execute(format: VaultExportFormat) async throws -> VaultExport {
        lastFormat = format
        callCount += 1
        if let stubbedError { throw stubbedError }
        return stubbedResult
    }
}

/// Reports a fixed summary and can fire the progress callback, so a suite can assert on the
/// progress sheet without a real import.
@MainActor
final class MockImportVaultUseCase: ImportVaultUseCase {

    private(set) var callCount = 0
    /// The format the last call asked for, so a suite can assert the sheet's choice reached here.
    private(set) var lastFormat: VaultExportFormat?
    private(set) var lastData: Data?

    var stubbedSummary = ImportSummary()
    var stubbedError: Error?

    /// Progress values to emit, in order, before returning.
    var stubbedProgress: [(Int, Int)] = []

    /// Set by a suite that wants to observe the run being cancelled mid-flight.
    var onExecute: (() -> Void)?

    func execute(data: Data, progress: @Sendable (Int, Int) -> Void) async throws -> ImportSummary {
        callCount += 1
        lastData = data
        onExecute?()
        for step in stubbedProgress { progress(step.0, step.1) }
        if let stubbedError { throw stubbedError }
        return stubbedSummary
    }
}
