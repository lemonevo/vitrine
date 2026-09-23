import Foundation
import os.log

// MARK: - SyncRepositoryImpl

/// Concrete implementation of `SyncRepository`.
///
/// Fetches the encrypted vault from the Bitwarden server, decrypts ciphers, folders,
/// organizations, and collections, then populates the in-memory `VaultRepository`.
///
/// **Org cipher support**: when the sync profile contains a `privateKey` EncString and at
/// least one organization, the RSA private key is decrypted with the vault symmetric key,
/// used to unwrap each org's symmetric key via RSA-OAEP-SHA1 (`Security.framework`), and
/// the unwrapped keys are stored in `OrgKeyCache` for the duration of the session.
/// Org ciphers are then decrypted using the org key rather than the personal vault key.
///
/// Individual cipher decryption failures are non-fatal — they are counted and logged
/// but the remaining ciphers are still stored.
///
/// Concurrent calls: the second caller receives `SyncError.syncInProgress`.
actor SyncRepositoryImpl: SyncRepository {

    // MARK: - Dependencies

    private let apiClient:       any PrizmAPIClientProtocol
    private let crypto:          any PrizmCryptoService
    private let vaultRepository: any VaultRepository
    private let vaultKeyCache:   VaultKeyCache
    private let orgKeyCache:     OrgKeyCache
    private let accountKeyCache: AccountKeyCache
    private let vaultCache:      any VaultCacheStore

    /// The signed-in account's user id, or `nil` when there is no session.
    ///
    /// A closure rather than an `AuthRepository` reference, and resolved at the moment it is needed
    /// rather than remembered here. The answer is read from the Keychain, which is the one place
    /// that knows which account is signed in — caching it in a second place would create a value
    /// that can disagree with the session it describes.
    private let currentUserId:   @Sendable () async -> String?

    /// Identifies the session this sync belongs to.
    ///
    /// A sync is the longest-running thing the app does, so it is the most likely to still be in
    /// flight when the user locks. Without this, it returns and writes — into the key caches, into
    /// the store, into the view model — resurrecting a session whose keys the lock has already
    /// zeroed.
    private let sessionEpoch:    SessionEpoch

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "SyncRepository")

    // MARK: - State

    private var isSyncing = false

    // MARK: - Init

    init(
        apiClient:       any PrizmAPIClientProtocol,
        crypto:          any PrizmCryptoService,
        vaultRepository: any VaultRepository,
        vaultKeyCache:   VaultKeyCache,
        orgKeyCache:     OrgKeyCache = OrgKeyCache(),
        accountKeyCache:  AccountKeyCache = AccountKeyCache(),
        vaultCache:      any VaultCacheStore,
        sessionEpoch:    SessionEpoch = SessionEpoch(),
        currentUserId:   @escaping @Sendable () async -> String?
    ) {
        self.apiClient       = apiClient
        self.crypto          = crypto
        self.vaultRepository = vaultRepository
        self.vaultKeyCache   = vaultKeyCache
        self.orgKeyCache     = orgKeyCache
        self.accountKeyCache  = accountKeyCache
        self.vaultCache      = vaultCache
        self.sessionEpoch    = sessionEpoch
        self.currentUserId   = currentUserId
    }

    // MARK: - SyncRepository

    func sync(progress: @Sendable @escaping (String) -> Void) async throws -> SyncResult {
        guard !isSyncing else {
            logger.info("sync() called while already in progress")
            throw SyncError.syncInProgress
        }
        isSyncing = true
        defer { isSyncing = false }

        // Captured before the first `await`, so a lock that happens at any point during this sync
        // invalidates it. Everything below is either a read or is preceded by `requireLiveSession`.
        let epochToken = await sessionEpoch.current()

        // Phase 1: Fetch encrypted vault from server, or from the cache when it cannot be reached.
        progress(L("Syncing vault…"))
        logger.info("Starting vault sync")

        let fetched = try await fetchVault()

        // The network call is the longest window, and the common case: the user pressed ⌘L while the
        // request was out. Checked before any decryption so a dead session does no work at all.
        try await requireLiveSession(epochToken)

        let syncResponse = fetched.response
        if fetched.source == .cache {
            progress(L("Using the offline copy of your vault…"))
        }

        let totalCiphers = syncResponse.ciphers.count
        logger.info("Fetched \(totalCiphers) cipher(s)")

        if DebugConfig.isEnabled {
            // Log counts by cipher type to help diagnose sync issues (e.g. unexpected
            // type integers from a non-standard server). Values are type ints only —
            // no cipher names, URLs, or other vault content is logged.
            let typeCounts = syncResponse.ciphers.reduce(into: [Int: Int]()) { acc, c in
                acc[c.type, default: 0] += 1
            }
            let orgCount = syncResponse.ciphers.filter { $0.organizationId != nil }.count
            // Must match `RawCipher.type`'s documented mapping and `CipherMapper.mapContent`:
            // 2 is a secure note, 3 a card, 4 an identity. It did not, so the breakdown a person
            // reads while diagnosing a bad sync named the wrong types.
            let typeNames = [1: "login", 2: "secureNote", 3: "card", 4: "identity", 5: "sshKey"]
            let breakdown = typeCounts
                .sorted(by: { $0.key < $1.key })
                .map { "\(typeNames[$0.key] ?? "type\($0.key)")=\($0.value)" }
                .joined(separator: " ")
            logger.debug("[debug] cipher breakdown: \(breakdown, privacy: .public) org(skipped)=\(orgCount, privacy: .public)")
        }

        // Phase 2: Decrypt personal ciphers via the crypto service.
        progress(L("Decrypting %lld item(s)…", totalCiphers))

        var (items, failedCount, cipherKeyMap) = try await crypto.decryptList(ciphers: syncResponse.ciphers)
        logger.info("Decrypted \(items.count) cipher(s); \(failedCount) failure(s)")
        if DebugConfig.isEnabled && failedCount > 0 {
            logger.debug("[debug] \(failedCount, privacy: .public) cipher(s) failed to decrypt — check VitrineCryptoService logs for per-cipher errors")
        }

        // Phase 2b: Populate the per-cipher key cache from keys collected during decryptList.
        // Only ciphers with a per-item key are included; vault-key-only ciphers are handled
        // by VaultKeyServiceImpl's fallback path.
        try await requireLiveSession(epochToken)
        await vaultKeyCache.populate(keys: cipherKeyMap)
        logger.info("VaultKeyCache populated with \(cipherKeyMap.count, privacy: .public) per-item key(s)")

        // Phase 2b: Decrypt folder names.
        let (folders, folderFailedCount) = try await crypto.decryptFolders(folders: syncResponse.folders)
        logger.info("Decrypted \(folders.count, privacy: .public) folder(s); \(folderFailedCount, privacy: .public) failure(s)")
        if folderFailedCount > 0 {
            logger.error("decryptFolders: \(folderFailedCount, privacy: .public) folder(s) failed to decrypt")
        }

        // Phase 2c-0: the account's own public key, for the fingerprint phrase.
        //
        // Deliberately a separate block from the org unwrapping below rather than sharing its
        // decrypted key: the two have different conditions, and this one must run for accounts
        // with **no** organizations — which is exactly the case the org block skips, and exactly
        // the account that has no other reason for its key ever to be decrypted. Restructuring
        // the org phase around a shared buffer would have saved one AES-CBC decryption of about
        // 1.2 KB per sync, at the cost of moving a hundred lines.
        //
        // A failure is logged and skipped: it costs the user a settings row, whereas failing the
        // sync would cost them their whole vault over something that only gets displayed.
        if let encPrivateKey = syncResponse.profile.privateKey {
            do {
                let vaultKeys = try await crypto.currentKeys()
                var rsaPrivateKeyBytes = try await crypto.decryptRSAPrivateKey(
                    encPrivateKey: encPrivateKey,
                    vaultKeys: vaultKeys
                )
                defer { rsaPrivateKeyBytes.zeroize() }

                let spki = try await crypto.accountPublicKeySPKI(pkcs8PrivateKey: rsaPrivateKeyBytes)
                await accountKeyCache.store(publicKey: spki)
            } catch {
                logger.error("Could not derive the account public key — the fingerprint phrase will be unavailable: \(error, privacy: .public)")
            }
        }

        // Phase 2c: Unwrap org keys and decrypt collection names.
        //
        // Only performed when the sync response contains organizations AND the profile
        // has a privateKey field (i.e. the user has org membership). Vaultwarden instances
        // without org support will have an empty `organizations` array and skip this block.
        //
        // Security: the decrypted RSA private key bytes are zeroed immediately after use.
        // Reference: Bitwarden Security Whitepaper §4 — "Organization Key Wrapping".
        var organizations: [Organization] = []
        var collections: [OrgCollection] = []
        /// Per-item keys for org ciphers that carry their own. Filled during the org phase and
        /// merged into the key cache in the commit phase, so every write happens in one place.
        var orgCipherKeyMap: [String: Data] = [:]
        /// Org ciphers the org pass could not produce. Hoisted out of the block below because the
        /// result counts them together with the personal failures.
        var orgCipherFailedCount = 0

        if !syncResponse.organizations.isEmpty,
           let encPrivateKey = syncResponse.profile.privateKey {
            do {
                let vaultKeys = try await crypto.currentKeys()

                // Decrypt the user's RSA private key (PKCS#8 DER) from the sync profile.
                var rsaPrivateKeyBytes = try await crypto.decryptRSAPrivateKey(
                    encPrivateKey: encPrivateKey,
                    vaultKeys: vaultKeys
                )
                defer {
                    // Zero the private key bytes immediately after use.
                    rsaPrivateKeyBytes.zeroize()
                }

                // Unwrap each org key into OrgKeyCache.
                // Failure for a single org is logged and skipped; other orgs proceed.
                try await requireLiveSession(epochToken)
                await orgKeyCache.clear()  // Fresh slate for this sync.
                for rawOrg in syncResponse.organizations {
                    do {
                        let orgKeys = try await crypto.unwrapOrgKey(
                            encOrgKey: rawOrg.key,
                            rsaPrivateKey: rsaPrivateKeyBytes
                        )
                        await orgKeyCache.store(key: orgKeys, for: rawOrg.id)
                    } catch {
                        logger.fault("Failed to unwrap org key for org \(rawOrg.id.prefix(8), privacy: .public)… — org ciphers will be skipped: \(error, privacy: .public)")
                    }
                }

                // Build domain Organization entities.
                let orgKeysSnapshot = await orgKeyCache.snapshot()
                organizations = syncResponse.organizations.compactMap { (raw: RawOrganization) in
                    guard let role = OrgRole(rawValue: raw.type) else {
                        logger.error("Unknown org role type \(raw.type, privacy: .public) for org \(raw.id.prefix(8), privacy: .public)")
                        return nil
                    }
                    let org = Organization(id: raw.id, name: raw.name, role: role)
                    logger.info("Org \(raw.name, privacy: .public): type=\(raw.type, privacy: .public) role=\(String(describing: role), privacy: .public) canManage=\(org.canManageCollections, privacy: .public)")
                    return org
                }

                // Decrypt collection names using the respective org key.
                collections = syncResponse.collections.compactMap { raw in
                    guard let orgKey = orgKeysSnapshot[raw.organizationId] else {
                        logger.error("No org key for collection \(raw.id.prefix(8), privacy: .public) (org \(raw.organizationId.prefix(8), privacy: .public))")
                        return nil
                    }
                    do {
                        let encName = try EncString(string: raw.name)
                        let nameData = try encName.decrypt(keys: orgKey)
                        guard let name = String(data: nameData, encoding: .utf8) else {
                            logger.error("Collection name not valid UTF-8 for collection \(raw.id.prefix(8), privacy: .public)")
                            return nil
                        }
                        // `preserved` carries the collection's members, groups and external id. Dropping them
                        // here is what made a later rename send empty arrays — see
                        // `PreservedCollectionFields`.
                        return OrgCollection(id: raw.id, organizationId: raw.organizationId, name: name,
                                             preserved: raw.preserved)
                    } catch {
                        logger.error("Failed to decrypt collection name for \(raw.id.prefix(8), privacy: .public): \(error, privacy: .public)")
                        return nil
                    }
                }

                // Decrypt org ciphers using the unwrapped org keys.
                // Personal ciphers were already decrypted by `decryptList` above; org ciphers
                // were skipped there because org keys were not yet available at that point.
                // We do a second pass here, using the same CipherMapper with the org key snapshot.
                let orgMapper = CipherMapper()
                for (index, cipher) in syncResponse.ciphers.enumerated() {
                    guard cipher.organizationId != nil else { continue }
                    do {
                        let (item, cipherKey) = try orgMapper.map(
                            raw: cipher, vaultKeys: vaultKeys, orgKeys: orgKeysSnapshot
                        )
                        items.append(item)
                        if cipher.key != nil { orgCipherKeyMap[cipher.id] = cipherKey }
                    } catch CipherMapperError.organisationCipherSkipped {
                        // Org key not in snapshot — org key unwrap failed for this org.
                        orgCipherFailedCount += 1
                        if DebugConfig.isEnabled {
                            logger.debug("[debug] org cipher[\(index, privacy: .public)] skipped — org key unavailable")
                        }
                    } catch {
                        orgCipherFailedCount += 1
                        logger.error("Org cipher decryption failed at index \(index, privacy: .public): \(error, privacy: .public)")
                    }
                }
                // Keys for ciphers that carry their own are merged into the cache in the commit
                // phase below, together with the personal ones — so every write this sync makes
                // happens in one place, behind one liveness check, rather than being scattered
                // through the phases it belongs to.
                logger.info("Org sync: \(organizations.count) org(s), \(collections.count) collection(s), \(orgCipherFailedCount, privacy: .public) org cipher(s) skipped")
            } catch {
                logger.error("Org key sync failed — org ciphers unavailable this session: \(error, privacy: .public)")
                // Non-fatal: personal items still work without org support.
            }
        }

        // Phase 3: Commit. Everything this sync writes is here, behind a single liveness check.
        //
        // Placing the check at the top of the commit — rather than only after the fetch — closes
        // the window in which a session ends during the decryption of a large vault, which is
        // hundreds of milliseconds of work. A write that passes this check and then lands while a
        // lock is clearing the same store is still possible in principle; it is microseconds of
        // synchronous code, and what would remain is key bytes in a cache that no unlocked code
        // path can read, since the crypto service refuses to hand out keys once locked.
        try await requireLiveSession(epochToken)

        await vaultKeyCache.populate(keys: cipherKeyMap.merging(orgCipherKeyMap) { _, new in new })

        let syncedAt = Date()
        await vaultRepository.populate(
            items:         items,
            folders:       folders,
            organizations: organizations,
            collections:   collections,
            syncedAt:      syncedAt
        )

        // Phase 4: Keep the payload for the next unlock without a network.
        //
        // Only a server response is written, and only after the populate above has succeeded. A
        // cache-sourced run has nothing new to store, and a failed run — which has already thrown
        // by this point — must never overwrite a good cache with a partial one. That ordering is
        // what makes "a failed sync does not damage the cache" true by construction rather than by
        // remembering to check.
        if fetched.source == .server, let body = fetched.body {
            await persistPayload(body, writtenAt: syncedAt)
        }

        return SyncResult(
            syncedAt:              syncedAt,
            totalCiphers:          totalCiphers,
            // Personal and organisation failures, summed. They are counted by different code paths —
            // the personal pass skips org ciphers outright, and the org pass keeps its own local
            // tally — and only the total is honest: the user sees one list, so a number that covers
            // half of it would under-report exactly the thing it exists to report.
            failedDecryptionCount: failedCount + orgCipherFailedCount,
            source:                fetched.source,
            payloadTimestamp:      fetched.payloadTimestamp
        )
    }

    // MARK: - Private

    /// Refuses to go further if the session this sync belongs to has ended.
    ///
    /// Called before each group of writes. The alternative — checking once — cannot cover a sync
    /// that spans a vault lock, because the check would have to be either before the work (too
    /// early to catch a lock during it) or after (too late: the writes have happened).
    ///
    /// - Throws: `SyncError.sessionEnded`, which is not a failure to report: it is the correct
    ///   outcome of a race that the teardown won, and naming it keeps it out of the log as a fake
    ///   network problem.
    private func requireLiveSession(_ token: Int) async throws {
        guard await sessionEpoch.isCurrent(token) else {
            logger.info("Sync abandoned: the session ended while it was in flight")
            throw SyncError.sessionEnded
        }
    }

    /// A vault payload to populate from, and where it came from.
    private struct FetchedVault {
        let response:         SyncResponse
        /// The server's bytes. Present only for a live fetch; there is nothing to re-cache when
        /// the payload came out of the cache.
        let body:             Data?
        let source:           SyncSource
        /// When the data was fetched from the server.
        let payloadTimestamp: Date
    }

    /// Fetches the vault, falling back to the cached payload when the server cannot be reached.
    ///
    /// The split that matters: fall back when the request **could not be completed**, never when
    /// the server **answered**. A rejection or an unreadable response is information about the
    /// session or the client, and substituting cached data for it would replace that information
    /// with a screen that looks like a normal offline unlock.
    private func fetchVault() async throws -> FetchedVault {
        do {
            let (response, body) = try await apiClient.fetchSyncPayload()
            return FetchedVault(
                response: response, body: body, source: .server, payloadTimestamp: Date()
            )
        } catch let err as APIError {
            switch err {
            case .httpError(statusCode: 401, _):
                throw SyncError.unauthorized

            case .httpError(let statusCode, _) where (400..<500).contains(statusCode):
                // The server decided something about this request. Report it; do not paper over it.
                logger.error("Sync request rejected with HTTP \(statusCode, privacy: .public)")
                throw SyncError.networkUnavailable

            case .httpError:
                // 5xx: the server answered, but it could not serve the vault. Indistinguishable to
                // the user from an outage, which is the case the cache is for.
                return try await loadFromCache(replacing: SyncError.networkUnavailable)

            case .decodingFailed, .baseURLNotSet, .serverTrustRefused, .staleCopy:
                // A trust refusal is deliberately in this group. It is the one failure where
                // quietly serving last week's vault could hide an active interception, and the app
                // already has a screen for resolving it.
                //
                // `staleCopy` is here for the same rule rather than for its relevance to syncing:
                // it means the server answered and refused, so the cache must not stand in for the
                // answer. A sync request cannot carry a `lastKnownRevisionDate`, so it should not
                // arise on this path at all — the case is listed so that adding it to `APIError`
                // could not have left this switch deciding by accident.
                throw SyncError.networkUnavailable
            }
        } catch {
            // No response at all: offline, DNS, connection refused, timeout.
            return try await loadFromCache(replacing: SyncError.networkUnavailable)
        }
    }

    /// Populates from the cached payload for the signed-in account, or rethrows `originalError`.
    ///
    /// `originalError` is what the user is told when there is nothing usable to fall back to. The
    /// network failure is the reason the cache was needed, so it is the honest thing to report —
    /// an empty vault is not.
    private func loadFromCache(replacing originalError: SyncError) async throws -> FetchedVault {
        guard let userId = await currentUserId(), let serverURL = await apiClient.baseURL else {
            logger.error("Vault unreachable and no account identity to look up a cache for")
            throw originalError
        }

        let identity = VaultCacheIdentity(userId: userId, serverURL: serverURL)
        guard let payload = await vaultCache.read(identity: identity) else {
            logger.error("Vault unreachable and no cached payload is available")
            throw originalError
        }

        let response: SyncResponse
        do {
            // Same decoder configuration as `PrizmAPIClientImpl.decode`: a plain `JSONDecoder`
            // with no key or date strategies. `SyncResponse` handles the casing variants itself.
            response = try JSONDecoder().decode(SyncResponse.self, from: payload.body)
        } catch {
            logger.error("Cached payload could not be decoded; treating it as absent")
            throw originalError
        }

        logger.info("Populating from the cached vault payload written \(payload.writtenAt, privacy: .public)")
        return FetchedVault(
            response: response, body: nil, source: .cache, payloadTimestamp: payload.writtenAt
        )
    }

    /// Stores the server's bytes for the signed-in account. Best-effort — see `VaultCacheStore`.
    private func persistPayload(_ body: Data, writtenAt: Date) async {
        guard let userId = await currentUserId(), let serverURL = await apiClient.baseURL else {
            logger.error("No account identity available; vault payload not cached")
            return
        }
        await vaultCache.write(
            identity: VaultCacheIdentity(userId: userId, serverURL: serverURL),
            payload:  VaultCachePayload(body: body, writtenAt: writtenAt)
        )
    }
}
