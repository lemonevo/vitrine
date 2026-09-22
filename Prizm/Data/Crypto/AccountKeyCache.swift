import Foundation
import os.log

// MARK: - AccountKeyCache

/// The one piece of the account's own key pair the fingerprint needs, held for the length of an
/// unlocked session.
///
/// **Only the public key is stored.** Unlike `OrgKeyCache` there is no zeroing on `clear()`: a
/// public key is published by definition, and zeroing it would imply a secrecy it does not have.
/// What makes clearing necessary is not secrecy but *scope* — the phrase is derived from vault
/// material obtained while unlocked, and a window that still shows it after a lock is showing
/// something the user has just asked to put away.
///
/// The value is captured at sync time rather than recomputed on demand because the input is the
/// **encrypted** private key in the sync response, which is not retained anywhere. Deriving it
/// later would mean either keeping ciphertext around or re-deriving from a key that has been
/// zeroed.
actor AccountKeyCache {

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "AccountKeyCache")

    /// The account's RSA public key, SPKI DER — the exact bytes the reference hashes.
    private var publicKey: Data?

    func store(publicKey: Data) {
        self.publicKey = publicKey
        logger.info("AccountKeyCache: stored the account public key (\(publicKey.count, privacy: .public) bytes)")
    }

    func current() -> Data? {
        publicKey
    }

    /// Called from the same teardown that clears `VaultKeyCache` and `OrgKeyCache`.
    func clear() {
        publicKey = nil
        logger.info("AccountKeyCache: cleared")
    }
}
