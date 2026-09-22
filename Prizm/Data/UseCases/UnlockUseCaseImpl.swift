import Foundation
import os.log

// MARK: - UnlockUseCaseImpl

/// Orchestrates the vault unlock flow (User Story 2):
///   1. Call `AuthRepository.unlockWithPassword` — purely local KDF, no network.
///   2. On success, call `SyncRepository.sync` to populate the in-memory vault (empty after
///      every app launch).
///
/// The sync is **not** the unlock: the master password was already verified in step 1, locally.
/// When the server cannot be reached, step 2 is answered from the cached payload and the flow
/// succeeds with the vault as it was last fetched — that is what makes an unlock possible with no
/// network at all. A `SyncResult` reporting `.cache` is therefore a successful unlock, not a
/// degraded one, and only a sync with nothing usable behind it (no cache, a rejected session, or a
/// decryption failure) is an error.
///
/// On wrong password: `AuthError.invalidCredentials` is thrown and the vault stays locked.
/// `lockVault` is intentionally NOT called on failure — the existing locked session is
/// preserved so the user can retry without re-entering their server URL or re-authenticating.
/// The crypto service keys remain zeroed (they are never populated on a failed attempt),
/// so no vault data is exposed between retry attempts.
final class UnlockUseCaseImpl: UnlockUseCase {

    private let auth: any AuthRepository
    private let sync: any SyncRepository

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "UnlockUseCase")

    init(auth: any AuthRepository, sync: any SyncRepository) {
        self.auth = auth
        self.sync = sync
    }

    func execute(masterPassword: Data) async throws -> Account {
        // Step 1: Derive master key locally and unlock the crypto service.
        logger.info("Attempting vault unlock")
        let account = try await auth.unlockWithPassword(masterPassword)

        // Step 2: Re-sync vault — in-memory store is empty after every app launch.
        logger.info("Unlock succeeded — re-syncing vault for \(account.userId, privacy: .private)")
        _ = try await sync.sync(progress: { _ in })

        return account
    }
}
