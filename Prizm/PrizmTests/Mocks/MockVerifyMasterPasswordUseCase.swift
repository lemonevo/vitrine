import Foundation
@testable import Prizm

/// Test double for `VerifyMasterPasswordUseCase`.
///
/// Records every submission and returns a configured answer, so a suite can drive the re-prompt
/// gate without deriving anything. The real derivation is covered in
/// `AuthRepositoryVerifyMasterPasswordTests`; using it here would make every gate test depend on
/// KDF parameters it has no interest in.
final class MockVerifyMasterPasswordUseCase: VerifyMasterPasswordUseCase {

    /// The answer to return. `true` by default, because the interesting transitions are the ones
    /// that happen once the gate opens.
    var stubbedResult: Bool = true

    /// When non-nil, `execute` throws this instead of answering — the "could not check" path.
    var stubbedError: Error?

    /// When greater than zero, `execute` waits this long before answering.
    ///
    /// Exists so a suite can land a lock in the middle of a password check. That interleaving is
    /// the only way a grant can be issued after the thing that granted it has been torn down, and
    /// without a way to hold the check open it cannot be tested at all.
    var stubbedDelay: TimeInterval = 0

    /// Every password submitted, in order.
    private(set) var submitted: [Data] = []
    private(set) var callCount: Int = 0

    func execute(_ password: Data) async throws -> Bool {
        callCount += 1
        submitted.append(password)
        if stubbedDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(stubbedDelay * 1_000_000_000))
        }
        if let error = stubbedError { throw error }
        return stubbedResult
    }
}
