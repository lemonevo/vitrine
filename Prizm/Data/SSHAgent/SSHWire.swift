import Foundation

// MARK: - SSHAgentMessage

/// Message numbers in the SSH agent protocol.
///
/// Only the four Prizm answers are named. The rest — `ADD_IDENTITY`, `REMOVE_IDENTITY`,
/// `REMOVE_ALL_IDENTITIES`, `LOCK`, `UNLOCK` — are answered with `failure`, which is why they are
/// not listed here: giving them names would suggest they are handled.
nonisolated enum SSHAgentMessage: UInt8 {
    case failure           = 5
    case success           = 6
    case requestIdentities = 11
    case identitiesAnswer  = 12
    case signRequest       = 13
    case signResponse      = 14
}

// MARK: - SSHAgentSignFlags

/// Flags on `SSH_AGENTC_SIGN_REQUEST`.
///
/// `rsaSha2_256` and `rsaSha2_512` say which digest the client wants an RSA signature over. When
/// neither is set the client is asking for SHA-1, which OpenSSH still sends for a key it has never
/// seen used — so it has to be recognised as a request, not as "no flags".
nonisolated struct SSHAgentSignFlags: OptionSet {
    let rawValue: UInt32

    /// `SSH_AGENT_OLD_SIGNATURE` — asking for the deprecated ssh-dss-style blob. Ignored: Prizm
    /// does not hold DSA keys, so the flag cannot apply to anything Prizm signs.
    static let oldSignature = SSHAgentSignFlags(rawValue: 1)
    static let rsaSha2_256  = SSHAgentSignFlags(rawValue: 2)
    static let rsaSha2_512  = SSHAgentSignFlags(rawValue: 4)
}

// MARK: - SSHWireReader

/// Reads the SSH wire primitives defined in RFC 4251 §5.
///
/// Throws rather than clamping: a truncated read means the peer sent something that is not this
/// protocol, and continuing with what is available would produce an answer that is wrong in a way
/// only the client can see.
nonisolated struct SSHWireReader {

    private let bytes: [UInt8]
    private var offset: Int

    init(_ data: Data) {
        bytes  = [UInt8](data)
        offset = 0
    }

    var bytesRemaining: Int { bytes.count - offset }

    mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else { throw SSHWireError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw SSHWireError.truncated }
        var value: UInt32 = 0
        for _ in 0..<4 {
            value = (value << 8) | UInt32(bytes[offset])
            offset += 1
        }
        return value
    }

    mutating func readString() throws -> Data {
        let length = Int(try readUInt32())
        guard length <= bytesRemaining else { throw SSHWireError.truncated }
        defer { offset += length }
        return Data(bytes[offset..<(offset + length)])
    }

    /// An `mpint` — a big-endian two's-complement integer, with a leading zero byte when the high
    /// bit is set so the value stays positive.
    mutating func readMPInt() throws -> Data {
        let raw = try readString()
        // A leading zero is legal and carries no information about the value.
        var start = 0
        while start + 1 < raw.count && raw[start] == 0 { start += 1 }
        return raw.dropFirst(start)
    }
}

// MARK: - SSHWireWriter

/// Writes the same primitives, and frames complete agent messages.
nonisolated struct SSHWireWriter {

    private(set) var bytes: [UInt8] = []

    mutating func writeByte(_ value: UInt8) { bytes.append(value) }

    mutating func writeUInt32(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    mutating func writeString(_ value: Data) {
        writeUInt32(UInt32(value.count))
        bytes.append(contentsOf: value)
    }

    mutating func writeString(_ value: String) { writeString(Data(value.utf8)) }

    /// Writes an `mpint`: the minimal big-endian magnitude, plus a zero byte when the high bit
    /// would otherwise make it read as negative.
    mutating func writeMPInt(_ magnitude: Data) {
        var value = magnitude
        while value.first == 0, value.count > 1 { value.removeFirst() }
        if (value.first ?? 0) & 0x80 != 0 { value.insert(0, at: value.startIndex) }
        writeString(value)
    }

    // MARK: Framing

    /// A complete message: length (excluding itself), then the type byte, then the body.
    static func message(type: SSHAgentMessage, body: [UInt8] = []) -> Data {
        var writer = SSHWireWriter()
        writer.writeUInt32(UInt32(body.count + 1))
        writer.writeByte(type.rawValue)
        writer.bytes.append(contentsOf: body)
        return Data(writer.bytes)
    }

    /// The answer to `REQUEST_IDENTITIES`: a count, then each key's blob and comment.
    ///
    /// A *public* blob per entry, and nothing else. The comment is chosen by the caller — see the
    /// scenario in the spec about it being the item's name.
    static func identitiesAnswer(_ identities: [(blob: Data, comment: String)]) -> Data {
        var writer = SSHWireWriter()
        writer.writeUInt32(UInt32(identities.count))
        for identity in identities {
            writer.writeString(identity.blob)
            writer.writeString(identity.comment)
        }
        return message(type: .identitiesAnswer, body: writer.bytes)
    }

    /// The answer to `SIGN_REQUEST`: one string holding `string algorithm` + `string signature`.
    ///
    /// The nesting is easy to get wrong and produces a signature `ssh` rejects with a message about
    /// the key rather than the encoding, so it is built here rather than at the call site.
    static func signResponse(algorithm: String, signature: Data) -> Data {
        var payload = SSHWireWriter()
        payload.writeString(algorithm)
        payload.writeString(signature)

        // The payload is one string, not two siblings in the message body. A client reads the
        // response as `string blob` and only then splits the blob, so writing them as siblings
        // hands it an algorithm name where it expects a length — and `ssh` reports the key as
        // invalid rather than the encoding, which is the least findable way this can fail.
        var writer = SSHWireWriter()
        writer.writeString(Data(payload.bytes))
        return message(type: .signResponse, body: writer.bytes)
    }

    static func failure() -> Data { message(type: .failure) }
}

// MARK: - SSHWireError

nonisolated enum SSHWireError: Error, LocalizedError {
    /// The peer sent fewer bytes than the message claimed.
    case truncated
    /// The message named a type Prizm does not answer.
    case unsupportedMessage(UInt8)

    var errorDescription: String? {
        switch self {
        case .truncated:
            return L("The SSH client sent an incomplete request.")
        case .unsupportedMessage(let type):
            return L("The SSH client sent a request Prizm does not answer (%lld).", Int64(type))
        }
    }
}
