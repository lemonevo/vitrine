import Foundation
import LocalAuthentication
@testable import Prizm

final class MockBiometricKeychainService: BiometricKeychainService {
    private var store: [String: Data] = [:]
    var readError: Error?
    var writeError: Error?
    /// Deletion had no failure hook, which is how "the key could not be removed" stayed a branch no
    /// test could reach — and that branch is the difference between "Touch ID is off" and a vault key
    /// that a fingerprint still unlocks.
    var deleteError: Error?
    /// Defaults to the strong path; set to `false` to cover an unsigned build.
    var stubbedIsSystemEnforced: Bool = true

    var isSystemEnforced: Bool { stubbedIsSystemEnforced }

    func writeBiometric(data: Data, key: String) throws {
        if let err = writeError { throw err }
        store[key] = data
    }

    func readBiometric(key: String) async throws -> Data {
        if let err = readError { throw err }
        guard let data = store[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func readBiometric(key: String, context: LAContext) async throws -> Data {
        if let err = readError { throw err }
        guard let data = store[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func deleteBiometric(key: String) throws {
        if let err = deleteError { throw err }
        store.removeValue(forKey: key)
    }
}
