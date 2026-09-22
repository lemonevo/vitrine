import Foundation
@testable import Prizm

/// In-memory test double for `VaultCacheStore`.
///
/// Records what was written so a test can assert on the payload the sync produced, and serves a
/// configurable payload so the fallback paths can be exercised without touching the disk.
actor MockVaultCacheStore: VaultCacheStore {

    // MARK: - State observations
    // nonisolated(unsafe) allows tests to read/write without await — safe in single-threaded tests.

    nonisolated(unsafe) var writes: [(identity: VaultCacheIdentity, payload: VaultCachePayload)] = []
    nonisolated(unsafe) var writeCallCount: Int = 0
    nonisolated(unsafe) var readCallCount: Int = 0
    nonisolated(unsafe) var deletedUserIds: [String] = []

    // MARK: - Stubs

    /// What `read` returns. `nil` means "no cache", which is the default — most tests are about the
    /// server path and would rather not accidentally fall back.
    nonisolated(unsafe) var stubbedRead: VaultCachePayload?

    // MARK: - VaultCacheStore

    func write(identity: VaultCacheIdentity, payload: VaultCachePayload) async {
        writeCallCount += 1
        writes.append((identity, payload))
    }

    func read(identity: VaultCacheIdentity) async -> VaultCachePayload? {
        readCallCount += 1
        return stubbedRead
    }

    func delete(userId: String) async {
        deletedUserIds.append(userId)
    }
}
