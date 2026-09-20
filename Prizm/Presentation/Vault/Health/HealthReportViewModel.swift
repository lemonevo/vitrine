import Combine
import Foundation

// MARK: - HealthReportViewModel

/// Loads the vault health report and holds its state for the sheet.
///
/// One `State` rather than three `@Published` fields (`isLoading` / `report` / `errorMessage`):
/// those can express combinations that mean nothing — loading *and* failed *and* holding a report —
/// and every view then has to pick an order to test them in. An enum makes the impossible states
/// unrepresentable and the view a `switch`.
@MainActor
final class HealthReportViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded(VaultHealthReport)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    private let useCase: any GenerateVaultHealthReportUseCase

    init(useCase: any GenerateVaultHealthReportUseCase) {
        self.useCase = useCase
    }

    /// Runs the checks.
    ///
    /// Called when the sheet appears. There is nothing to cancel: the analysis is synchronous and
    /// reads memory, so the only await is the vault read itself.
    func load() async {
        state = .loading
        do {
            state = .loaded(try await useCase.execute())
        } catch {
            // The failure is surfaced rather than swallowed into an empty report — an empty report
            // reads as "your vault is clean", which is the opposite of what happened.
            state = .failed(L("Could not read the vault: %@", error.localizedDescription))
        }
    }
}
