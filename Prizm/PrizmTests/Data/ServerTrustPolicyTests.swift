import XCTest
@testable import Prizm

// MARK: - ServerTrustPolicyTests

/// The decision table from design D8, one case per row.
///
/// **What this file does not cover, and why.** The TLS handshake is not exercised here — not by a
/// real server (a unit test cannot stand one up with a private certificate authority) and not by a
/// fake `SecTrust` (which would test the fake). `ServerTrustPolicy.decide` is a pure function over
/// four values precisely so that the rule can be tested without either. `ServerTrustDelegate` —
/// the ~50 lines that set anchors, call `SecTrustEvaluateWithError` and record a fingerprint — is
/// the untested part, and it is untested by construction rather than by omission. The same
/// limitation is recorded in `SECURITY.md`.
final class ServerTrustPolicyTests: XCTestCase {

    private static let host      = "vault.example.com"
    private static let pinned    = "1111111111111111111111111111111111111111111111111111111111111111"
    private static let presented = "2222222222222222222222222222222222222222222222222222222222222222"
    private static let ca        = Data([0x30, 0x82, 0x01])

    // MARK: - Not this server

    func testDifferentHost_usesDefaultHandling() {
        var configuration = ServerTrustConfiguration.empty
        configuration.trustedCACertificates = [Self.ca]
        configuration.pinningEnabled         = true

        let decision = ServerTrustPolicy.decide(host:               "blob.core.windows.net",
                                                configuredHost:     Self.host,
                                                configuration:      configuration,
                                                observedLeafSHA256: Self.presented)

        XCTAssertEqual(decision, .useDefaultHandling,
                       "A fully configured server must not make the app apply that trust to another host")
    }

    func testNoConfiguredHost_usesDefaultHandling() {
        let decision = ServerTrustPolicy.decide(host:               Self.host,
                                                configuredHost:     nil,
                                                configuration:      ServerTrustConfiguration.empty,
                                                observedLeafSHA256: nil)
        XCTAssertEqual(decision, .useDefaultHandling)
    }

    // MARK: - Nothing configured

    func testEmptyConfiguration_usesDefaultHandling() {
        let decision = ServerTrustPolicy.decide(host:               Self.host,
                                                configuredHost:     Self.host,
                                                configuration:      .empty,
                                                observedLeafSHA256: Self.presented)
        XCTAssertEqual(decision, .useDefaultHandling)
    }

    // MARK: - Host matching

    func testHostComparisonIgnoresCaseAndAPort() {
        var configuration = ServerTrustConfiguration.empty
        configuration.trustedCACertificates = [Self.ca]

        for candidate in ["Vault.Example.com", "vault.example.com:443", "VAULT.example.com."] {
            let decision = ServerTrustPolicy.decide(host:               candidate,
                                                    configuredHost:     "vault.example.com:443",
                                                    configuration:      configuration,
                                                    observedLeafSHA256: nil)
            guard case .evaluate = decision else {
                return XCTFail("\(candidate) should have been recognised as the configured host")
            }
        }
    }

    func testIPv6LiteralIsNotSplitAsAPort() {
        XCTAssertEqual(ServerTrustPolicy.normalize("::1"), "::1",
                       "Stripping the port must not mangle an IPv6 literal into a host")
    }

    // MARK: - Anchors

    func testTrustedAuthorityIsPassedAsTheAnchors() {
        var configuration = ServerTrustConfiguration.empty
        configuration.trustedCACertificates = [Self.ca, Data([0x02])]

        let decision = ServerTrustPolicy.decide(host:               Self.host,
                                                configuredHost:     Self.host,
                                                configuration:      configuration,
                                                observedLeafSHA256: nil)
        XCTAssertEqual(decision, .evaluate(anchors: [Self.ca, Data([0x02])], pin: .disabled))
    }

    func testPinningOffIgnoresARecordedFingerprint() {
        var configuration = ServerTrustConfiguration.empty
        configuration.pinnedLeafSHA256 = Self.pinned
        // pinningEnabled stays false: the user turned the setting off but the pin is kept.

        let decision = ServerTrustPolicy.decide(host:               Self.host,
                                                configuredHost:     Self.host,
                                                configuration:      configuration,
                                                observedLeafSHA256: Self.presented)
        XCTAssertEqual(decision, .evaluate(anchors: [], pin: .disabled),
                       "Turning the setting off must not leave a pin being enforced")
    }

    // MARK: - Pinning

    func testMatchingFingerprint_isAccepted() {
        let decision = decide(pinningEnabled: true, pinned: Self.pinned, observed: Self.pinned)
        XCTAssertEqual(decision, .evaluate(anchors: [], pin: .matches))
    }

    func testChangedFingerprint_isRefused() {
        let decision = decide(pinningEnabled: true, pinned: Self.pinned, observed: Self.presented)
        XCTAssertEqual(decision, .evaluate(anchors: [], pin: .mismatch))
    }

    func testFingerprintComparisonIgnoresCase() {
        let decision = decide(pinningEnabled: true,
                              pinned:    Self.pinned.uppercased(),
                              observed:  Self.pinned)
        XCTAssertEqual(decision, .evaluate(anchors: [], pin: .matches))
    }

    func testPinningOnWithNothingRecorded_recordsWhatIsSeen() {
        let decision = decide(pinningEnabled: true, pinned: nil, observed: Self.presented)
        XCTAssertEqual(decision, .evaluate(anchors: [], pin: .record(Self.presented)))
    }

    func testPinningOnButNoFingerprintCouldBeRead_isNotGranted() {
        let decision = decide(pinningEnabled: true, pinned: nil, observed: nil)
        XCTAssertEqual(decision, .evaluate(anchors: [], pin: .undetermined),
                       "Accepting with nothing to record would be indistinguishable from a checked pin")
    }

    func testARecordedPinWithNoFingerprintCouldBeRead_isNotGranted() {
        let decision = decide(pinningEnabled: true, pinned: Self.pinned, observed: nil)
        XCTAssertEqual(decision, .evaluate(anchors: [], pin: .undetermined))
    }

    // MARK: - Errors

    func testCertificateChangedErrorNamesTheHostAndIsNotAGenericFailure() {
        let error = ServerTrustError.certificateChanged(host: Self.host)
        let text  = error.errorDescription ?? ""
        XCTAssertTrue(text.contains(Self.host), "the message has to say which server")
        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, "connection failed")
    }

    func testEveryRefusalHasItsOwnMessage() {
        let messages = [
            ServerTrustError.certificateChanged(host: Self.host).errorDescription,
            ServerTrustError.chainRejected(host: Self.host, reason: "r").errorDescription,
            ServerTrustError.configurationUnreadable(host: Self.host, reason: "r").errorDescription,
            ServerTrustError.undetermined(host: Self.host).errorDescription,
        ].compactMap { $0 }
        XCTAssertEqual(messages.count, 4, "every refusal must have a message of its own")
        XCTAssertEqual(Set(messages).count, 4, "the messages must not collapse into one generic one")
    }

    // MARK: - Helpers

    private func decide(pinningEnabled: Bool,
                        pinned:   String?,
                        observed: String?) -> ServerTrustDecision {
        var configuration = ServerTrustConfiguration.empty
        configuration.pinningEnabled    = pinningEnabled
        configuration.pinnedLeafSHA256  = pinned
        return ServerTrustPolicy.decide(host:               Self.host,
                                        configuredHost:     Self.host,
                                        configuration:      configuration,
                                        observedLeafSHA256: observed)
    }
}
