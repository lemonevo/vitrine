import XCTest
@testable import Prizm

// MARK: - HealthReportViewModelTests

/// Tests for the report's view model: that a successful run publishes a report, and that a failed
/// run publishes a message rather than an empty one.
///
/// The second case is the one that matters. An empty report reads as "your vault is clean", which is
/// the opposite of what happened when the vault could not be read at all.
@MainActor
final class HealthReportViewModelTests: XCTestCase {

    private var useCase: StubHealthReportUseCase!
    private var sut: HealthReportViewModel!

    override func setUp() async throws {
        try await super.setUp()
        useCase = StubHealthReportUseCase()
        sut     = HealthReportViewModel(useCase: useCase)
    }

    func test_initialState_isLoading() {
        guard case .loading = sut.state else {
            return XCTFail("Expected .loading, got \(sut.state)")
        }
    }

    func test_load_success_publishesTheReport() async {
        let finding = HealthFinding(itemId: "item-1", itemName: "GitHub", detail: "weak")
        useCase.report = VaultHealthReport(byCheck: [.weakPassword: [finding]])

        await sut.load()

        guard case .loaded(let report) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(report.count(for: .weakPassword), 1)
        XCTAssertEqual(report.findings(for: .weakPassword).first?.itemId, "item-1")
    }

    /// A failure is surfaced, not swallowed into an empty report.
    func test_load_failure_publishesAMessage() async {
        useCase.error = StubReportError.unreadable

        await sut.load()

        guard case .failed(let message) = sut.state else {
            return XCTFail("Expected .failed, got \(sut.state)")
        }
        XCTAssertTrue(message.contains("vault exploded"),
                      "The message should carry the underlying reason, got: \(message)")
        XCTAssertFalse(message.isEmpty)
    }

    /// Each presentation re-runs the checks: a cached report would show the vault as it was the
    /// first time, and the whole point of the sheet is what is wrong now.
    func test_load_reRunsOnEveryCall() async {
        await sut.load()
        await sut.load()

        XCTAssertEqual(useCase.callCount, 2)
    }
}

// MARK: - Doubles

private enum StubReportError: LocalizedError {
    case unreadable

    var errorDescription: String? { "vault exploded" }
}

/// A double over the report use case: the real one reads a vault, and this suite is about what the
/// view model does with whatever comes back.
///
/// `@unchecked Sendable` because the stubbed outcome is written before `load()` and read inside it,
/// with no concurrency involved.
private final class StubHealthReportUseCase: GenerateVaultHealthReportUseCase, @unchecked Sendable {

    var report = VaultHealthReport(byCheck: [:])
    var error: Error?
    private(set) var callCount = 0

    func execute() async throws -> VaultHealthReport {
        callCount += 1
        if let error { throw error }
        return report
    }
}
