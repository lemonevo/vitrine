import Foundation
import LocalAuthentication

/// How the biometric gate on a stored item is enforced.
enum BiometricStorageMode: Equatable {

    /// The item carries a `.biometryCurrentSet` access control on the data-protection
    /// Keychain, so macOS itself refuses to release the bytes without a successful
    /// biometric evaluation — and invalidates the item when enrollment changes.
    ///
    /// This is the design of record (design Decision 2). It needs the
    /// `keychain-access-groups` entitlement, so only a build signed with a real Team ID
    /// can use it.
    case systemEnforced

    /// The item lives in the legacy login Keychain with no access control, and Prizm
    /// evaluates the biometric policy in-process before every read.
    ///
    /// The prompt the user sees is identical; what differs is who enforces it. macOS
    /// will release the bytes to any process already on the item's ACL, so the gate is
    /// only as strong as this process. Used when `systemEnforced` is impossible, and
    /// reported to Settings rather than silently substituted.
    case appEnforced
}

/// Evaluates the biometric policy that gates a Keychain read.
///
/// Injected rather than called inline so the SecItem code paths stay exercisable
/// without enrolled biometrics — a test runner must not raise a Touch ID prompt.
protocol BiometricPolicyEvaluating {
    /// Runs the system biometric prompt and returns the context that answered it, so the
    /// same evaluation can be handed to `SecItemCopyMatching` via
    /// `kSecUseAuthenticationContext` instead of being performed twice.
    ///
    /// - Parameter reason: The line the user reads in that system dialog.
    func evaluate(reason: String) async throws -> LAContext
}

/// The system's own Touch ID / Face ID prompt.
struct SystemBiometricPolicyEvaluator: BiometricPolicyEvaluating {
    func evaluate(reason: String) async throws -> LAContext {
        let context = LAContext()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { _, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }
        return context
    }
}

/// Provides biometric-gated read, write, and delete access to the macOS Keychain.
///
/// Separate from `KeychainService` because `kSecAccessControl` (used here for
/// `.biometryCurrentSet`) and `kSecAttrAccessible` (used by `KeychainServiceImpl`)
/// are mutually exclusive on the same SecItem — see design Decision 3.
///
/// This is a Data-layer implementation detail consumed only by `AuthRepositoryImpl`.
/// It MUST NOT be placed in the Domain layer.
protocol BiometricKeychainService {
    /// Whether macOS itself enforces the biometric gate on the stored item.
    ///
    /// `true` only when the item carries a `.biometryCurrentSet` access control, which
    /// needs the `keychain-access-groups` entitlement. When `false` the Touch ID prompt
    /// is identical but Prizm evaluates it, so the protection is only as strong as this
    /// process — callers surface which of the two is in force instead of assuming.
    var isSystemEnforced: Bool { get }

    /// Write `data` for `key` behind a biometric access control gate.
    func writeBiometric(data: Data, key: String) throws
    /// Read and return the data stored for `key`, triggering biometric authentication.
    /// - Throws: `KeychainError.itemNotFound` if no item exists.
    func readBiometric(key: String) async throws -> Data

    /// Delete the item for `key`. No-ops silently when the item does not exist.
    func deleteBiometric(key: String) throws
}
