import Foundation

// MARK: - GetPasskeysUseCaseImpl

/// Reads an item's passkeys through the vault repository.
///
/// Deliberately thin, for the same reason as `GetPasswordHistoryUseCaseImpl`: the key resolution and
/// the skipping of malformed entries belong to the layer that holds the key material. Duplicating
/// either here would put a second copy of the "which key decrypts this item?" rule in the tree.
///
/// What *not* to do is decided at the type level rather than here — `PasskeyCredential` has no field
/// for the private key, so this cannot return one even if a future caller wanted it.
nonisolated struct GetPasskeysUseCaseImpl: GetPasskeysUseCase {

    private let vault: any VaultRepository

    init(vault: any VaultRepository) {
        self.vault = vault
    }

    func execute(itemId: String) async throws -> [PasskeyCredential] {
        try await vault.passkeys(for: itemId)
    }
}
