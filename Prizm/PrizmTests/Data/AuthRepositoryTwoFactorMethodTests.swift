import XCTest
@testable import Prizm

// MARK: - AuthRepositoryTwoFactorMethodTests

/// Which method is chosen, and which number goes on the wire when the code is submitted.
///
/// These run against the real repository with a mocked transport, because the number is decided
/// inside the repository — a test of the mock would only confirm that the mock returns whatever it
/// was given.
@MainActor
final class AuthRepositoryTwoFactorMethodTests: XCTestCase {

    private var sut: AuthRepositoryImpl!
    private var mockAPI: MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var mockKeychain: MockKeychainService!
    private var mockBiometricKeychain: MockBiometricKeychainService!
    private var mockVaultCache: MockVaultCacheStore!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI      = MockPrizmAPIClient()
        mockCrypto   = MockPrizmCryptoService()
        mockKeychain = MockKeychainService()
        mockBiometricKeychain = MockBiometricKeychainService()
        mockVaultCache = MockVaultCacheStore()
        sut = AuthRepositoryImpl(
            apiClient:  mockAPI,
            crypto:     mockCrypto,
            keychain:   mockKeychain,
            biometricKeychain: mockBiometricKeychain,
            vaultCache: mockVaultCache,
            pinUnlock: KeychainPinUnlockService(keychain: mockKeychain, crypto: mockCrypto)
        )
        try await sut.setServerEnvironment(ServerEnvironment(
            base: URL(string: "https://vault.example.com")!, overrides: nil
        ))
        mockAPI.preLoginResponse = PreLoginResponse(
            kdf: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil
        )
        mockCrypto.stubbedServerHash = "hash=="
    }

    // MARK: - Helpers

    /// Drives `loginWithPassword` far enough to leave a pending challenge, and returns the method.
    @discardableResult
    private func challenge(_ providers: [Int]) async throws -> TwoFactorMethod {
        mockAPI.tokenTwoFactorProviders = providers
        let result = try await sut.loginWithPassword(
            email: "alice@example.com", masterPassword: Data("pw!".utf8)
        )
        guard case .requiresTwoFactor(let method) = result else {
            throw TestFailure("expected .requiresTwoFactor, got \(result)")
        }
        return method
    }

    /// Puts the token endpoint into a state where it answers a code submission successfully.
    private func acceptNextCode() {
        mockAPI.tokenTwoFactorProviders = nil
        mockAPI.tokenResponse = TokenResponse(
            accessToken: "access", refreshToken: "refresh", tokenType: "Bearer",
            expiresIn: 3600, key: "2.encUserKey==", privateKey: "2.encPrivateKey==",
            kdf: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil,
            twoFactorToken: nil, twoFactorProviders: nil,
            userId: "user-guid-001", email: "alice@example.com", name: "Alice"
        )
    }

    // MARK: - What the wire carries

    func testAuthenticatorCode_isSentAsProviderZero() async throws {
        try await challenge([0])
        acceptNextCode()
        _ = try await sut.loginWithTwoFactorCode("123456", rememberDevice: false)

        XCTAssertEqual(mockAPI.lastTwoFactorProvider, 0)
        XCTAssertEqual(mockAPI.lastTwoFactorToken, "123456")
    }

    func testEmailCode_isSentAsProviderOne() async throws {
        try await challenge([1])
        acceptNextCode()
        _ = try await sut.loginWithTwoFactorCode("654321", rememberDevice: false)

        XCTAssertEqual(mockAPI.lastTwoFactorProvider, 1,
                       "an emailed code must not be submitted as an authenticator code")
    }

    func testYubiKeyCode_isSentAsProviderThree() async throws {
        try await challenge([3])
        acceptNextCode()
        let otp = "cbdefghijklnrtuvcbdefghijklnrtuvcbdefghijklnrtuvcbde"
        _ = try await sut.loginWithTwoFactorCode(otp, rememberDevice: false)

        XCTAssertEqual(mockAPI.lastTwoFactorProvider, 3)
        XCTAssertEqual(mockAPI.lastTwoFactorToken, otp,
                       "the code must reach the server unaltered — a YubiKey code is letters")
    }

    // MARK: - Which method is chosen

    func testSeveralOffered_theFirstSupportedIsChosen() async throws {
        let method = try await challenge([1, 3, 0])
        XCTAssertEqual(method.provider, .authenticatorApp)
    }

    func testOnlyUnsupportedOffered_namesThem() async throws {
        let method = try await challenge([2, 7])
        guard case .unsupported(let names) = method else {
            return XCTFail("expected .unsupported, got \(method)")
        }
        XCTAssertEqual(names, ["Duo", "WebAuthn"])
    }

    func testNothingCompletableOffered_storesNoChallenge() async throws {
        _ = try await challenge([2])
        // No pending state means no resend and no submission; both must be refused rather than
        // silently reusing the password hash.
        await XCTAssertThrowsErrorAsync(try await sut.sendEmailTwoFactorCode())
    }

    // MARK: - Resend

    func testResend_asksTheServerOnce() async throws {
        try await challenge([1])
        try await sut.sendEmailTwoFactorCode()

        XCTAssertEqual(mockAPI.sendEmailCodeCallCount, 1)
        XCTAssertEqual(mockAPI.sendEmailCodeEmail, "alice@example.com",
                       "the code goes to the account's own address; nothing else is accepted")
    }

    func testResend_forANonEmailMethodIsRefused() async throws {
        // Resend has no meaning for an authenticator app, and sending mail anyway would be a
        // surprise to the user and a rate-limit cost on the server.
        try await challenge([0])
        await XCTAssertThrowsErrorAsync(try await sut.sendEmailTwoFactorCode()) { error in
            XCTAssertTrue(error is AuthError)
        }
        XCTAssertEqual(mockAPI.sendEmailCodeCallCount, 0)
    }

    func testResendFailure_propagatesSoThePromptCanSaySo() async throws {
        try await challenge([1])
        mockAPI.sendEmailCodeShouldThrow = APIError.httpError(statusCode: 429, body: "rate limited")
        await XCTAssertThrowsErrorAsync(try await sut.sendEmailTwoFactorCode())
    }

    // MARK: - A rejected code leaves the challenge intact

    func testRejectedCode_doesNotConsumeTheChallenge() async throws {
        try await challenge([0])
        mockAPI.tokenShouldThrow = AuthError.invalidTwoFactorCode

        await XCTAssertThrowsErrorAsync(
            try await sut.loginWithTwoFactorCode("000000", rememberDevice: false)
        ) { error in
            XCTAssertEqual(error as? AuthError, .invalidTwoFactorCode)
        }

        // The pending key material survives, so the user can correct a typo without typing the
        // master password again (spec: "the derived key material SHALL NOT be discarded").
        mockAPI.tokenShouldThrow = nil
        acceptNextCode()
        let account = try await sut.loginWithTwoFactorCode("123456", rememberDevice: false)
        XCTAssertEqual(account.email, "alice@example.com")
    }
}

// MARK: -

/// A throwable stand-in for `XCTFail` inside a helper that returns a value.
private struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
