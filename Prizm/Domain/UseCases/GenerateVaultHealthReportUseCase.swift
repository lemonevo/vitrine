import Foundation

// MARK: - GenerateVaultHealthReportUseCase

/// Produces the vault health report.
///
/// The analysis itself is a pure function — `VaultHealthReport.make` — and this exists to give the
/// presentation layer a vault-shaped entry point. It also keeps the estimator and the clock out of
/// the view, so the staleness boundary can be pinned in a test instead of being decided by whatever
/// the machine's calendar says at the moment the sheet opens.
///
/// **No network.** The report is computed from the decrypted vault already in memory, so it is
/// available on a server with no internet access at all (design D6).
protocol GenerateVaultHealthReportUseCase: Sendable {
    func execute() async throws -> VaultHealthReport
}
