import Foundation

// MARK: - SSHBigUInt

/// Just enough unsigned big-integer arithmetic to build an RSA private key.
///
/// Swift has no arbitrary-precision integer, and `SecKey` will not accept an RSA private key
/// without `dP` and `dQ` — the exponents used by the Chinese-remainder shortcut — which OpenSSH's
/// key format does not store. They are `d mod (p-1)` and `d mod (q-1)`, so the one operation
/// needed is modulo, and that is the only one implemented.
///
/// Deliberately not a general-purpose bignum: there is no multiplication, no negative numbers and
/// no division, and a future reader should not assume this type does more than it does.
nonisolated enum SSHBigUInt {

    /// Big-endian magnitude, no leading zero bytes. Zero is the empty array.
    typealias Value = [UInt8]

    // MARK: Conversion

    static func magnitude(of data: Data) -> Value {
        var bytes = Value(data)
        while !bytes.isEmpty, bytes.first == 0 { bytes.removeFirst() }
        return bytes
    }

    static func data(_ value: Value) -> Data { Data(value) }

    static var zero: Value { [] }

    // MARK: Comparison

    /// - Returns: -1, 0 or 1.
    static func compare(_ a: Value, _ b: Value) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for i in 0..<a.count where a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        return 0
    }

    // MARK: Arithmetic

    /// `a - 1`. Only ever called on a prime, so it is never called on zero.
    static func decrement(_ a: Value) -> Value {
        precondition(!a.isEmpty, "decrementing zero is not defined here")
        var out = a
        var i   = out.count - 1
        while true {
            if out[i] > 0 { out[i] -= 1; break }
            out[i] = 0xFF
            if i == 0 { break }
            i -= 1
        }
        return magnitude(of: Data(out))
    }

    /// `a - b`, for `a >= b`.
    static func subtract(_ a: Value, _ b: Value) -> Value {
        precondition(compare(a, b) >= 0, "subtract would go negative")
        var out    = a
        var borrow = 0
        for i in stride(from: out.count - 1, through: 0, by: -1) {
            let rhs  = i - (out.count - b.count)
            let sub  = Int(out[i]) - borrow - (rhs >= 0 ? Int(b[rhs]) : 0)
            if sub < 0 {
                out[i] = UInt8(sub + 256)
                borrow = 1
            } else {
                out[i] = UInt8(sub)
                borrow = 0
            }
        }
        return magnitude(of: Data(out))
    }

    /// `a mod m`, by binary long division: shift the remainder left one bit at a time and subtract
    /// whenever it has grown past `m`.
    ///
    /// Quadratic in the width of `a`, which for a 2048-bit key is a few thousand byte operations —
    /// far below the cost of the signature it feeds, and the only place this runs.
    static func modulo(_ a: Value, _ m: Value) -> Value {
        precondition(!m.isEmpty, "modulo by zero")
        if compare(a, m) < 0 { return a }
        var remainder: Value = []
        for byte in a {
            for bit in stride(from: 7, through: 0, by: -1) {
                remainder = shiftLeftOne(remainder, adding: (byte >> bit) & 1)
                if compare(remainder, m) >= 0 { remainder = subtract(remainder, m) }
            }
        }
        return magnitude(of: Data(remainder))
    }

    /// `value << 1 | bit`.
    ///
    /// Walks from the least-significant end, which is the direction the carry travels.
    private static func shiftLeftOne(_ value: Value, adding bit: UInt8) -> Value {
        var out   = value
        var carry = bit
        for i in stride(from: out.count - 1, through: 0, by: -1) {
            let high = out[i] & 0x80 != 0 ? 1 : 0
            out[i]   = (out[i] << 1) | UInt8(carry)
            carry    = UInt8(high)
        }
        if carry != 0 { out.insert(carry, at: 0) }
        return out
    }
}
