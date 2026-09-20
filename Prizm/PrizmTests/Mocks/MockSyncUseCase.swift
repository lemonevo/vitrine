import Foundation
@testable import Prizm

/// Test double for `SyncUseCase`.
final class MockSyncUseCase: SyncUseCase {

    private(set) var executeCalled: Bool = false

    /// How many times `execute` was entered.
    ///
    /// `executeCalled` only answers "was it ever called", which cannot distinguish "the re-entrancy
    /// guard held" from "the second call also ran". Counting can.
    private(set) var executeCallCount: Int = 0

    var stubbedResult: SyncResult = SyncResult(syncedAt: Date(), totalCiphers: 0, failedDecryptionCount: 0)
    var executeError: Error?

    /// When set, `execute` sleeps for this long before returning.
    ///
    /// Lets a test observe the in-flight state. Without it the double returns on the next run-loop
    /// turn and "a second sync was blocked" is not reliably observable.
    var stubbedDelay: Duration?

    func execute(progress: @Sendable @escaping (String) -> Void) async throws -> SyncResult {
        executeCalled = true
        executeCallCount += 1
        if let stubbedDelay { try await Task.sleep(for: stubbedDelay) }
        if let err = executeError { throw err }
        return stubbedResult
    }
}
