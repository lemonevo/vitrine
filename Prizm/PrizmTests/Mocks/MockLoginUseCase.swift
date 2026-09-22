import Foundation
@testable import Prizm

/// Test double for `LoginUseCase`.
@MainActor
final class MockLoginUseCase: LoginUseCase {

    // MARK: - Call tracking

    private(set) var executeCallCount:       Int    = 0
    private(set) var cancelTwoFactorCalled:  Bool   = false
    private(set) var completeTwoFactorCalled: Bool  = false
    private(set) var sendEmailCodeCallCount: Int    = 0

    /// The code the view model submitted. Recorded because the point of several cases is that the
    /// code reaches the use case unaltered — a YubiKey code filtered down to digits would still be
    /// non-empty, so "was called" is not enough to catch it.
    private(set) var submittedCode:          String?

    // MARK: - Stubs

    /// The sync outcome carried by `LoginOutcome.signedIn`. Left nil by default so a test that does
    /// not care about the vault payload does not have to build one.
    var stubbedSyncResult: SyncResult?

    var stubbedResult: LoginOutcome = .signedIn(
        account: Account(
            userId:            "stub-user",
            email:             "stub@example.com",
            name:              nil,
            serverEnvironment: ServerEnvironment(
                base:      URL(string: "https://stub.example.com")!,
                overrides: nil
            )
        ),
        sync: nil
    )
    var executeError: Error?
    var completeTwoFactorError: Error?
    var sendEmailCodeError: Error?

    // MARK: - LoginUseCase

    func execute(serverURL: String, email: String, masterPassword: Data) async throws -> LoginOutcome {
        executeCallCount += 1
        if let err = executeError { throw err }
        return stubbedResult
    }

    func completeTwoFactor(
        code: String,
        rememberDevice: Bool
    ) async throws -> (account: Account, sync: SyncResult?) {
        completeTwoFactorCalled = true
        submittedCode = code
        if let err = completeTwoFactorError { throw err }
        guard case .signedIn(let account, let sync) = stubbedResult else {
            throw AuthError.invalidTwoFactorCode
        }
        return (account, sync ?? stubbedSyncResult)
    }

    func sendEmailTwoFactorCode() async throws {
        sendEmailCodeCallCount += 1
        if let err = sendEmailCodeError { throw err }
    }

    func cancelTwoFactor() {
        cancelTwoFactorCalled = true
    }
}
