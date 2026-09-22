import Foundation
import Security
@testable import Prizm

/// `errSecUnavailable` — what the real Keychain returns when it is busy or otherwise refusing an
/// operation. Spelled as a number because the constant is not in scope for this target on the current
/// SDK.
private let keychainUnavailable: OSStatus = -25314

/// Test double for `KeychainService`.
///
/// Uses an in-memory dictionary instead of the real macOS Keychain.
/// Records which keys were deleted so tests can assert on `signOut` cleanup.
///
/// `@unchecked Sendable` because `KeychainService` is now `Sendable` — a TLS challenge reads trust
/// material through it off the main actor. The dictionary is only touched from the test's own
/// actor, which is the same guarantee the real implementation makes with its lock.
final class MockKeychainService: KeychainService, @unchecked Sendable {

    // MARK: - In-memory store

    private var store: [String: Data] = [:]

    // MARK: - Observation

    private(set) var deletedKeys: Set<String> = []
    private(set) var writtenKeys: [String]    = []
    /// All keys passed to read(key:), in call order. Used to assert no duplicate reads.
    private(set) var readKeys:   [String]     = []

    // MARK: - Failure stubbing

    /// Keys whose write or delete should fail.
    ///
    /// Exists because the security-relevant behaviour of `KeychainPinUnlockService` lives entirely in
    /// what it does when the Keychain says no: a PIN whose attempt counter cannot be written has no
    /// limit, and a wrapped key that cannot be deleted is still unlockable by guessing. Without these
    /// the failure branches are unreachable in tests, which is how they stayed wrong.
    var failingWrites:  Set<String> = []
    var failingDeletes: Set<String> = []

    // MARK: - KeychainService

    func read(key: String) throws -> Data {
        readKeys.append(key)
        guard let value = store[key] else {
            throw KeychainError.itemNotFound
        }
        return value
    }

    func write(data: Data, key: String) throws {
        if failingWrites.contains(key) { throw KeychainError.unexpectedStatus(keychainUnavailable) }
        store[key] = data
        writtenKeys.append(key)
    }

    func delete(key: String) throws {
        if failingDeletes.contains(key) { throw KeychainError.unexpectedStatus(keychainUnavailable) }
        deletedKeys.insert(key)
        store.removeValue(forKey: key)
    }

    // MARK: - Test helpers

    /// Pre-seeds a value for tests that need to read from Keychain without going through write.
    func seed(key: String, value: String) {
        store[key] = value.data(using: .utf8)!
    }

    /// Pre-seeds raw Data for tests.
    func seed(key: String, data: Data) {
        store[key] = data
    }
}
