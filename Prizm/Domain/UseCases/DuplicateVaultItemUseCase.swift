import Foundation

/// Creates a copy of an existing vault item.
protocol DuplicateVaultItemUseCase {
    /// - Parameter id: the item to copy.
    /// - Returns: the server-confirmed new item.
    /// - Throws: `VaultError.itemNotFound` when `id` is not in the vault store; `VaultError.vaultLocked`
    ///   when the vault is locked; `APIError` on network or HTTP failure.
    func execute(id: String) async throws -> VaultItem
}
