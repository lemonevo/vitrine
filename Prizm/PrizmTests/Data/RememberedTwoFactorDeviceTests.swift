import XCTest
@testable import Prizm

/// "Remember this device" — the checkbox that used to do nothing.
///
/// The token was always sent to the server and always returned; Prizm decoded it and dropped it, so
/// the next login sent `twoFactorToken: nil` and the challenge came back. The user had been told, by a
/// checkbox, that it would not.
@MainActor
final class RememberedTwoFactorDeviceTests: XCTestCase {

    private var sut:      AuthRepositoryImpl!
    private var mockAPI:  MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var keychain: MockKeychainService!

    private let email = "alice@example.com"

    override func setUp() async throws {
        try await super.setUp()
        mockAPI    = MockPrizmAPIClient()
        mockCrypto = MockPrizmCryptoService()
        keychain   = MockKeychainService()
        sut = AuthRepositoryImpl(
            apiClient: mockAPI,
            crypto:    mockCrypto,
            keychain:  keychain,
            biometricKeychain: MockBiometricKeychainService(),
            vaultCache: MockVaultCacheStore(),
            pinUnlock: KeychainPinUnlockService(keychain: keychain, crypto: mockCrypto)
        )
        // The login path reads the configured server before anything else, so a suite that skips
        // this fails with `serverUnreachable` before reaching the behaviour under test.
        try await sut.setServerEnvironment(ServerEnvironment(
            base: URL(string: "https://vault.example.com")!, overrides: nil
        ))
        mockAPI.preLoginResponse = PreLoginResponse(
            kdf: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil
        )
        mockCrypto.stubbedServerHash = "hash=="
        // A login succeeds by default, so a replay test does not have to configure anything; the
        // challenge helper below removes it because the mock signals a challenge only when there is
        // no success response to return instead.
        mockAPI.tokenResponse = successResponse(twoFactorToken: nil)
    }

    // MARK: - Helpers

    /// The success shape the other auth suites use, with the remembered token swapped in.
    private func successResponse(twoFactorToken: String?) -> TokenResponse {
        TokenResponse(
            accessToken: "access", refreshToken: "refresh", tokenType: "Bearer",
            expiresIn: 3600, key: "2.encKey==", privateKey: "2.encPrivateKey==",
            kdf: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil,
            twoFactorToken: twoFactorToken, twoFactorProviders: nil,
            userId: "user-guid-001", email: email, name: "Alice"
        )
    }

    private func signIn(withPassword password: String = "hunter2", email: String? = nil) async throws -> LoginResult {
        try await sut.loginWithPassword(
            email:          email ?? self.email,
            masterPassword: Data(password.utf8)
        )
    }

    /// Drives a login to the point where the server is asking for a code.
    ///
    /// The mock signals a challenge by returning a token response carrying `twoFactorProviders`
    /// rather than by throwing — the same shape the real client accepts.
    private func reachTwoFactorChallenge() async throws {
        mockAPI.tokenResponse = nil
        mockAPI.tokenTwoFactorProviders = [0]
        _ = try await signIn()
        mockAPI.tokenTwoFactorProviders = nil
    }

    /// Puts the next code submission in a position to succeed.
    private func acceptTheNextCode(rememberedToken: String?) {
        mockAPI.tokenResponse = successResponse(twoFactorToken: rememberedToken)
    }

    // MARK: - 1.1 stored when asked for

    func testTwoFactorLogin_withRemember_storesTheToken() async throws {
        try await reachTwoFactorChallenge()
        acceptTheNextCode(rememberedToken: "remembered-token")

        _ = try await sut.loginWithTwoFactorCode("123456", rememberDevice: true)

        XCTAssertEqual(
            try String(data: keychain.read(key: KeychainKey.twoFactorToken), encoding: .utf8),
            "remembered-token"
        )
    }

    /// The email is stored beside it: replaying a token for the wrong account would hand the server a
    /// credential that belongs to someone else.
    func testTwoFactorLogin_withRemember_storesTheEmailItBelongsTo() async throws {
        try await reachTwoFactorChallenge()
        acceptTheNextCode(rememberedToken: "remembered-token")

        _ = try await sut.loginWithTwoFactorCode("123456", rememberDevice: true)

        XCTAssertEqual(
            try String(data: keychain.read(key: KeychainKey.twoFactorEmail), encoding: .utf8),
            email
        )
    }

    // MARK: - 1.2 nothing stored when not asked for

    func testTwoFactorLogin_withoutRemember_storesNothing() async throws {
        try await reachTwoFactorChallenge()
        acceptTheNextCode(rememberedToken: "remembered-token")

        _ = try await sut.loginWithTwoFactorCode("123456", rememberDevice: false)

        XCTAssertFalse(
            keychain.writtenKeys.contains(KeychainKey.twoFactorToken),
            "storing it anyway would remember a device the user declined to remember"
        )
    }

    // MARK: - 1.3 a response with no token

    /// The second way this checkbox can do nothing. The login still succeeds — the user is in — and
    /// nothing is stored, because there is nothing to store.
    func testTwoFactorLogin_withRememberButNoToken_stillSucceedsAndStoresNothing() async throws {
        try await reachTwoFactorChallenge()
        acceptTheNextCode(rememberedToken: nil)

        let account = try await sut.loginWithTwoFactorCode("123456", rememberDevice: true)

        XCTAssertFalse(account.userId.isEmpty, "the login itself must not be affected")
        XCTAssertFalse(keychain.writtenKeys.contains(KeychainKey.twoFactorToken))
    }

    // MARK: - 2.1 the token is replayed

    func testLogin_withARememberedDevice_sendsTheToken() async throws {
        keychain.seed(key: KeychainKey.twoFactorToken, value: "remembered-token")
        keychain.seed(key: KeychainKey.twoFactorEmail, value: email)

        _ = try await signIn()

        XCTAssertEqual(mockAPI.lastTwoFactorToken, "remembered-token")
    }

    // MARK: - 2.2 a different account

    func testLogin_forADifferentAccount_doesNotSendTheToken() async throws {
        keychain.seed(key: KeychainKey.twoFactorToken, value: "remembered-token")
        keychain.seed(key: KeychainKey.twoFactorEmail, value: email)

        _ = try await signIn(email: "bob@example.com")

        XCTAssertNil(mockAPI.lastTwoFactorToken, "another account's token is not this account's to use")
        XCTAssertEqual(
            try String(data: keychain.read(key: KeychainKey.twoFactorToken), encoding: .utf8),
            "remembered-token",
            "and it must still be there for its own account"
        )
    }

    // MARK: - 2.3 the comparison normalises

    func testLogin_matchesTheEmailDespiteWhitespaceAndCase() async throws {
        keychain.seed(key: KeychainKey.twoFactorToken, value: "remembered-token")
        keychain.seed(key: KeychainKey.twoFactorEmail, value: "  Alice@Example.COM  ")

        _ = try await signIn(email: email)

        XCTAssertEqual(mockAPI.lastTwoFactorToken, "remembered-token")
    }

    // MARK: - 2.4 nothing stored means nothing sent

    /// The guard against the replay path going unconditional.
    func testLogin_withNothingRemembered_sendsNoToken() async throws {
        _ = try await signIn()

        XCTAssertNil(mockAPI.lastTwoFactorToken)
    }

    /// A token stored without an email cannot be attributed to an account, so it must not be sent.
    func testLogin_withATokenButNoEmail_doesNotSendIt() async throws {
        keychain.seed(key: KeychainKey.twoFactorToken, value: "orphaned-token")

        _ = try await signIn()

        XCTAssertNil(mockAPI.lastTwoFactorToken)
    }

    // MARK: - 3.1 / 3.3 lifecycle

    func testSignOut_forgetsTheDevice() async throws {
        keychain.seed(key: KeychainKey.twoFactorToken, value: "remembered-token")
        keychain.seed(key: KeychainKey.twoFactorEmail, value: email)

        try await sut.signOut()

        XCTAssertTrue(keychain.deletedKeys.contains(KeychainKey.twoFactorToken))
        XCTAssertTrue(keychain.deletedKeys.contains(KeychainKey.twoFactorEmail))
    }

    /// Locking keeps the session, and a remembered device is part of the session rather than of the
    /// unlocked state — otherwise every lock would silently forget it.
    func testLockVault_doesNotForgetTheDevice() async throws {
        keychain.seed(key: KeychainKey.twoFactorToken, value: "remembered-token")
        keychain.seed(key: KeychainKey.twoFactorEmail, value: email)

        await sut.lockVault()

        XCTAssertFalse(keychain.deletedKeys.contains(KeychainKey.twoFactorToken))
        XCTAssertFalse(keychain.deletedKeys.contains(KeychainKey.twoFactorEmail))
    }
}
