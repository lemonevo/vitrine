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

    /// Every password submitted, in order.
    private(set) var submitted: [Data] = []
    private(set) var callCount: Int = 0

    func execute(_ password: Data) async throws -> Bool {
        callCount += 1
        submitted.append(password)
        if let error = stubbedError { throw error }
        return stubbedResult
    }
}
