import XCTest
@testable import Prizm

/// Failing tests for LoginUseCaseImpl (T026).
/// These will fail until LoginUseCaseImpl + AuthRepositoryImpl + SyncRepositoryImpl are implemented.
@MainActor
final class LoginUseCaseTests: XCTestCase {

    private var sut: LoginUseCaseImpl!
    private var mockAuth: MockAuthRepository!
    private var mockSync: MockSyncRepository!

    private let serverURL      = "https://vault.example.com"
    private let email          = "alice@example.com"
    private let masterPassword = Data("masterPassword1!".utf8)

    override func setUp() async throws {
        try await super.setUp()
        mockAuth = MockAuthRepository()
        mockSync = MockSyncRepository()
        sut = LoginUseCaseImpl(auth: mockAuth, sync: mockSync)
    }

    // MARK: - T026: execute(serverURL:email:masterPassword:)

    /// Full success path: validates URL, sets environment, calls loginWithPassword, syncs, returns .success.
    func testExecute_validCredentials_returnsSuccessAndSyncs() async throws {
        mockAuth.stubbedLoginResult  = .success(makeAccount())
        mockSync.stubbedSyncResult   = makeSyncResult()

        let result = try await sut.execute(
            serverURL:      serverURL,
            email:          email,
            masterPassword: masterPassword
        )

        guard case .signedIn(let account, let sync) = result else {
            return XCTFail("Expected .signedIn, got \(result)")
        }
        XCTAssertEqual(account.email, email)
        XCTAssertEqual(sync?.source, .server, "The sync that ran after login should be reported as server-sourced")
        XCTAssertTrue(mockAuth.setServerEnvironmentCalled, "Expected setServerEnvironment to be called")
        XCTAssertTrue(mockAuth.loginWithPasswordCalled,    "Expected loginWithPassword to be called")
        XCTAssertTrue(mockSync.syncCalled,                 "Expected sync to be called after login")
    }

    /// An invalid server URL is rejected before any network call is made.
    func testExecute_invalidURL_throwsBeforeNetwork() async throws {
        mockAuth.validateServerURLError = AuthError.invalidURL

        let sut = self.sut!
        await XCTAssertThrowsErrorAsync(
            try await sut.execute(
                serverURL:      "not-a-url",
                email:          email,
                masterPassword: masterPassword
            )
        ) { error in
            XCTAssertEqual(error as? AuthError, .invalidURL)
        }

        XCTAssertFalse(mockAuth.loginWithPasswordCalled, "Login must not be called on invalid URL")
        XCTAssertFalse(mockSync.syncCalled,              "Sync must not be called on invalid URL")
    }

    /// When loginWithPassword returns .requiresTwoFactor, the use case returns the same result
    /// without triggering a sync.
    func testExecute_requires2FA_returnsTwoFactorWithoutSync() async throws {
        mockAuth.stubbedLoginResult = .requiresTwoFactor(.challenge(.authenticatorApp))

        let result = try await sut.execute(
            serverURL:      serverURL,
            email:          email,
            masterPassword: masterPassword
        )

        guard case .requiresTwoFactor(let method) = result else {
            return XCTFail("Expected .requiresTwoFactor, got \(result)")
        }
        XCTAssertEqual(method.provider, .authenticatorApp)
        XCTAssertFalse(mockSync.syncCalled, "Sync must not be called when 2FA is required")
    }

    /// Invalid credentials propagate as AuthError.invalidCredentials.
    func testExecute_invalidCredentials_throws() async throws {
        mockAuth.loginWithPasswordError = AuthError.invalidCredentials

        let sut = self.sut!
        await XCTAssertThrowsErrorAsync(
            try await sut.execute(
                serverURL:      serverURL,
                email:          email,
                masterPassword: masterPassword
            )
        ) { error in
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }

        XCTAssertFalse(mockSync.syncCalled, "Sync must not be called on failed login")
    }

    /// A sync failure after successful login is non-fatal — the credentials were right, and failing
    /// here would send the user back to a login screen that cannot succeed either. The outcome
    /// carries no sync result, which is how the caller knows not to report a sync that never
    /// happened (FR-049).
    func testExecute_syncFailure_returnsSignedInWithoutSyncResult() async throws {
        mockAuth.stubbedLoginResult = .success(makeAccount())
        mockSync.syncShouldThrow    = SyncError.networkUnavailable

        let result = try await sut.execute(
            serverURL:      serverURL,
            email:          email,
            masterPassword: masterPassword
        )
        guard case .signedIn(_, let sync) = result else {
            XCTFail("Expected .signedIn despite sync failure")
            return
        }
        XCTAssertNil(sync, "A failed sync must not be reported as a successful one")
        XCTAssertTrue(mockSync.syncCalled, "Sync should still be attempted")
    }

    // MARK: - cancelTwoFactor

    /// cancelTwoFactor delegates to auth.cancelTwoFactor() — clears pending in-memory key material.
    func testCancelTwoFactor_callsCancelTwoFactor() async throws {
        mockAuth.stubbedLoginResult = .requiresTwoFactor(.challenge(.authenticatorApp))
        _ = try await sut.execute(
            serverURL:      serverURL,
            email:          email,
            masterPassword: masterPassword
        )

        sut.cancelTwoFactor()

        XCTAssertTrue(mockAuth.cancelTwoFactorCalled,
                      "cancelTwoFactor must forward to auth.cancelTwoFactor to clear pending key material")
    }

    // MARK: - Helpers

    private func makeAccount() -> Account {
        Account(
            userId:            "user-guid-001",
            email:             email,
            name:              "Alice",
            serverEnvironment: ServerEnvironment(
                base:      URL(string: "https://vault.example.com")!,
                overrides: nil
            )
        )
    }

    private func makeSyncResult() -> SyncResult {
        SyncResult(syncedAt: Date(), totalCiphers: 0, failedDecryptionCount: 0)
    }
}
