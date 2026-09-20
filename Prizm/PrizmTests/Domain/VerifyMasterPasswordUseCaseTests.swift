import XCTest
@testable import Prizm

/// Covers `VerifyMasterPasswordUseCaseImpl`.
///
/// The repository double decides the answer, so nothing here says anything about the
/// cryptography — that is `AuthRepositoryVerifyMasterPasswordTests` and the crypto suite's job.
/// What this pins down is the contract the gate is built on:
///
/// - every submission is forwarded, so the use case holds no memory of a previous "yes";
/// - an error propagates instead of being flattened into `false`.
@MainActor
final class VerifyMasterPasswordUseCaseTests: XCTestCase {

    private var auth: MockAuthRepository!
    private var sut: VerifyMasterPasswordUseCaseImpl!

    override func setUp() async throws {
        try await super.setUp()
        auth = MockAuthRepository()
        sut  = VerifyMasterPasswordUseCaseImpl(auth: auth)
    }

    func testCorrectPassword_returnsTrue() async throws {
        auth.stubbedVerifyMasterPasswordResult = true

        let matches = try await sut.execute(Data("masterPassword1!".utf8))

        XCTAssertTrue(matches)
    }

    func testWrongPassword_returnsFalse() async throws {
        auth.stubbedVerifyMasterPasswordResult = false

        let matches = try await sut.execute(Data("wrong".utf8))

        XCTAssertFalse(matches)
    }

    /// The use case must not remember a previous "yes". A cached grant is one that outlives the
    /// moment it was given, which is exactly what the gate keeps per item and per unlock session
    /// instead — so the caching belongs there and nowhere else.
    func testEachSubmissionIsForwarded() async throws {
        _ = try await sut.execute(Data("first".utf8))
        _ = try await sut.execute(Data("second".utf8))

        XCTAssertEqual(auth.verifyMasterPasswordCallCount, 2)
        XCTAssertEqual(auth.verifyMasterPasswordPasswords,
                       [Data("first".utf8), Data("second".utf8)])
    }

    /// "Could not check" must not be flattened into "wrong password" on the way through: the two
    /// need different handling at the call site, and a Bool cannot carry both.
    func testCouldNotCheck_propagatesTheError() async throws {
        auth.verifyMasterPasswordError = AuthError.noStoredSession

        await XCTAssertThrowsErrorAsync(
            try await sut.execute(Data("masterPassword1!".utf8))
        ) { error in
            XCTAssertEqual(error as? AuthError, .noStoredSession)
        }
    }
}
