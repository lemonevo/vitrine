import Foundation

// MARK: - Constant-time comparison

/// Compares two byte buffers in time that does not depend on how many leading bytes match.
///
/// `Data`'s `==` returns at the first differing byte, so how long it takes reports *where* the
/// first difference is. That is a property worth removing for the material this is used on: the
/// outcome of a master-password check is exactly the value an attacker would like to learn one
/// byte at a time.
///
/// Deliberately not a constant-time library. It folds an XOR over every position and ORs the
/// length difference into the same accumulator, which is sufficient for the single comparison
/// in the tree that needs it and does not pretend to solve the general problem.
///
/// - Note: The loop cannot be shortened by the optimiser: every iteration feeds the accumulator
///   through `|=`, so removing any iteration would change the result.
nonisolated func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    var accumulator = lhs.count ^ rhs.count
    for index in 0..<min(lhs.count, rhs.count) {
        accumulator |= Int(lhs[index] ^ rhs[index])
    }
    return accumulator == 0
}
