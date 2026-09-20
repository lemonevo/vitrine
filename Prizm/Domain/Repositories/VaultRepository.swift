import Foundation

/// In-memory vault store: write side used by `SyncRepositoryImpl`, read side used by use cases.
/// Implemented by `VaultRepositoryImpl` (a dedicated `actor`) in the Data layer.
/// All methods are `async` — callers must `await` them regardless of their own isolation context.
protocol VaultRepository: AnyObject, Sendable {

    /// All non-deleted vault items, sorted alphabetically by name (case-insensitive).
    func allItems() async throws -> [VaultItem]

    /// Items matching the given sidebar selection, sorted alphabetically.
    func items(for selection: SidebarSelection) async throws -> [VaultItem]

    /// Case-insensitive substring search scoped to the active sidebar selection.
    /// Searches type-specific fields per FR-012:
    /// - Login:      name, username, URIs
    /// - Card:       name, cardholderName
    /// - Identity:   name, email, company
    /// - SecureNote: name
    /// - SSHKey:     name
    func searchItems(query: String, in selection: SidebarSelection) async throws -> [VaultItem]

    /// Cached item counts keyed by `SidebarSelection`. O(1) — served from a pre-built index.
    func itemCounts() async throws -> [SidebarSelection: Int]

    /// Returns the fully-decrypted detail for a single item.
    /// Not cached — re-decrypts on every call (decrypt on demand, per spec).
    func itemDetail(id: String) async throws -> VaultItem

    /// Decrypts the server-maintained password history of the item with `id`.
    ///
    /// Returns the previous passwords newest-first, or an empty array when the item has none.
    ///
    /// **Why the repository and not a mapper.** Decrypting a history entry needs the item's own
    /// key resolution — the per-item key when the cipher carries one, otherwise the vault or
    /// organisation key. That resolution already lives here (`CipherMapper.map` performs it for
    /// the current password), and reimplementing it at a call site is how the two drift apart.
    ///
    /// **Never cached.** The plaintext is produced per call and dropped when the caller is done,
    /// matching `itemDetail(id:)`. The encrypted form stays in
    /// `PreservedCipherFields.passwordHistory` and continues to round-trip untouched.
    ///
    /// An entry that cannot be decrypted is skipped rather than failing the whole list: a history
    /// with one damaged entry is still worth showing, and refusing to show any of it would hide
    /// data the user owns.
    ///
    /// - Throws: `VaultError.itemNotFound` if `id` is not in the store.
    /// - Throws: `VaultError.vaultLocked` if the vault is locked.
    func passwordHistory(for id: String) async throws -> [PasswordHistoryEntry]

    /// Replaces the in-memory vault store and rebuilds all read indexes.
    /// Called by `SyncRepositoryImpl` after a successful sync.
    func populate(items: [VaultItem], folders: [Folder], organizations: [Organization],
                  collections: [OrgCollection], syncedAt: Date) async

    /// All organizations the user belongs to, sorted alphabetically by name.
    func organizations() async throws -> [Organization]

    /// All collections across all organizations, sorted alphabetically by name.
    func collections() async throws -> [OrgCollection]

    /// Items assigned to the given collection, sorted alphabetically by name.
    func items(for collection: String) async throws -> [VaultItem]

    /// Clears the in-memory vault store and all indexes. Called on lock and sign-out.
    func clearVault() async

    /// All folders, sorted alphabetically by name (case-insensitive).
    func folders() async throws -> [Folder]

    /// Re-encrypts `draft`, calls `PUT /ciphers/{id}`, updates the in-memory cache, and
    /// returns the server-confirmed `VaultItem` decoded from the API response.
    func update(_ draft: DraftVaultItem) async throws -> VaultItem

    /// Soft-deletes the item with `id` by calling `PUT /ciphers/{id}/delete`.
    func deleteItem(id: String) async throws

    /// Permanently removes the trashed item with `id` by calling `DELETE /ciphers/{id}`.
    func permanentDeleteItem(id: String) async throws

    /// Restores a trashed item by calling `PUT /ciphers/{id}/restore`.
    func restoreItem(id: String) async throws

    /// Encrypts a new `draft`, calls `POST /api/ciphers`, inserts the server-confirmed item
    /// into the in-memory cache, and returns it.
    func create(_ draft: DraftVaultItem) async throws -> VaultItem

    /// Creates a copy of the item with `id` and returns the server-confirmed new item.
    ///
    /// The copy carries everything the user can see — content, notes, custom fields, folder,
    /// organisation membership — but not attachments, the per-item cipher key, passkeys, password
    /// history or the archived flag. See `DraftVaultItem.duplicate(of:)` for why each is excluded.
    ///
    /// Implemented in terms of `create`, so a duplicate goes through the same encryption, org-key
    /// resolution and cache-insert path as any other new item.
    ///
    /// - Throws: `VaultError.itemNotFound` if `id` is not in the store.
    func duplicate(id: String) async throws -> VaultItem

    /// Replaces the `attachments` array for the vault item identified by `cipherId`,
    /// patching the in-memory cache without a full re-sync.
    func updateAttachments(_ attachments: [Attachment], for cipherId: String) async

    // MARK: - Folder CRUD

    func createFolder(name: String) async throws -> Folder
    func renameFolder(id: String, name: String) async throws -> Folder
    func deleteFolder(id: String) async throws

    // MARK: - Move to folder

    func moveItemToFolder(itemId: String, folderId: String?) async throws
    func moveItemsToFolder(itemIds: [String], folderId: String?) async throws

    // MARK: - Collection CRUD

    func createCollection(name: String, organizationId: String) async throws -> OrgCollection
    func renameCollection(id: String, organizationId: String, name: String) async throws -> OrgCollection
    func deleteCollection(id: String, organizationId: String) async throws

}

// MARK: - Errors

nonisolated enum VaultError: Error, LocalizedError {
    case vaultLocked
    case decryptionFailed(String)
    case itemNotFound(String)

    var errorDescription: String? {
        switch self {
        case .vaultLocked:
            return L("The vault is locked. Please unlock to continue.")
        case .decryptionFailed(let detail):
            return L("Decryption failed: %@", detail)
        case .itemNotFound(let id):
            return L("Item not found: %@", id)
        }
    }
}
