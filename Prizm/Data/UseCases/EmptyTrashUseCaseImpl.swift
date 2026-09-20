import Foundation
import os.log

/// Concrete implementation of `EmptyTrashUseCase`.
///
/// Lists the trashed items and permanently deletes each one. Failures are counted rather than
/// thrown, so a partial outcome is reported honestly instead of leaving the user guessing how much
/// was removed (see `EmptyTrashResult`).
final class EmptyTrashUseCaseImpl: EmptyTrashUseCase {

    private let repository: any VaultRepository
    private let logger = Logger(subsystem: "com.prizm", category: "EmptyTrashUseCase")

    init(repository: any VaultRepository) {
        self.repository = repository
    }

    func execute() async -> EmptyTrashResult {
        let trashed: [VaultItem]
        do {
            trashed = try await repository.items(for: .trash)
        } catch {
            logger.error("Could not list Trash: \(error.localizedDescription, privacy: .public)")
            return EmptyTrashResult(deletedCount: 0, failedCount: 0,
                                    errorMessage: error.localizedDescription)
        }

        guard !trashed.isEmpty else { return .none }

        var deleted = 0
        var failed  = 0
        var lastError: String?

        for item in trashed {
            do {
                try await repository.permanentDeleteItem(id: item.id)
                deleted += 1
            } catch {
                failed += 1
                lastError = error.localizedDescription
                logger.error("Permanent delete failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.info("Trash emptied: \(deleted) deleted, \(failed) failed")
        return EmptyTrashResult(deletedCount: deleted, failedCount: failed, errorMessage: lastError)
    }
}
