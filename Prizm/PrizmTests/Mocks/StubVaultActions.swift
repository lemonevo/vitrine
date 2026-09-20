import Foundation
@testable import Prizm

// MARK: - No-op action doubles
//
// Named distinctly from the file-private stubs in the individual suites so that widening these to
// internal cannot collide with them.

/// Succeeds and returns a copy of the draft it was handed.
@MainActor
final class NoopDuplicateUseCase: DuplicateVaultItemUseCase {
    private(set) var callCount = 0
    private(set) var lastId: String?
    var stubbedResult: VaultItem?
    var stubbedError: Error?

    func execute(id: String) async throws -> VaultItem {
        callCount += 1
        lastId = id
        if let stubbedError { throw stubbedError }
        guard let stubbedResult else { throw VaultError.itemNotFound(id) }
        return stubbedResult
    }
}

/// Reports a configurable outcome without touching a repository.
@MainActor
final class StubEmptyTrashUseCase: EmptyTrashUseCase {
    private(set) var callCount = 0
    var stubbedResult: EmptyTrashResult = .none

    func execute() async -> EmptyTrashResult {
        callCount += 1
        return stubbedResult
    }
}
