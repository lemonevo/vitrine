import Foundation

// MARK: - GetPasswordHistoryUseCaseImpl

/// Reads the item's previous passwords through the vault repository.
///
/// Deliberately thin: the key resolution, the malformed-entry skipping and the ordering all live in
/// `VaultRepositoryImpl.passwordHistory(for:)`, where they belong — that is the layer that holds the
/// key material. Duplicating any of it here would put a second copy of the "which key decrypts this
/// item?" rule in the tree, and the two copies would drift.
///
/// The one thing this does decide is what *not* to do: it does not sort, and it does not cache. See
/// the protocol for both.
nonisolated struct GetPasswordHistoryUseCaseImpl: GetPasswordHistoryUseCase {

    private let vault: any VaultRepository

    init(vault: any VaultRepository) {
        self.vault = vault
    }

    func execute(itemId: String) async throws -> [PasswordHistoryEntry] {
        try await vault.passwordHistory(for: itemId)
    }
}
