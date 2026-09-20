import Foundation

// MARK: - ServerTrustStore

/// Persists the trust configuration for each server, keyed by host.
///
/// Host-keyed, not global, because the trust is *for a server*: pointing the app at a different
/// server must not inherit material the user granted for the previous one, and forgetting one
/// server must leave the others alone.
protocol ServerTrustStore: Sendable {

    /// The configuration recorded for `host`, or `.empty` when nothing has been recorded.
    func configuration(forHost host: String) async throws -> ServerTrustConfiguration

    /// Records `configuration` for `host`, replacing whatever was there.
    func save(_ configuration: ServerTrustConfiguration, forHost host: String) async throws

    /// Discards everything recorded for `host`. No-ops when nothing was recorded.
    func removeConfiguration(forHost host: String) async throws
}
