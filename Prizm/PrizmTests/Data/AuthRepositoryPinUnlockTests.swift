import XCTest
@testable import Prizm

/// The PIN as `AuthRepositoryImpl` wires it: what enables it, what unlocks with it, and what turns it
/// off.
///
/// The service's own behaviour is `PinUnlockServiceTests`. What is asserted here is the wiring, and
/// two of these are the ones that matter most: that the fifth failure reaches `signOut` rather than
/// stopping at an error, and that a cold start does not offer the PIN at all.
@MainActor
final class AuthRepositoryPinUnlockTests: XCTestCase {

    private var sut:      AuthRepositoryImpl!
    private var mockAPI:  MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var keychain: MockKeychainService!
    private var pinUnlock: KeychainPinUnlockService!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let userId = "11111111-2222-3333-4444-555555555555"
    private let email  = "alice@example.com"

    override func setUp() async throws {
        try await super.setUp()
        suiteName  = "AuthRepositoryPinUnlockTests-\(UUID().uuidString)"
        defaults   = UserDefaults(suiteName: suiteName)
        mockAPI    = MockPrizmAPIClient()
        mockCrypto = MockPrizmCryptoService()
        keychain   = MockKeychainService()
        pinUnlock  = KeychainPinUnlockService(keychain: keychain, crypto: mockCrypto)

        sut = AuthRepositoryImpl(
            apiClient: mockAPI,
            crypto:    mockCrypto,
            keychain:  keychain,
            biometricKeychain: MockBiometricKeychainService(),
            vaultCache: MockVaultCacheStore(),
            pinUnlock:  pinUnlock,
            userDefaults: defaults
        )
        try await sut.setServerEnvironment(ServerEnvironment(
            base: URL(string: "https://vault.example.com")!, overrides: nil
        ))
        mockAPI.preLoginResponse = PreLoginResponse(
            kdf: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil
        )
        mockCrypto.stubbedServerHash = "hash=="
        mockAPI.tokenResponse = TokenResponse(
            accessToken: "access", refreshToken: "refresh", tokenType: "Bearer",
            expiresIn: 3600, key: "2.encKey==", privateKey: nil,
            kdf: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil,
            twoFactorToken: nil, twoFactorProviders: nil,
            userId: userId, email: email, name: "Alice"
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        pinUnlock = nil
        keychain = nil
        mockCrypto = nil
        mockAPI = nil
        sut = nil
        try await super.tearDown()
    }

    /// Signs in and leaves the vault unlocked with key material, which is the precondition for
    /// setting a PIN.
    private func signInAndUnlock() async throws {
        _ = try await sut.loginWithPassword(email: email, masterPassword: Data("pw!".utf8))
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(repeating: 0xAB, count: 32),
            macKey:        Data(repeating: 0xCD, count: 32)
        ))
    }

    // MARK: - 3.1 enabling

    func testEnablePinUnlock_requiresAnUnlockedVault() async throws {
        _ = try await sut.loginWithPassword(email: email, masterPassword: Data("pw!".utf8))
        await mockCrypto.lockVault()

        await XCTAssertThrowsErrorAsync(try await self.sut.enablePinUnlock(pin: "2468")) { error in
            XCTAssertEqual(error as? AuthError, .vaultLocked)
        }
        XCTAssertFalse(pinUnlock.isSet(userId: userId), "nothing may be stored without live key material")
    }

    func testEnableThenDisable() async throws {
        try await signInAndUnlock()

        try await sut.enablePinUnlock(pin: "2468")
        XCTAssertTrue(pinUnlock.isSet(userId: userId))

        try await sut.disablePinUnlock()
        XCTAssertFalse(pinUnlock.isSet(userId: userId))
    }

    // MARK: - 3.2 unlocking

    func testUnlockWithPIN_returnsTheAccount() async throws {
        try await signInAndUnlock()
        try await sut.enablePinUnlock(pin: "2468")
        // A lock, not a sign-out: the session has to survive for a PIN to be useful.
        await mockCrypto.lockVault()

        let account = try await sut.unlockWithPIN("2468")

        XCTAssertEqual(account.userId, userId)
        XCTAssertEqual(account.email, email)
        XCTAssertTrue(mockCrypto.isUnlocked, "the vault must actually be open afterwards")
    }

    func testUnlockWithPIN_wrongPin_doesNotUnlock() async throws {
        try await signInAndUnlock()
        try await sut.enablePinUnlock(pin: "2468")
        await mockCrypto.lockVault()

        await XCTAssertThrowsErrorAsync(try await self.sut.unlockWithPIN("0000")) { error in
            guard case PinUnlockError.incorrectPin = error else {
                return XCTFail("expected .incorrectPin, got \(error)")
            }
        }
        XCTAssertFalse(mockCrypto.isUnlocked)
    }

    // MARK: - 3.2 / 3.3 the fifth failure signs out

    /// The service wipes the material; this asserts the *repository* finishes the job. Without it the
    /// user would be left on the unlock screen with a four-digit code that no longer works and no
    /// explanation.
    func testFifthFailure_signsOutAndRemovesTheSession() async throws {
        try await signInAndUnlock()
        try await sut.enablePinUnlock(pin: "2468")
        await mockCrypto.lockVault()

        for _ in 0..<4 { _ = try? await sut.unlockWithPIN("0000") }

        await XCTAssertThrowsErrorAsync(try await self.sut.unlockWithPIN("0000")) { error in
            XCTAssertEqual(error as? PinUnlockError, .attemptsExhausted)
        }

        XCTAssertFalse(pinUnlock.isSet(userId: userId), "the PIN material must be gone")
        XCTAssertNil(try? keychain.read(key: KeychainKey.activeUserId), "and so must the session")
    }

    func testSignOut_removesThePin() async throws {
        try await signInAndUnlock()
        try await sut.enablePinUnlock(pin: "2468")

        try await sut.signOut()

        XCTAssertFalse(pinUnlock.isSet(userId: userId))
    }

    /// Locking keeps the session, so it must keep the PIN — otherwise every lock would silently
    /// disable the feature the user configured.
    func testLockVault_keepsThePin() async throws {
        try await signInAndUnlock()
        try await sut.enablePinUnlock(pin: "2468")

        await sut.lockVault()

        XCTAssertTrue(pinUnlock.isSet(userId: userId))
    }

    // MARK: - 3.4 availability, and the restart setting

    func testPinUnlockAvailable_isFalseWithNoPin() async throws {
        try await signInAndUnlock()

        XCTAssertFalse(sut.pinUnlockAvailable)
    }

    func testPinUnlockAvailable_isTrueAfterAFullAuthentication() async throws {
        try await signInAndUnlock()
        try await sut.enablePinUnlock(pin: "2468")

        XCTAssertTrue(sut.pinUnlockAvailable, "the master password was just accepted in this launch")
    }

    /// The setting's default is what makes this feature opt-in rather than a hole: a freshly launched
    /// app has had no full authentication, so the PIN is not offered.
    func testPinUnlockAvailable_isFalseOnAFreshLaunchByDefault() async throws {
        // Material present in the Keychain, as if a previous run had set it.
        keychain.seed(key: KeychainKey.activeUserId, value: userId)
        keychain.seed(key: KeychainKey.user(userId, "email"), value: email)
        keychain.seed(key: KeychainKey.user(userId, "serverEnvironment"),
                      value: #"{"base":"https://vault.example.com"}"#)
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(repeating: 0xAB, count: 32),
            macKey:        Data(repeating: 0xCD, count: 32)
        ))
        try await sut.enablePinUnlock(pin: "2468")

        // A new repository over the same Keychain is what a relaunch amounts to: it has seen no
        // authentication in *this* launch.
        let relaunched = AuthRepositoryImpl(
            apiClient: mockAPI, crypto: mockCrypto, keychain: keychain,
            biometricKeychain: MockBiometricKeychainService(),
            vaultCache: MockVaultCacheStore(), pinUnlock: pinUnlock, userDefaults: defaults
        )

        XCTAssertFalse(
            relaunched.pinUnlockAvailable,
            "with the default setting, a PIN must not open an app that has not been opened properly"
        )
    }

    func testPinUnlockAvailable_respectsTheRestartSettingWhenTurnedOff() async throws {
        keychain.seed(key: KeychainKey.activeUserId, value: userId)
        keychain.seed(key: KeychainKey.user(userId, "email"), value: email)
        keychain.seed(key: KeychainKey.user(userId, "serverEnvironment"),
                      value: #"{"base":"https://vault.example.com"}"#)
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(repeating: 0xAB, count: 32),
            macKey:        Data(repeating: 0xCD, count: 32)
        ))
        try await sut.enablePinUnlock(pin: "2468")
        PinUnlockSettings.setRequiresMasterPasswordOnRestart(false, in: defaults)

        let relaunched = AuthRepositoryImpl(
            apiClient: mockAPI, crypto: mockCrypto, keychain: keychain,
            biometricKeychain: MockBiometricKeychainService(),
            vaultCache: MockVaultCacheStore(), pinUnlock: pinUnlock, userDefaults: defaults
        )

        XCTAssertTrue(
            relaunched.pinUnlockAvailable,
            "turning the setting off is the user accepting that a PIN may open a restarted app"
        )
    }

    // MARK: - The remaining count reaches the UI

    func testRemainingAttempts_areExposed() async throws {
        try await signInAndUnlock()
        try await sut.enablePinUnlock(pin: "2468")
        XCTAssertEqual(sut.pinUnlockRemainingAttempts, PinUnlockSettings.maximumAttempts)

        _ = try? await sut.unlockWithPIN("0000")

        XCTAssertEqual(sut.pinUnlockRemainingAttempts, PinUnlockSettings.maximumAttempts - 1)
    }
}
