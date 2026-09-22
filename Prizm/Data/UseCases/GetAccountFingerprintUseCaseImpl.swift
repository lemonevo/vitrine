import Foundation
import os.log

/// Reads the two inputs the phrase needs and hands them to the pure function.
///
/// A `class` rather than a `nonisolated struct` because `AuthRepository` is not `Sendable` — the
/// same reason `VerifyMasterPasswordUseCaseImpl` is a class. A value type could not hold the
/// dependency without either lying about thread safety or forcing a conformance that does not hold.
///
/// Both inputs are looked up at call time rather than captured: the account can be signed out and
/// into a different one, and the public key arrives with a sync that may not have happened when
/// this object was created.
final class GetAccountFingerprintUseCaseImpl: GetAccountFingerprintUseCase {

    private let auth:            any AuthRepository
    private let accountKeyCache: AccountKeyCache
    private let wordList:        [String]

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "AccountFingerprint")

    init(auth:            any AuthRepository,
         accountKeyCache: AccountKeyCache,
         wordList:        [String]) {
        self.auth            = auth
        self.accountKeyCache = accountKeyCache
        self.wordList        = wordList
    }

    func execute() async throws -> String? {
        guard let account = auth.storedAccount() else { return nil }
        guard let publicKey = await accountKeyCache.current() else {
            logger.info("No account public key cached — a sync has not completed yet")
            return nil
        }

        // The user id, not the email. The reference hashes the account identifier; using the email
        // produces a phrase that looks entirely correct and matches no other client, which is the
        // one failure mode this feature cannot survive.
        return try AccountFingerprintPhrase.phrase(
            material:  account.userId,
            publicKey: publicKey,
            wordList:  wordList
        )
    }
}
