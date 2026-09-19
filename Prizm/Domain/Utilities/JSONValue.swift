import Foundation

// MARK: - JSONValue

/// A JSON value of unknown shape, preserved exactly across a decode/encode round trip.
///
/// **Why this exists.** The Bitwarden cipher wire format carries subtrees Prizm does not model —
/// passkeys under `login.fido2Credentials`, the server-maintained `passwordHistory`. Because
/// `PUT /api/ciphers/{id}` replaces the whole cipher, a field that is absent from the request body
/// is deleted server-side (Vaultwarden `update_cipher_from_data` assigns `password_history`
/// unconditionally and stores the `login` object verbatim). Carrying those subtrees as `JSONValue`
/// keeps them byte-identical without inventing Swift types for a feature that has no UI yet.
///
/// **Why not `Any`.** `Any` is neither `Sendable`, nor `Equatable`, nor `Codable`; using it would
/// make `VaultItem` unusable in all three of the ways it is used.
///
/// **Precision.** Numbers are held as `Double`. Every value in the subtrees this type is used for
/// is a JSON string or boolean (FIDO2 `counter` is a string on the wire), so no precision is at
/// risk today. A future caller that needs exact large integers should add a case rather than
/// round-trip through `Double`.
///
/// Object key order is not preserved — JSON object member order carries no meaning.
nonisolated enum JSONValue: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        // `Bool` must be tried before `Double`: JSONDecoder refuses to widen a boolean to a
        // number, so the reverse order would still work, but trying `Double` first would turn a
        // boolean into a number on the way back out.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Value is not valid JSON"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:          try container.encodeNil()
        case .bool(let v):   try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v):  try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
