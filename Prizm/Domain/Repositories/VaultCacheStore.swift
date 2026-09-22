import Foundation

// MARK: - VaultCacheIdentity

/// Which account a cached vault payload belongs to.
///
/// Both fields are part of the identity because either one alone is ambiguous: the same user id
/// on a different server is a different vault, and two accounts on one server are two vaults.
nonisolated struct VaultCacheIdentity: Equatable, Sendable {
    /// The account's user id. Also the directory the payload is stored under.
    let userId: String

    /// The server the payload was fetched from.
    let serverURL: URL
}

// MARK: - VaultCachePayload

/// A cached `/api/sync` response body.
nonisolated struct VaultCachePayload: Equatable, Sendable {
    /// The response body **exactly as the server sent it**.
    ///
    /// Not a re-encoding of `SyncResponse`: re-encoding writes back only the fields the model
    /// decodes, so any field Prizm does not yet model would be silently destroyed in the cache.
    /// The cached copy has to be able to lose nothing the server sent.
    let body: Data

    /// When this payload was fetched from the server.
    let writtenAt: Date
}

// MARK: - VaultCacheStore

/// Persists the server's encrypted vault payload so that a vault can be opened with no network.
///
/// **What this holds.** The `/api/sync` response as received — item names, usernames, passwords,
/// notes, TOTP seeds, SSH keys and attachment metadata, every field of which is already an
/// `EncString` in the server's own format. No plaintext, no key, and no attachment blob is stored
/// here, so the file is not readable without the master password or the biometric Keychain item,
/// exactly like the live vault.
///
/// **Why it does not throw.** Both operations are best-effort by contract. A cache that cannot be
/// written must not fail the sync that produced it — trading a working vault for a stale one to
/// report a disk problem is the wrong side of that trade. A cache that cannot be read must be
/// indistinguishable from an absent one, so that the caller reports the network failure that made
/// the read necessary rather than an error from the cache. Implementations log their failures.
///
/// Implemented by `VaultCacheStoreImpl` in the Data layer.
protocol VaultCacheStore: Actor {

    /// Stores `payload` as the cache for `identity`, replacing any payload already stored for it.
    ///
    /// If the write cannot be completed, the previously cached payload is left as it was.
    func write(identity: VaultCacheIdentity, payload: VaultCachePayload) async

    /// The cached payload for `identity`.
    ///
    /// - Returns: `nil` when there is no payload for this account, when what is stored cannot be
    ///   read (truncated, not JSON, written by an unknown schema version), or when it was written
    ///   for a different server than `identity.serverURL`.
    func read(identity: VaultCacheIdentity) async -> VaultCachePayload?

    /// Removes everything stored for `userId`.
    ///
    /// Called on sign-out, and not on lock: locking zeroes the keys, which is what makes the
    /// cached ciphertext unreadable, and deleting it would defeat the purpose of having it.
    func delete(userId: String) async
}
