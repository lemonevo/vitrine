import CryptoKit
import Foundation
import os
import os.log
import Security

// MARK: - ServerTrustDelegate

/// Carries out `ServerTrustPolicy`'s decision during a TLS handshake.
///
/// This is deliberately an adapter: the rule lives in the policy as a pure function, and every
/// branch of it is unit-tested. What is left here is the part that cannot be — talking to
/// `SecTrust` and `URLSession`. What is *not* covered by any test is stated there rather than
/// here, because this file is where someone would come looking for a handshake test and not find
/// one.
///
/// `URLSession` keeps a strong reference to its delegate, so the session owns this object; nothing
/// else needs to hold it to keep it alive, but the API client holds one too so it can translate a
/// refusal into the error the user sees.
nonisolated final class ServerTrustDelegate: NSObject, URLSessionDelegate, Sendable {

    private let store:      any ServerTrustStore
    private let hostSource: HostSource = HostSource()
    private let refusals:   RefusalBox = RefusalBox()
    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "ServerTrust")

    init(store: any ServerTrustStore) {
        self.store = store
    }

    /// Supplies the host the user configured.
    ///
    /// Set after construction rather than passed to `init`, because the session that owns this
    /// delegate has to exist before the client whose base URL names that host can be created. It is
    /// read per challenge anyway: signing out and into a different server changes it without
    /// recreating the session.
    func setConfiguredHost(_ provider: @escaping @Sendable () async -> String?) {
        hostSource.set(provider)
    }

    // MARK: - URLSessionDelegate

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition,
                                                            URLCredential?) -> Void) {

        // Anything other than a server-trust challenge — client certificates, HTTP authentication
        // — is none of this object's business.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host     = challenge.protectionSpace.host
        let observed = Self.leafFingerprint(trust)

        // `SecTrust` is not `Sendable`, and the decision has to be awaited because the store is.
        // The reference is used on one queue for the lifetime of this challenge and is not shared,
        // so the box records that rather than pretending the type crosses threads by itself.
        let box       = TrustBox(trust)
        let store     = self.store
        let hostSource = self.hostSource
        let refusal   = self.refusals

        Task {
            await Self.resolve(host:            host,
                               trust:           box,
                               observedLeaf:    observed,
                               store:           store,
                               hostSource:      hostSource,
                               refusals:        refusal,
                               completionHandler: completionHandler)
        }
    }

    // MARK: - Decision

    private static func resolve(
        host:              String,
        trust:             TrustBox,
        observedLeaf:      String?,
        store:             any ServerTrustStore,
        hostSource:        HostSource,
        refusals:          RefusalBox,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition,
                                                URLCredential?) -> Void
    ) async {
        let configuration: ServerTrustConfiguration
        do {
            configuration = try await store.configuration(forHost: host)
        } catch {
            // Fail closed. Treating an unreadable configuration as "nothing configured" would
            // downgrade the user's own settings to default handling — the one direction of this
            // decision that hands a protected connection to whatever answers.
            refusals.record(error)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let decision = ServerTrustPolicy.decide(host:               host,
                                                configuredHost:     await hostSource.current(),
                                                configuration:      configuration,
                                                observedLeafSHA256: observedLeaf)

        switch decision {
        case .useDefaultHandling:
            completionHandler(.performDefaultHandling, nil)

        case .evaluate(let anchors, let pin):
            await evaluate(trust:      trust.trust,
                           host:       host,
                           anchors:    anchors,
                           pin:        pin,
                           store:      store,
                           refusals:   refusals,
                           completion: completionHandler)
        }
    }

    private static func evaluate(
        trust:      SecTrust,
        host:       String,
        anchors:    [Data],
        pin:        ServerTrustPinCheck,
        store:      any ServerTrustStore,
        refusals:   RefusalBox,
        completion: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) async {
        if !anchors.isEmpty {
            let certificates = anchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            guard certificates.count == anchors.count else {
                // A stored value that is not a certificate: say so rather than evaluating with
                // fewer anchors than the user trusted, which would silently widen what is accepted.
                refusals.record(ServerTrustError.configurationUnreadable(
                    host: host, reason: L("A stored certificate could not be read.")))
                completion(.cancelAuthenticationChallenge, nil)
                return
            }
            // "Only" is the whole point: without it the system's own authorities are added back
            // and the private one becomes an extra rather than a restriction.
            SecTrustSetAnchorCertificates(trust, certificates as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
        }

        var evaluationError: CFError?
        guard SecTrustEvaluateWithError(trust, &evaluationError) else {
            let reason = (evaluationError?.localizedDescription).map { String(describing: $0) } ?? ""
            refusals.record(ServerTrustError.chainRejected(host: host, reason: reason))
            completion(.cancelAuthenticationChallenge, nil)
            return
        }

        switch pin {
        case .disabled, .matches:
            completion(.useCredential, URLCredential(trust: trust))

        case .record(let fingerprint):
            var updated = (try? await store.configuration(forHost: host)) ?? .empty
            updated.pinnedLeafSHA256 = fingerprint
            do {
                try await store.save(updated, forHost: host)
            } catch {
                // Fail closed on the save too. A pin that could not be recorded and an accepted
                // connection would leave the user believing they are pinned when they are not —
                // which is worse than a refused connection, because it is invisible.
                refusals.record(ServerTrustError.configurationUnreadable(
                    host: host, reason: error.localizedDescription))
                completion(.cancelAuthenticationChallenge, nil)
                return
            }
            completion(.useCredential, URLCredential(trust: trust))

        case .mismatch:
            refusals.record(ServerTrustError.certificateChanged(host: host))
            completion(.cancelAuthenticationChallenge, nil)

        case .undetermined:
            refusals.record(ServerTrustError.undetermined(host: host))
            completion(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Fingerprints

    /// SHA-256 of the leaf certificate, hex-encoded. Nil when the chain has no leaf.
    static func leafFingerprint(_ trust: SecTrust) -> String? {
        guard let leaf = SecTrustGetCertificateAtIndex(trust, 0) else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Refusals

    /// The refusal to report as the cause of the next failed request, if any.
    ///
    /// Consumed on read. A refusal left behind would be attached to a later, unrelated request —
    /// a pin failure during login would otherwise be reported again the next time anything fails.
    func takeRefusal() -> ServerTrustError? {
        refusals.take()
    }
}

// MARK: - Boxes

/// Carries a `SecTrust` across the await in `resolve`. See the comment at its use site.
private nonisolated struct TrustBox: @unchecked Sendable {
    let trust: SecTrust
    init(_ trust: SecTrust) { self.trust = trust }
}

/// Holds the closure that names the configured host. See `setConfiguredHost`.
private nonisolated final class HostSource: Sendable {
    private let lock = OSAllocatedUnfairLock<(@Sendable () async -> String?)?>(initialState: nil)

    func set(_ provider: @escaping @Sendable () async -> String?) {
        lock.withLock { $0 = provider }
    }

    func current() async -> String? {
        let provider = lock.withLock { $0 }
        return await provider?()
    }
}

/// The refusal the delegate recorded, guarded because the delegate is called off the main actor.
private nonisolated final class RefusalBox: Sendable {
    private let lock = OSAllocatedUnfairLock<ServerTrustError?>(initialState: nil)

    func record(_ error: Error) {
        lock.withLock { $0 = error as? ServerTrustError }
    }

    func take() -> ServerTrustError? {
        lock.withLock { state in
            let value = state
            state = nil
            return value
        }
    }
}
