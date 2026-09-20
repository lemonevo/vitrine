import Foundation

// MARK: - ServerTrustPolicy

/// The whole of Prizm's server-trust rule, as a pure function (design D8).
///
/// Nothing here touches `SecTrust`, a socket, or the network. It is a function from four values to
/// one enum, which is what makes it testable: a unit test cannot stand up a TLS server with a
/// private certificate authority, and faking `SecTrust` would test the fake. `ServerTrustDelegate`
/// is the thin adapter that feeds this function and carries out what it returns.
///
/// The counterpart limitation is stated plainly rather than buried: **the TLS handshake itself is
/// not covered by any test in this project.** What is covered is every branch of the rule that
/// decides what the handshake is asked to do.
nonisolated enum ServerTrustPolicy {

    /// - Parameters:
    ///   - host: The host being connected to, as `URLProtectionSpace` reports it.
    ///   - configuredHost: The host of the server the user configured. Nil when none is set yet.
    ///   - configuration: What the user has recorded for their own server.
    ///   - observedLeafSHA256: SHA-256 of the leaf certificate this connection presented, hex.
    ///     Nil when the chain has no leaf to read.
    static func decide(host:               String,
                       configuredHost:     String?,
                       configuration:      ServerTrustConfiguration,
                       observedLeafSHA256: String?) -> ServerTrustDecision {

        // Scoped to one host on purpose. The blob endpoint an attachment download redirects to is
        // a different host with a perfectly valid public certificate; applying the user's private
        // authority to it would break downloads, and pinning it would pin a host they never chose.
        guard let configuredHost, Self.normalize(host) == Self.normalize(configuredHost) else {
            return .useDefaultHandling
        }

        guard !configuration.isEmpty else { return .useDefaultHandling }

        return .evaluate(anchors: configuration.trustedCACertificates,
                         pin: Self.pinCheck(configuration: configuration,
                                            observedLeafSHA256: observedLeafSHA256))
    }

    // MARK: - Pinning

    private static func pinCheck(configuration:      ServerTrustConfiguration,
                                 observedLeafSHA256: String?) -> ServerTrustPinCheck {
        guard configuration.pinningEnabled else { return .disabled }
        guard let observed = observedLeafSHA256 else { return .undetermined }

        guard let recorded = configuration.pinnedLeafSHA256 else {
            // Trust on first use: accept, and remember what was seen.
            return .record(observed)
        }

        // Not constant-time, deliberately. The value being compared is the hash of a certificate
        // the server publishes to anyone who connects — there is no secret here to leak, and
        // `ConstantTimeCompare` exists for the master-password comparison, which does have one.
        return observed.lowercased() == recorded.lowercased() ? .matches : .mismatch
    }

    // MARK: - Hosts

    /// Lowercased, without a trailing dot and without a port.
    ///
    /// `URLProtectionSpace.host` carries no port, but the configured server URL does, and a pin
    /// recorded for `vault.example.com:443` that failed to match `vault.example.com` would be a
    /// lockout caused by punctuation.
    static func normalize(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix(".") { value.removeLast() }
        // An IPv6 literal carries several colons; exactly one is a port separator.
        guard value.filter({ $0 == ":" }).count == 1, let name = value.split(separator: ":").first
        else { return value }
        return String(name)
    }
}

// MARK: - ServerTrustError

/// Why a connection was refused on trust grounds.
///
/// Each case has its own message because the alternative is a generic "connection failed", which
/// sends the user to inspect their network when the actual answer is in front of them: the
/// certificate is not the one it was.
nonisolated enum ServerTrustError: Error, LocalizedError, Equatable {

    /// The presented leaf certificate is not the pinned one.
    case certificateChanged(host: String)
    /// The chain does not validate against the trusted authority.
    case chainRejected(host: String, reason: String)
    /// The trust configuration could not be read, so no decision could be made.
    case configurationUnreadable(host: String, reason: String)
    /// Pinning is armed and the leaf's fingerprint could not be computed.
    case undetermined(host: String)

    var errorDescription: String? {
        switch self {
        case .certificateChanged(let host):
            return L("The certificate for %@ is not the one this app recorded. It was replaced, or something is intercepting the connection.", host)
        case .chainRejected(let host, let reason):
            return L("The certificate for %@ was not issued by the authority you trusted. %@", host, reason)
        case .configurationUnreadable(let host, let reason):
            return L("Prizm could not read the stored certificate settings for %@, so the connection was not made. %@", host, reason)
        case .undetermined(let host):
            return L("Prizm could not read the certificate for %@, so the connection was not made.", host)
        }
    }
}
