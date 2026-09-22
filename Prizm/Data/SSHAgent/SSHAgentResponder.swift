import Foundation
import os.log

// MARK: - SSHAgentResponder

/// Answers one agent request.
///
/// **Nothing here touches a socket, a key, or the vault** — every one of those arrives as an
/// argument, and the answer comes back as bytes. That is what makes the protocol testable: a test
/// can hand it a `SIGN_REQUEST` for a key it does not hold and assert the answer is `FAILURE`,
/// which is exactly the case that cannot be exercised once a real socket is involved.
///
/// `authorize` is an argument rather than something the caller does before calling, because a gate
/// applied outside this function is a gate that a future caller can forget to apply. Here, not
/// calling it is not an option: there is no path from a sign request to a signature that skips it.
nonisolated enum SSHAgentResponder {

    /// Produces a signature for one identity.
    typealias Signing = @Sendable (SSHAgentIdentity, Data, SSHAgentSignFlags) async throws
        -> (algorithm: String, signature: Data)

    /// - Parameters:
    ///   - request: One complete message, length prefix included, as it arrived on the socket.
    ///   - identities: The keys the agent is serving.
    ///   - authorize: Whether one signature may be made. Called **before** `sign`, and its `false`
    ///     is final.
    ///   - sign: Produces the signature. Called only after authorization.
    static func response(
        to request:    Data,
        identities:    [SSHAgentIdentity],
        authorize:     @Sendable (SSHAgentIdentity) async -> Bool,
        sign:          @escaping Signing
    ) async -> Data {
        do {
            var reader = SSHWireReader(request)
            _ = try reader.readUInt32()          // length; the bytes are already framed
            let rawType = try reader.readByte()

            guard let type = SSHAgentMessage(rawValue: rawType) else {
                return Self.failure(.unsupportedRequest(rawType))
            }

            switch type {
            case .requestIdentities:
                // Listing needs no authorization: these are public keys. Gating it would mean a
                // user cannot see which keys are loaded without entering a master password, and
                // would protect nothing — the blobs are published by definition.
                return SSHWireWriter.identitiesAnswer(
                    identities.map { (blob: $0.blob, comment: $0.comment) }
                )

            case .signRequest:
                return await Self.signResponse(reading: &reader,
                                               identities: identities,
                                               authorize: authorize,
                                               sign: sign)

            default:
                return Self.failure(.unsupportedRequest(rawType))
            }
        } catch {
            // A malformed request is answered, never thrown. Throwing would tear down the
            // connection and take every other pending request with it, for one bad message.
            return Self.failure(.malformedRequest)
        }
    }

    // MARK: - Sign request

    private static func signResponse(
        reading:    inout SSHWireReader,
        identities: [SSHAgentIdentity],
        authorize:  @Sendable (SSHAgentIdentity) async -> Bool,
        sign:       Signing
    ) async -> Data {
        do {
            let blob     = try reading.readString()
            let data     = try reading.readString()
            let rawFlags = try reading.readUInt32()
            let flags    = SSHAgentSignFlags(rawValue: rawFlags)

            guard let identity = identities.first(where: { $0.blob == blob }) else {
                // Not served by this agent. `ssh` asks every agent in turn, so this is the common
                // case rather than an error, and it must not be reported as one.
                return Self.failure(.unknownKey)
            }

            guard await authorize(identity) else { return Self.failure(.notAuthorized) }

            let result = try await sign(identity, data, flags)
            return SSHWireWriter.signResponse(algorithm: result.algorithm, signature: result.signature)
        } catch {
            return Self.failure(.signingFailed)
        }
    }

    // MARK: - Failures

    /// The reasons a request is refused, recorded rather than collapsed into one `FAILURE` byte.
    ///
    /// They are not sent to the client — the protocol's failure message carries no payload — so
    /// they exist for the log. A log that says only "failed" is why an agent is hard to debug from
    /// the outside: the client reports "agent refused" and nothing else, for every one of these.
    nonisolated enum Refusal: Error {
        case unsupportedRequest(UInt8)
        case malformedRequest
        case unknownKey
        case notAuthorized
        case signingFailed
    }

    /// The answer, and the only trace: the protocol's failure message has no payload, so this log
    /// is the whole of what anyone can later learn about why a client was refused.
    private static func failure(_ reason: Refusal) -> Data {
        logger.error("SSH agent refused a request: \(reason.logSummary, privacy: .public)")
        return SSHWireWriter.failure()
    }

    private static let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "SSHAgent")
}

extension SSHAgentResponder.Refusal {
    fileprivate var logSummary: String {
        switch self {
        case .unsupportedRequest(let type): return "unsupported message type \(type)"
        case .malformedRequest:             return "the request could not be read"
        case .unknownKey:                   return "the key is not served by this agent"
        case .notAuthorized:                return "the signature was not authorized"
        case .signingFailed:                return "signing failed"
        }
    }
}
