import LocalAuthentication
@testable import Prizm

/// Stand-in for `SystemBiometricPolicyEvaluator` that always succeeds.
///
/// A test runner has no enrolled biometrics and must never raise a Touch ID prompt, so
/// the Keychain code paths are exercised through `.appEnforced` + this evaluator. The
/// gate itself is covered by the manual checklist in the README, not here.
final class NoopBiometricPolicyEvaluator: BiometricPolicyEvaluating {
    private(set) var evaluateCallCount = 0
    private(set) var lastReason: String?

    /// When non-nil, `evaluate` throws it instead of succeeding.
    var error: Error?

    func evaluate(reason: String) async throws -> LAContext {
        evaluateCallCount += 1
        lastReason = reason
        if let error { throw error }
        return LAContext()
    }
}
