import Foundation
import os.log

// MARK: - KeychainServerTrustStore

/// `ServerTrustStore` backed by the same Keychain record the session uses.
///
/// It writes into `KeychainService` rather than opening its own `SecItem` calls because that
/// service already guarantees the two properties the spec asks for —
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and never synchronisable — and a second
/// implementation of the same storage rules is a second place for them to drift. Reusing it also
/// keeps the count of Keychain items at one, which is what keeps a rebuild down to a single
/// authorisation prompt (see `KeychainServiceImpl`).
///
/// The values are not secrets, and they go in the Keychain anyway: they are the inputs to a trust
/// decision, and `UserDefaults` can be rewritten by any process running as the user with one
/// `defaults write`.
nonisolated final class KeychainServerTrustStore: ServerTrustStore {

    private let keychain: any KeychainService
    private let logger = Logger(subsystem: "com.prizm", category: "ServerTrustStore")

    init(keychain: any KeychainService) {
        self.keychain = keychain
    }

    // MARK: - ServerTrustStore

    func configuration(forHost host: String) async throws -> ServerTrustConfiguration {
        let data: Data
        do {
            data = try keychain.read(key: Self.key(for: host))
        } catch KeychainError.itemNotFound {
            // Nothing recorded is a normal state, not a fault: every server starts this way and
            // the policy treats it as "use the default handling".
            return .empty
        }
        do {
            return try JSONDecoder().decode(ServerTrustConfiguration.self, from: data)
        } catch {
            // A value that cannot be decoded is not "nothing recorded". Returning .empty here
            // would silently downgrade a configured server to default handling — the fail-open
            // direction — so it surfaces instead, and the delegate refuses the connection.
            logger.error("Stored trust configuration for \(host, privacy: .public) is unreadable")
            throw ServerTrustError.configurationUnreadable(host: host, reason: error.localizedDescription)
        }
    }

    func save(_ configuration: ServerTrustConfiguration, forHost host: String) async throws {
        let data = try JSONEncoder().encode(configuration)
        try keychain.write(data: data, key: Self.key(for: host))
    }

    func removeConfiguration(forHost host: String) async throws {
        try keychain.delete(key: Self.key(for: host))
    }

    // MARK: - Keys

    /// Normalised so that `vault.example.com` and `VAULT.example.com.` address one entry, and so
    /// that forgetting one spelling does not leave the other behind.
    private static func key(for host: String) -> String {
        "serverTrust.\(ServerTrustPolicy.normalize(host))"
    }
}

