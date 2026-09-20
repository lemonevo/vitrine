import Foundation

// MARK: - GenerateVaultHealthReportUseCaseImpl

/// Reads the decrypted vault and runs the five checks over it.
///
/// The only thing this adds to `VaultHealthReport.make` is the vault read: the analysis is pure and
/// stays there, so the checks are testable without a repository and this type stays thin enough to
/// have nothing worth testing beyond the wiring.
nonisolated struct GenerateVaultHealthReportUseCaseImpl: GenerateVaultHealthReportUseCase {

    private let vault: any VaultRepository
    private let estimator: PasswordStrengthEstimator
    /// The clock, injected so a test can put the staleness boundary where it wants it.
    private let now: @Sendable () -> Date

    init(vault: any VaultRepository,
         estimator: PasswordStrengthEstimator = .application,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.vault = vault
        self.estimator = estimator
        self.now = now
    }

    func execute() async throws -> VaultHealthReport {
        let items = try await vault.allItems()
        return VaultHealthReport.make(from: items, estimator: estimator, now: now())
    }
}
