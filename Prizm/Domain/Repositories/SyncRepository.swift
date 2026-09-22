import Foundation

/// Fetches the encrypted vault from the server and populates the in-memory store.
/// Called once per unlock event (after login and after every relaunch + unlock).
/// No background sync, periodic polling, or user-triggered re-sync in v1.
/// Implemented by `SyncRepositoryImpl` in the Data layer.
protocol SyncRepository: Actor {

    /// Syncs the vault from the server.
    ///
    /// Sequence:
    /// 1. GET `/sync?excludeDomains=true` → encrypted JSON.
    /// 2. Decrypt each cipher via `PrizmCryptoServiceImpl`.
    /// 3. Populate `VaultRepositoryImpl` in-memory store.
    ///
    /// When the server cannot be **reached**, the locally cached payload is used instead and the
    /// result reports `source == .cache`. A failure the server itself reported (a rejected session,
    /// a key failure) is never served from the cache: that would hide an expired session, or mask a
    /// wrong key, behind a screen that looks like a normal sync.
    ///
    /// - Parameter progress: Callback fired with human-readable status messages
    ///   (minimum: "Syncing vault…" then "Decrypting…"). Called on the calling actor.
    /// - Returns: `SyncResult` with counts of synced and failed ciphers, and the source of the data.
    /// - Throws: `SyncError` on catastrophic failure. When the server is unreachable and no usable
    ///   cache exists, the transport error is thrown — never an empty vault. Individual cipher
    ///   failures are skipped and counted in `SyncResult.failedDecryptionCount`.
    func sync(progress: @Sendable @escaping (String) -> Void) async throws -> SyncResult
}

// MARK: - Supporting types

/// Where a sync's data came from.
nonisolated enum SyncSource: Equatable, Sendable {
    /// Fetched from the server during this call.
    case server
    /// Read from the locally cached payload because the server could not be reached.
    case cache
}

nonisolated struct SyncResult {
    /// When this sync completed.
    let syncedAt: Date
    let totalCiphers: Int

    /// How many of the vault's items this sync could not produce — personal **and** organisation.
    ///
    /// An item lands here when it cannot be decrypted or mapped: an unhandled cipher type, a field
    /// that fails to decrypt, a per-item key that will not unwrap, or an organisation item whose org
    /// key could not be unwrapped. All of them present to the user the same way — an item that is not
    /// in the list — so they are one number.
    ///
    /// It is a count and not a list because the item's *name* is encrypted too: an item that cannot
    /// be read cannot be named, so there is nothing to list until it can be.
    let failedDecryptionCount: Int
    /// Where the data came from. Callers that display freshness must consult this: a
    /// cache-sourced result carries data that is older than `syncedAt` says.
    let source: SyncSource

    /// When the data was fetched **from the server**. Equal to `syncedAt` for a live sync; for a
    /// cache-sourced sync this is when the cached payload was originally fetched, which is the
    /// only honest thing to show the user.
    let payloadTimestamp: Date

    /// `source` and `payloadTimestamp` default to a live sync, so constructing a result in a test
    /// does not have to say "this came from the server" every time.
    init(
        syncedAt: Date,
        totalCiphers: Int,
        failedDecryptionCount: Int,
        source: SyncSource = .server,
        payloadTimestamp: Date? = nil
    ) {
        self.syncedAt              = syncedAt
        self.totalCiphers          = totalCiphers
        self.failedDecryptionCount = failedDecryptionCount
        self.source                = source
        self.payloadTimestamp      = payloadTimestamp ?? syncedAt
    }
}

nonisolated enum SyncError: Error, LocalizedError, Equatable {
    case networkUnavailable
    case serverUnreachable(URL)
    /// Access token is invalid or expired; user must sign in again.
    case unauthorized
    /// Symmetric key decryption failed catastrophically (not per-cipher).
    case decryptionFailed
    /// A second `sync()` call arrived while one is already in flight.
    case syncInProgress
    /// The session this sync belonged to ended — the vault was locked or the user signed out —
    /// before it completed. Nothing was written.
    ///
    /// Not a failure to report. It is the correct outcome of a race that the teardown won, and
    /// naming it is what keeps it out of the log as a fake network problem.
    case sessionEnded

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return L("No internet connection. Check your network connection.")
        case .serverUnreachable(let url):
            return L("Cannot reach %@. Verify the URL and check your connection.", url.host ?? url.absoluteString)
        case .unauthorized:
            return L("Your session has expired. Try signing out and signing in again.")
        case .decryptionFailed:
            return L("Failed to decrypt your vault. Please sign in again.")
        case .syncInProgress:
            return L("Sync is already in progress.")
        case .sessionEnded:
            return L("The vault was locked before the sync finished.")
        }
    }
}
