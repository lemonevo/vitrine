import Foundation
import os.log

/// Concrete implementation of `DuplicateVaultItemUseCase`.
/// Delegates encryption and network I/O to `VaultRepository.duplicate(id:)`.
final class DuplicateVaultItemUseCaseImpl: DuplicateVaultItemUseCase {

    private let repository: any VaultRepository

    init(repository: any VaultRepository) {
        self.repository = repository
    }

    func execute(id: String) async throws -> VaultItem {
        try await repository.duplicate(id: id)
    }
}
