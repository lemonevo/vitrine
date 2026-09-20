import Foundation

// MARK: - ServerTrustConfiguration

/// The trust a user has configured for one server: an optional private authority, and an optional
/// pinned leaf certificate.
///
/// Neither value is a secret, and that is exactly why both live in the Keychain rather than in
/// `UserDefaults` (design D8): they are the *inputs to a trust decision*, and a process running as
/// the user can rewrite `UserDefaults` with a single `defaults write` — which would let it add its
/// own certificate authority and then read everything the vault sends.
///
/// Everything is scoped to one host. See `ServerTrustPolicy`.
nonisolated struct ServerTrustConfiguration: Equatable, Sendable, Codable {

    /// DER-encoded certificates to use as the **only** anchors when evaluating this server's chain.
    var trustedCACertificates: [Data] = []

    /// SHA-256 of the leaf certificate this server is expected to present, hex-encoded.
    /// Nil until one has been recorded.
    var pinnedLeafSHA256: String?

    /// Whether pinning is armed for this server.
    ///
    /// Separate from `pinnedLeafSHA256` being non-nil because the two change independently: turning
    /// the setting off must not destroy a recorded pin the user may want back, and turning it on
    /// with nothing recorded is the trust-on-first-use case.
    var pinningEnabled: Bool = false

    /// Nothing configured: no authority, no pin, pinning off.
    var isEmpty: Bool {
        trustedCACertificates.isEmpty && pinnedLeafSHA256 == nil && !pinningEnabled
    }

    static let empty = ServerTrustConfiguration()
}

// MARK: - ServerTrustDecision

/// What the policy concludes about one connection to one host.
///
/// A pure value so the rule can be unit-tested without a TLS server. See `ServerTrustPolicy`.
nonisolated enum ServerTrustDecision: Equatable, Sendable {

    /// Not the configured server, or nothing configured for it. Let the system evaluate.
    case useDefaultHandling

    /// Evaluate this server's chain.
    ///
    /// - `anchors` empty means the system's own anchors are used — pinning can be configured
    ///   without a private authority.
    /// - `pin` says what to do about the recorded fingerprint.
    case evaluate(anchors: [Data], pin: ServerTrustPinCheck)
}

/// The pin half of a decision.
nonisolated enum ServerTrustPinCheck: Equatable, Sendable {
    /// Pinning is off for this server. The anchors decide on their own.
    case disabled
    /// Pinning is armed and nothing is recorded yet: accept, and record this fingerprint.
    case record(String)
    /// The certificate presented is the recorded one.
    case matches
    /// The certificate changed. Refuse, with an error that says so rather than a generic network
    /// failure — "connection failed" would send the user looking at their network when the real
    /// answer is that the server's certificate is not the one it used to be.
    case mismatch

    /// Pinning is armed but the leaf's fingerprint could not be computed, so there is nothing to
    /// compare against and nothing to record. Refuse rather than accept: an accepted connection
    /// that recorded no pin would be indistinguishable from a pin that was checked and passed.
    case undetermined
}
