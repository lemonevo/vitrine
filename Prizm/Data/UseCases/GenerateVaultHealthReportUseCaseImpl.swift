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
        // Off the caller's actor. The analysis is pure, but `PasswordStrengthEstimator.estimate` is
        // O(n²) in the length of each password and runs once per login — and `-default-isolation
        // MainActor` means this `nonisolated struct`'s synchronous body runs on whichever actor
        // called it. Opening the report therefore estimated every password in the vault on the
        // thread drawing the sheet. `offMain` is the same helper the attachment path uses.
        //
        // The clock is read here rather than inside, so the timestamp is taken when the report was
        // asked for rather than whenever the executor got to it.
        let stamp = now()
        return try await offMain(items, stamp) { items, stamp in
            VaultHealthReport.make(from: items, estimator: estimator, now: stamp)
        }
    }
}
