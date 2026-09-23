import Foundation
import os.log

// MARK: - VaultRepositoryImpl

/// In-memory vault store, populated by `SyncRepositoryImpl` after each sync.
///
/// All items are held in a flat `[VaultItem]` array. `populate()` rebuilds three
/// pre-computed indexes so that read methods are O(1) lookups instead of O(n) scans.
/// Every write method that mutates the raw stores calls `buildIndexes()` to keep the
/// cache consistent without waiting for the next sync.
///
/// Thread safety: this type is a Swift `actor`. All mutations and reads execute on the
/// actor's cooperative-thread-pool executor — never on the main thread.
actor VaultRepositoryImpl: VaultRepository {

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "VaultRepository")

    // MARK: - Dependencies (write path)

    private let apiClient:   any PrizmAPIClientProtocol
    private let crypto:      any PrizmCryptoService
    // `nonisolated`: CipherMapper is Sendable with no mutable state; marking it nonisolated
    // allows the actor init to be called from @MainActor without an actor hop.
    nonisolated private let mapper: CipherMapper
    private let orgKeyCache: OrgKeyCache

    // MARK: - Raw stores

    private var items: [VaultItem] = []
    private var folderStore: [Folder] = []
    private var organizationStore: [Organization] = []
    private var collectionStore: [OrgCollection] = []

    /// Internal sync timestamp; not exposed on the protocol (use `GetLastSyncDateUseCase`).
    private(set) var lastSyncedAt: Date? = nil

    // MARK: - Read indexes (rebuilt by buildIndexes() after every mutation)

    /// Pre-filtered, sorted item lists keyed by SidebarSelection.
    private var _bySelection: [SidebarSelection: [VaultItem]]

    /// Pre-computed counts keyed by SidebarSelection.
    private var _counts: [SidebarSelection: Int]

    /// Maps orgId → Set<collectionId> for O(1) org-membership tests.
    private var _orgCollectionIds: [String: Set<String>]

    // MARK: - Init

    // `nonisolated` avoids a Swift 6 strict-concurrency error when this init is called
    // from a `@MainActor` context (e.g. AppContainer): stored properties are initialized
    // before the actor is "live", so the actor executor is not yet involved.
    init(
        apiClient:   any PrizmAPIClientProtocol,
        crypto:      any PrizmCryptoService,
        mapper:      CipherMapper = CipherMapper(),
        orgKeyCache: OrgKeyCache = OrgKeyCache()
    ) {
        self.apiClient         = apiClient
        self.crypto            = crypto
        self.mapper            = mapper
        self.orgKeyCache       = orgKeyCache

        // Pre-populate static keys with zero counts so itemCounts() returns 0 (not nil)
        // before the first populate() / buildIndexes() call (e.g. empty-vault tests).
        var bySelection: [SidebarSelection: [VaultItem]] = [
            .allItems: [], .favorites: [], .trash: []
        ]
        var counts: [SidebarSelection: Int] = [
            .allItems: 0, .favorites: 0, .trash: 0
        ]
        for type in ItemType.allCases {
            bySelection[.type(type)] = []
            counts[.type(type)] = 0
        }
        self._bySelection      = bySelection
        self._counts           = counts
        self._orgCollectionIds = [:]
    }

    // MARK: - Write side (called by SyncRepositoryImpl)

    func populate(items: [VaultItem], folders: [Folder], organizations: [Organization],
                  collections: [OrgCollection], syncedAt: Date) async {
        self.items             = items
        self.folderStore       = folders
        self.organizationStore = organizations
        self.collectionStore   = collections
        self.lastSyncedAt      = syncedAt
        buildIndexes()
        logger.info("Vault populated: \(items.count) item(s), \(folders.count) folder(s), \(organizations.count) org(s), \(collections.count) collection(s)")
    }

    func clearVault() async {
        items             = []
        folderStore       = []
        organizationStore = []
        collectionStore   = []
        lastSyncedAt      = nil
        _bySelection      = [:]
        _counts           = [:]
        _orgCollectionIds = [:]
        logger.info("Vault cleared")
    }

    // MARK: - Index builder

    private func buildIndexes() {
        // Local staging variable — not stored; _bySelection[.allItems] serves the same role.
        let active = items.filter { !$0.isDeleted }

        // Build org-collection map first: used by both _bySelection and _counts.
        var orgColIds: [String: Set<String>] = [:]
        for col in collectionStore {
            orgColIds[col.organizationId, default: []].insert(col.id)
        }
        _orgCollectionIds = orgColIds

        // Build _bySelection
        var bySelection: [SidebarSelection: [VaultItem]] = [:]
        bySelection[.allItems]  = sorted(active)
        bySelection[.favorites] = sorted(active.filter(\.isFavorite))
        bySelection[.trash]     = sorted(items.filter(\.isDeleted))
        bySelection[.passkeys]  = sorted(active.filter(\.hasPasskey))

        for type in ItemType.allCases {
            bySelection[.type(type)] = sorted(active.filter { $0.content.matchesItemType(type) })
        }
        for folder in folderStore {
            bySelection[.folder(folder.id)] = sorted(active.filter {
                $0.organizationId == nil && $0.folderId == folder.id
            })
        }
        // Index by collection — cover all collectionIds referenced in items, not just those
        // present in collectionStore. Items may reference collections that haven't been fetched
        // yet (e.g. before the first full sync), so we union both sources.
        var allCollectionIds = Set(collectionStore.map(\.id))
        for item in active { allCollectionIds.formUnion(item.collectionIds) }
        for colId in allCollectionIds {
            bySelection[.collection(colId)] = sorted(active.filter {
                $0.collectionIds.contains(colId)
            })
        }
        // Index by organization — derive from collectionStore's organizationIds as well as
        // organizationStore, so org filtering works even when organizations: [] is passed to
        // populate() but collections carry orgId metadata.
        var allOrgIds = Set(organizationStore.map(\.id))
        allOrgIds.formUnion(orgColIds.keys)
        for orgId in allOrgIds {
            let colIds = orgColIds[orgId] ?? []
            bySelection[.organization(orgId)] = sorted(active.filter {
                $0.organizationId == orgId ||
                $0.collectionIds.contains(where: { colIds.contains($0) })
            })
        }
        _bySelection = bySelection

        // Derive _counts from _bySelection — no second filtering pass over items.
        var counts: [SidebarSelection: Int] = [:]
        counts[.allItems]  = bySelection[.allItems]?.count  ?? 0
        counts[.favorites] = bySelection[.favorites]?.count ?? 0
        counts[.trash]     = bySelection[.trash]?.count     ?? 0
        counts[.passkeys]  = bySelection[.passkeys]?.count  ?? 0
        for type in ItemType.allCases {
            counts[.type(type)] = bySelection[.type(type)]?.count ?? 0
        }
        for folder in folderStore {
            counts[.folder(folder.id)] = bySelection[.folder(folder.id)]?.count ?? 0
        }
        for colId in allCollectionIds {
            counts[.collection(colId)] = bySelection[.collection(colId), default: []].count
        }
        for orgId in allOrgIds {
            counts[.organization(orgId)] = bySelection[.organization(orgId), default: []].count
        }
        _counts = counts
    }

    // MARK: - Read side

    func allItems() async throws -> [VaultItem] {
        _bySelection[.allItems] ?? []
    }

    func folders() async throws -> [Folder] {
        folderStore.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func organizations() async throws -> [Organization] {
        organizationStore.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func collections() async throws -> [OrgCollection] {
        collectionStore.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func items(for collection: String) async throws -> [VaultItem] {
        _bySelection[.collection(collection)] ?? []
    }

    func items(for selection: SidebarSelection) async throws -> [VaultItem] {
        switch selection {
        case .newFolder, .newCollection:
            return []
        default:
            return _bySelection[selection] ?? []
        }
    }

    func searchItems(query: String, in selection: SidebarSelection) async throws -> [VaultItem] {
        let base = _bySelection[selection] ?? []
        guard !query.isEmpty else { return base }

        // Folder names live on the folder, not on the item — the item only carries a `folderId`.
        // Resolving them here rather than inside `matchesSearch` keeps `VaultItem` from needing to
        // know about folders, and this actor already holds both halves.
        let folderNames = Dictionary(folderStore.map { ($0.id, $0.name) },
                                     uniquingKeysWith: { first, _ in first })

        return base.filter { item in
            if item.matchesSearch(query: query) { return true }
            if let folderId = item.folderId,
               let folderName = folderNames[folderId],
               folderName.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    func itemCounts() async throws -> [SidebarSelection: Int] {
        _counts
    }

    func itemDetail(id: String) async throws -> VaultItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw VaultError.itemNotFound(id)
        }
        return item
    }

    // MARK: - Password history (decrypt on demand)

    /// Decrypts the server-maintained password history of the item with `id`.
    ///
    /// Newest-first ordering is the server's: Vaultwarden prepends each replaced password, so the
    /// array arrives in the order it should be displayed and is not re-sorted here.
    ///
    /// A malformed or undecryptable entry is **skipped**, not fatal. A history with one damaged
    /// entry is still worth showing, and refusing the whole list would hide data the user owns.
    /// Each skip is logged with the cipher id — never with the value.
    func passwordHistory(for id: String) async throws -> [PasswordHistoryEntry] {
        guard let item = items.first(where: { $0.id == id }) else {
            throw VaultError.itemNotFound(id)
        }
        guard !item.preserved.passwordHistory.isEmpty else { return [] }

        let keys = try await resolveCipherKeys(for: item)

        return item.preserved.passwordHistory.compactMap { entry in
            guard case .object(let fields) = entry,
                  let passwordValue = fields["password"],
                  case .string(let encryptedPassword) = passwordValue,
                  !encryptedPassword.isEmpty
            else {
                logger.error("Skipping malformed password-history entry for cipher \(id, privacy: .public)")
                return nil
            }

            let password: String
            do {
                let enc  = try EncString(string: encryptedPassword)
                let data = try enc.decrypt(keys: keys)
                guard let plaintext = String(data: data, encoding: .utf8) else {
                    logger.error("Password-history entry is not valid UTF-8 for cipher \(id, privacy: .public)")
                    return nil
                }
                password = plaintext
            } catch {
                logger.error("Skipping undecryptable password-history entry for cipher \(id, privacy: .public)")
                return nil
            }

            var lastUsedDate: Date?
            if case .string(let raw)? = fields["lastUsedDate"] {
                lastUsedDate = Self.parseISODate(raw)
            }
            return PasswordHistoryEntry(password: password, lastUsedDate: lastUsedDate)
        }
    }

    /// Decrypts the display fields of the item's passkeys.
    ///
    /// ## What is read, and what is not
    ///
    /// Every field of a FIDO2 credential is its own EncString, encrypted with the cipher's key —
    /// except `creationDate`, which is a plaintext ISO-8601 string. The field this method
    /// deliberately never touches is `keyValue`, which is the credential's **private** key:
    /// Bitwarden's authenticator writes `crypto.subtle.exportKey("pkcs8", keyPair.privateKey)` and
    /// imports it later to sign. Nothing about listing a passkey needs it, and a read-only viewer
    /// that decrypted it would be holding the one value on the item that can impersonate the user.
    ///
    /// So the decryption below is a fixed list of display fields. There is no path here that
    /// decrypts an arbitrary key out of the entry — which is what keeps "never read the private
    /// key" a property of the code instead of a rule someone has to remember.
    func passkeys(for id: String) async throws -> [PasskeyCredential] {
        guard let item = items.first(where: { $0.id == id }) else {
            throw VaultError.itemNotFound(id)
        }
        guard !item.preserved.fido2Credentials.isEmpty else { return [] }

        let keys = try await resolveCipherKeys(for: item)

        return item.preserved.fido2Credentials.compactMap { entry in
            guard case .object(let fields) = entry else {
                logger.error("Skipping malformed passkey entry for cipher \(id, privacy: .public)")
                return nil
            }

            /// Decrypts one named field. `nil` when it is absent or will not decrypt — an absent
            /// optional field is normal, so it is not logged as a fault.
            func plain(_ name: String) -> String? {
                guard case .string(let value)? = fields[name], !value.isEmpty else { return nil }
                do {
                    let data = try EncString(string: value).decrypt(keys: keys)
                    return String(data: data, encoding: .utf8)
                } catch {
                    return nil
                }
            }

            // The relying party id is the one field a listing is meaningless without: it is what
            // tells the user which site this credential belongs to.
            guard let rpId = plain("rpId") ?? plain("RpId") else {
                logger.error("Skipping passkey with no readable rpId for cipher \(id, privacy: .public)")
                return nil
            }

            return PasskeyCredential(
                rpId:            rpId,
                rpName:          plain("rpName") ?? plain("RpName"),
                userName:        plain("userName") ?? plain("UserName"),
                userDisplayName: plain("userDisplayName") ?? plain("UserDisplayName"),
                creationDate:    Self.creationDate(in: fields)
            )
        }
    }

    /// Reads `creationDate`, the one passkey field that is not an EncString.
    ///
    /// Two spellings are accepted because the two ends of Bitwarden's own stack disagree: the API
    /// model reads `CreationDate` while the response the server actually emits uses `creationDate`.
    /// Their lookup is case-insensitive so they never noticed; a direct dictionary lookup does.
    nonisolated private static func creationDate(in fields: [String: JSONValue]) -> Date? {
        for name in ["creationDate", "CreationDate"] {
            if case .string(let raw)? = fields[name] { return parseISODate(raw) }
        }
        return nil
    }

    /// Resolves the 64-byte key that decrypts an item's fields.
    ///
    /// This mirrors `CipherMapper.map`'s key selection exactly: the per-item key when the cipher
    /// carries one (unwrapped with the vault or organisation key), otherwise the vault or
    /// organisation key itself. The rule is deliberately duplicated rather than shared, because
    /// the mapper's copy is entangled with the whole decrypt-and-map pass; but it is four lines,
    /// and it has to stay identical — a history entry must decrypt with the same key its item's
    /// current password does.
    private func resolveCipherKeys(for item: VaultItem) async throws -> CryptoKeys {
        let vaultKeys: CryptoKeys
        do {
            vaultKeys = try await crypto.currentKeys()
        } catch PrizmCryptoServiceError.vaultLocked {
            throw VaultError.vaultLocked
        }

        let activeKeys: CryptoKeys
        if let orgId = item.organizationId {
            let orgKeys = await orgKeyCache.snapshot()
            guard let orgKey = orgKeys[orgId] else {
                throw VaultError.decryptionFailed("org key not found for org: \(orgId)")
            }
            activeKeys = orgKey
        } else {
            activeKeys = vaultKeys
        }

        guard let wrappedKey = item.preserved.cipherKey else { return activeKeys }

        do {
            let enc = try EncString(string: wrappedKey)
            let raw = try enc.decrypt(keys: activeKeys)
            return CryptoKeys(encryptionKey: raw.prefix(32), macKey: raw.suffix(32))
        } catch {
            logger.error("Per-item key decryption failed for cipher \(item.id, privacy: .public)")
            throw VaultError.decryptionFailed("key")
        }
    }

    /// Parses an ISO-8601 timestamp, with or without fractional seconds.
    ///
    /// The server is inconsistent: Vaultwarden writes `passwordHistory[].lastUsedDate` with
    /// millisecond precision while some cipher dates come without. `CipherMapper` only handles the
    /// fractional form, which is why this is a second parser rather than a shared one — the date
    /// here is display metadata, so an unparseable value degrades to `nil` rather than failing.
    ///
    /// The either-form rule itself lives in `ISO8601WireDate`, because `VaultExportDocument` needed
    /// the identical pair and the identical fallback written out a second time.
    nonisolated private static func parseISODate(_ raw: String) -> Date? {
        ISO8601WireDate.parse(raw)
    }

    // MARK: - Update (write path — called by EditVaultItemUseCaseImpl)

    /// Re-encrypts `draft`, calls `PUT /api/ciphers/{id}`, splices the server-confirmed
    /// item into the in-memory cache, and returns it.
    ///
    /// - Security goal: the vault's symmetric keys are used to re-encrypt every sensitive
    ///   field before the request leaves the device. The re-encryption boundary is the call
    ///   to `CipherMapper.toRawCipher` — after that point only EncString ciphertext exists
    ///   in the `RawCipher` struct. Plaintext is never serialised into the JSON body.
    ///   Algorithm: EncString type-2 (AES-256-CBC + HMAC-SHA256); see `CipherMapper.toRawCipher`
    ///   for the full algorithm reference and security notes.
    ///
    /// - Data flow (re-encryption boundary):
    ///   1. Obtain current symmetric keys from `PrizmCryptoService` — throws immediately
    ///      if the vault is locked, preventing writes from a locked state.
    ///   2. `CipherMapper.toRawCipher` encrypts every sensitive field with the vault key.
    ///      No plaintext value crosses this call boundary in the outbound direction.
    ///   3. The encrypted `RawCipher` is sent via `PUT /api/ciphers/{id}`.
    ///   4. The server response is decoded and re-mapped to a `VaultItem` — we use the
    ///      *response* (not the draft) so the server's revision date and any server-side
    ///      normalisation are captured correctly.
    ///   5. The in-memory cache is patched in-place so the UI reflects the latest state
    ///      without triggering a full re-sync.
    ///
    /// - What is NOT done:
    ///   • Biometric re-authentication is not required before writing (see TODO below).
    ///   • Offline writes are not queued; a network failure surfaces as a thrown error
    ///     and leaves the local cache unchanged (see TODO below).
    ///
    /// - Throws: `VaultError.vaultLocked` if the vault is locked (translated from `PrizmCryptoServiceError`).
    /// - Throws: `APIError` on network or HTTP failure.
    /// - Throws: `CipherMapperError` if the reverse mapper or response mapper fails.
    func update(_ draft: DraftVaultItem) async throws -> VaultItem {
        // TODO: Require biometric re-auth before encrypting and sending — deferred pending
        // SecureEnclave entitlement approval.

        let vaultKeys: CryptoKeys
        do {
            vaultKeys = try await crypto.currentKeys()
        } catch PrizmCryptoServiceError.vaultLocked {
            throw VaultError.vaultLocked
        }

        let orgKeysSnapshot = await orgKeyCache.snapshot()
        let encryptionKeys = try resolveEncryptionKeys(for: draft,
                                                       vaultKeys: vaultKeys,
                                                       orgKeys: orgKeysSnapshot)

        let rawCipher = try mapper.toRawCipher(draft, encryptedWith: encryptionKeys)

        // TODO: Queue encrypted rawCipher for offline persistence (deferred — requires WAL).
        let updatedRaw = try await apiClient.updateCipher(id: draft.id, cipher: rawCipher)

        // Collection membership is deliberately NOT re-sent here.
        //
        // `PUT /api/ciphers/{id}` never touches membership: in Vaultwarden, `put_cipher`
        // calls `update_cipher_from_data` with `shared_to_collections: None`, and that
        // function's only use of the parameter is the push notification it sends. The
        // separate `PUT /api/ciphers/{id}/collections` endpoint is what changes membership,
        // and it applies `symmetric_difference` against the set the cipher is currently in
        // — so an **empty** array removes the item from every collection it belongs to.
        //
        // Re-sending `draft.collectionIds` on every edit was therefore at best a no-op and
        // at worst destructive: a membership this client never learned decodes as `[]`
        // (`RawCipher.collectionIds` falls back to empty for an absent *and* an undecodable
        // value), so renaming an organisation item could empty its collections. No UI
        // changes membership, so there is nothing to send.
        //
        // If a membership editor is added later, call `updateCipherCollections` from that
        // action alone, and never with a value that a decode fallback produced.
        var (updatedItem, _) = try mapper.map(raw: updatedRaw, vaultKeys: vaultKeys, orgKeys: orgKeysSnapshot)

        // Patch collectionIds: PUT /api/ciphers/{id} returns pre-update collection state.
        // `with` keeps every other field — including `preserved` — untouched.
        if draft.organizationId != nil {
            updatedItem = updatedItem.with(collectionIds: draft.collectionIds)
        }

        if let idx = items.firstIndex(where: { $0.id == updatedItem.id }) {
            items[idx] = updatedItem
        } else {
            items.append(updatedItem)
        }
        buildIndexes()
        logger.info("Vault item updated: \(draft.id, privacy: .public)")
        return updatedItem
    }

    // MARK: - Create (write path)

    func create(_ draft: DraftVaultItem) async throws -> VaultItem {
        let vaultKeys: CryptoKeys
        do {
            vaultKeys = try await crypto.currentKeys()
        } catch PrizmCryptoServiceError.vaultLocked {
            throw VaultError.vaultLocked
        }

        let orgKeysSnapshot = await orgKeyCache.snapshot()
        let encryptionKeys = try resolveEncryptionKeys(for: draft,
                                                       vaultKeys: vaultKeys,
                                                       orgKeys: orgKeysSnapshot)

        let rawCipher = try mapper.toRawCipher(draft, encryptedWith: encryptionKeys)

        let createdRaw: RawCipher
        if draft.organizationId != nil {
            createdRaw = try await apiClient.createOrgCipher(cipher: rawCipher)
        } else {
            createdRaw = try await apiClient.createCipher(cipher: rawCipher)
        }

        // Discard cipherKey — newly created items are picked up by the next sync.
        let (createdItem, _) = try mapper.map(raw: createdRaw, vaultKeys: vaultKeys, orgKeys: orgKeysSnapshot)
        items.append(createdItem)
        buildIndexes()
        logger.info("Vault item created: \(createdItem.id, privacy: .public)")
        return createdItem
    }

    /// Creates a copy of the item with `id` by building a duplicate draft and routing it through
    /// `create`, so the copy is encrypted and cached exactly like any other new item.
    ///
    /// Attachments, the per-item cipher key, passkeys, password history and the archived flag are
    /// deliberately not carried over — see `DraftVaultItem.duplicate(of:)`.
    func duplicate(id: String) async throws -> VaultItem {
        guard let source = items.first(where: { $0.id == id }) else {
            throw VaultError.itemNotFound(id)
        }
        let created = try await create(DraftVaultItem.duplicate(of: source))
        logger.info("Vault item duplicated: \(id, privacy: .public) → \(created.id, privacy: .public)")
        return created
    }

    // MARK: - Delete / Restore / Empty Trash

    /// Soft-deletes the active item with `id` by calling `PUT /ciphers/{id}/delete`.
    ///
    /// - Security goal: no vault key material is needed — only the cipher ID is sent.
    ///   The access token (held by `PrizmAPIClientImpl`) authorises the operation.
    /// - Bitwarden endpoint: `PUT /api/ciphers/{id}/delete` — moves the cipher to Trash.
    func deleteItem(id: String) async throws {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        try await apiClient.softDeleteCipher(id: id)
        items[idx] = items[idx].with(isDeleted: true)
        buildIndexes()
        logger.info("Vault item soft-deleted: \(id, privacy: .public)")
    }

    /// Permanently deletes the trashed item with `id` by calling `DELETE /ciphers/{id}`.
    ///
    /// - Security goal: same as `deleteItem` — only the cipher ID is sent; no key material.
    /// - Bitwarden endpoint: `DELETE /api/ciphers/{id}` — permanently removes the cipher.
    func permanentDeleteItem(id: String) async throws {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        try await apiClient.permanentDeleteCipher(id: id)
        items.remove(at: idx)
        buildIndexes()
        logger.info("Vault item permanently deleted: \(id, privacy: .public)")
    }

    /// Restores the trashed item with `id` by calling `PUT /api/ciphers/{id}/restore`.
    ///
    /// - Security goal: same as `deleteItem` — only the cipher ID is sent; no key material.
    func restoreItem(id: String) async throws {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        try await apiClient.restoreCipher(id: id)
        // `with` keeps every other field — including `preserved` and the org membership.
        // A hand-written memberwise rebuild here would drop them (see openspec/specs/cipher-wire-integrity).
        items[idx] = items[idx].with(isDeleted: false)
        buildIndexes()
        logger.info("Vault item restored: \(id, privacy: .public)")
    }

    // MARK: - Attachment cache patch

    /// Replaces the `attachments` array for the item identified by `cipherId` in the
    /// in-memory store without triggering a full re-sync.
    func updateAttachments(_ attachments: [Attachment], for cipherId: String) async {
        guard let idx = items.firstIndex(where: { $0.id == cipherId }) else {
            logger.error("updateAttachments: cipher not found in cache — id=\(cipherId, privacy: .public)")
            return
        }
        // `with` keeps every other field — including `preserved` and the org membership.
        // Attachments are fetched through their own endpoint, so nothing else is refreshed here.
        items[idx] = items[idx].with(attachments: attachments)
        buildIndexes()
        logger.info("Vault item attachments updated: cipher=\(cipherId, privacy: .public) count=\(attachments.count, privacy: .public)")
    }

    // MARK: - Folder CRUD

    func createFolder(name: String) async throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultError.decryptionFailed("empty folder name") }
        let encName = try await encryptFolderName(trimmed)
        let raw = try await apiClient.createFolder(encryptedName: encName)
        let folder = Folder(id: raw.id, name: trimmed)
        folderStore.append(folder)
        buildIndexes()
        logger.info("Folder created: \(raw.id, privacy: .public)")
        return folder
    }

    func renameFolder(id: String, name: String) async throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultError.decryptionFailed("empty folder name") }
        let encName = try await encryptFolderName(trimmed)
        _ = try await apiClient.updateFolder(id: id, encryptedName: encName)
        let folder = Folder(id: id, name: trimmed)
        if let idx = folderStore.firstIndex(where: { $0.id == id }) {
            folderStore[idx] = folder
        }
        buildIndexes()
        logger.info("Folder renamed: \(id, privacy: .public)")
        return folder
    }

    func deleteFolder(id: String) async throws {
        try await apiClient.deleteFolder(id: id)
        folderStore.removeAll { $0.id == id }
        // Unfolder items that were in this folder (server does this too).
        // `with(folderId: .some(nil))` changes only the folder: `organizationId` and
        // `collectionIds` must survive, or a later save would convert an org item into a
        // personal one (see openspec/specs/org-vault-items).
        for i in items.indices where items[i].folderId == id {
            items[i] = items[i].with(folderId: .some(nil))
        }
        buildIndexes()
        logger.info("Folder deleted: \(id, privacy: .public)")
    }

    // MARK: - Collection CRUD

    /// Creates a new collection within an organization.
    ///
    /// - Security goal: collection names are encrypted with the *org* symmetric key
    ///   (not the vault key) so that all members of the organization can decrypt them.
    ///   Reference: Bitwarden Security Whitepaper §4 — "Organization Key Wrapping".
    func createCollection(name: String, organizationId: String) async throws -> OrgCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultError.decryptionFailed("empty collection name") }
        let encName = try await encryptCollectionName(trimmed, organizationId: organizationId)
        let raw = try await apiClient.createCollection(organizationId: organizationId,
                                                        encryptedName: encName)
        let collection = OrgCollection(id: raw.id, organizationId: organizationId, name: trimmed)
        collectionStore.append(collection)
        buildIndexes()
        logger.info("Collection created: \(raw.id, privacy: .public)")
        return collection
    }

    /// Renames an existing collection. New name encrypted with the org key.
    func renameCollection(id: String, organizationId: String, name: String) async throws -> OrgCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultError.decryptionFailed("empty collection name") }
        let encName = try await encryptCollectionName(trimmed, organizationId: organizationId)

        // Whatever the store already knew about this collection's membership goes back with the
        // rename. Rebuilding the entity from three fields — which is what this did — discarded it
        // locally as well, so the client agreed with the server's loss.
        // Refused rather than defaulted. Vaultwarden deletes and re-creates a collection's access
        // rows from the request, so sending empty arrays is not "no change" — it is a revocation.
        // Having no source for the membership therefore means the rename cannot be done safely, and
        // failing is the only outcome that does not destroy something.
        //
        // Unreachable from the UI today (a collection missing from the store is not in the sidebar
        // either — this is the path for one dropped when its name failed to decrypt), which is an
        // argument for the cheap guard, not for leaving the fallback.
        guard let existing = collectionStore.first(where: { $0.id == id }) else {
            logger.error("Refusing to rename collection \(id, privacy: .public): its membership is unknown, and sending an empty one would revoke access")
            throw VaultError.itemNotFound(id)
        }
        let preserved = existing.preserved

        _ = try await apiClient.renameCollection(id: id, organizationId: organizationId,
                                                  encryptedName: encName,
                                                  preserved: preserved)
        let collection = OrgCollection(id: id, organizationId: organizationId, name: trimmed,
                                       preserved: preserved)
        if let idx = collectionStore.firstIndex(where: { $0.id == id }) {
            collectionStore[idx] = collection
        }
        buildIndexes()
        logger.info("Collection renamed: \(id, privacy: .public)")
        return collection
    }

    /// Deletes a collection from an organization and removes it from the local cache.
    ///
    /// Items that were in the collection are NOT deleted — they remain in the vault
    /// with stale `collectionIds` entries that no longer match a known collection.
    func deleteCollection(id: String, organizationId: String) async throws {
        try await apiClient.deleteCollection(id: id, organizationId: organizationId)
        collectionStore.removeAll { $0.id == id }
        buildIndexes()
        logger.info("Collection deleted: \(id, privacy: .public)")
    }

    // MARK: - Move to folder

    func moveItemToFolder(itemId: String, folderId: String?) async throws {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        let old = items[idx]
        try await apiClient.updateCipherPartial(id: itemId, folderId: folderId, favorite: old.isFavorite)
        items[idx] = old.with(folderId: .some(folderId))
        buildIndexes()
        logger.info("Item moved to folder: \(itemId, privacy: .public)")
    }

    func moveItemsToFolder(itemIds: [String], folderId: String?) async throws {
        try await apiClient.moveCiphersToFolder(ids: itemIds, folderId: folderId)
        for i in items.indices where itemIds.contains(items[i].id) {
            items[i] = items[i].with(folderId: .some(folderId))
        }
        buildIndexes()
        logger.info("Bulk move to folder: \(itemIds.count, privacy: .public) item(s)")
    }

    // MARK: - Private helpers

    /// Selects the key that wraps a draft's encrypted fields.
    ///
    /// - Security goal: an organisation cipher must be encrypted with the organisation's key.
    ///   Falling back to the personal vault key would write a cipher no other org member can
    ///   read — and that this client could not read either after the next sync, because the read
    ///   path refuses to map an org cipher whose org key is missing. A silent fallback here turns
    ///   a recoverable "org key not loaded" state into permanent corruption.
    /// - Throws: `VaultError.decryptionFailed` when the draft is org-scoped and the org key has
    ///   not been unwrapped. No network request is made in that case.
    private func resolveEncryptionKeys(for draft: DraftVaultItem,
                                       vaultKeys: CryptoKeys,
                                       orgKeys: [String: CryptoKeys]) throws -> CryptoKeys {
        guard let orgId = draft.organizationId else { return vaultKeys }
        guard let orgKey = orgKeys[orgId] else {
            logger.error("Refusing to write org cipher \(draft.id, privacy: .public): org key not unwrapped")
            throw VaultError.decryptionFailed("org key not found for org: \(orgId)")
        }
        return orgKey
    }

    private func sorted(_ input: [VaultItem]) -> [VaultItem] {
        input.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Encrypts a plaintext folder name as a type-2 EncString using the current vault keys.
    ///
    /// - Security: AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC) with a fresh random IV.
    ///   Same algorithm as cipher field encryption in `CipherMapper.encryptString`.
    private func encryptFolderName(_ name: String) async throws -> String {
        let keys: CryptoKeys
        do {
            keys = try await crypto.currentKeys()
        } catch PrizmCryptoServiceError.vaultLocked {
            throw VaultError.vaultLocked
        }
        guard let data = name.data(using: .utf8) else {
            throw VaultError.decryptionFailed("utf8-encode")
        }
        return try EncString.encrypt(data: data, keys: keys).toString()
    }

    /// Encrypts a plaintext collection name using the organization's symmetric key.
    ///
    /// - Security goal: collection names are org-key-encrypted so any org member
    ///   can read them. The vault key is NOT used — it is per-user, not per-org.
    ///   Algorithm: EncString type-2 (AES-256-CBC + HMAC-SHA256).
    private func encryptCollectionName(_ name: String, organizationId: String) async throws -> String {
        let orgSnapshot = await orgKeyCache.snapshot()
        guard let orgKey = orgSnapshot[organizationId] else {
            throw VaultError.decryptionFailed("org key not found for org: \(organizationId)")
        }
        guard let data = name.data(using: .utf8) else {
            throw VaultError.decryptionFailed("utf8-encode")
        }
        return try EncString.encrypt(data: data, keys: orgKey).toString()
    }
}

// MARK: - ItemContent search / type matching

nonisolated private extension ItemContent {
    func matchesItemType(_ type: ItemType) -> Bool {
        switch (self, type) {
        case (.login,      .login):      return true
        case (.card,       .card):       return true
        case (.identity,   .identity):   return true
        case (.secureNote, .secureNote): return true
        case (.sshKey,     .sshKey):     return true
        default:                         return false
        }
    }

    /// The free-text notes for this content type. All five carry notes under the same name, but
    /// they are separate stored properties, so a search that must cover every type needs one place
    /// to look.
    var notes: String? {
        switch self {
        case .login(let c):      return c.notes
        case .card(let c):       return c.notes
        case .identity(let c):   return c.notes
        case .secureNote(let c): return c.notes
        case .sshKey(let c):     return c.notes
        }
    }

    /// The custom fields for this content type, for the same reason.
    var customFields: [CustomField] {
        switch self {
        case .login(let c):      return c.customFields
        case .card(let c):       return c.customFields
        case .identity(let c):   return c.customFields
        case .secureNote(let c): return c.customFields
        case .sshKey(let c):     return c.customFields
        }
    }
}

nonisolated private extension VaultItem {
    /// Case-insensitive substring search.
    ///
    /// Searched, for every item type: the name, the notes, and each custom field's name and value.
    /// Plus, per type: Login = username and URIs; Card = cardholder name; Identity = email and
    /// company. Folder names are matched by the caller, which holds the folder list.
    ///
    /// Notes and custom fields are searched before the per-type switch, so secure notes and SSH
    /// keys — which have no other searchable field — are covered too. Hidden custom field values
    /// are searched like any other: this runs locally over already-decrypted values, and matching
    /// one does not display it.
    func matchesSearch(query: String) -> Bool {
        if name.localizedCaseInsensitiveContains(query) { return true }

        if let notes = content.notes, notes.localizedCaseInsensitiveContains(query) { return true }

        if content.customFields.contains(where: { field in
            field.name.localizedCaseInsensitiveContains(query)
                || field.value?.localizedCaseInsensitiveContains(query) == true
        }) { return true }

        switch content {
        case .login(let l):
            return (l.username?.localizedCaseInsensitiveContains(query) == true) ||
                   l.uris.contains { $0.uri.localizedCaseInsensitiveContains(query) }
        case .card(let c):
            return c.cardholderName?.localizedCaseInsensitiveContains(query) == true
        case .identity(let i):
            return (i.email?.localizedCaseInsensitiveContains(query) == true) ||
                   (i.company?.localizedCaseInsensitiveContains(query) == true)
        case .secureNote, .sshKey:
            return false
        }
    }
}
