import XCTest
@testable import Prizm

/// Covers `AuthRepositoryImpl.verifyMasterPassword` — the check the re-prompt gate asks for.
///
/// **What this cannot cover, and why.** The key derivation itself. `MockPrizmCryptoService`
/// returns a stub from `makeMasterKey` and `stretchKey`, so no password is ever really derived
/// here and this suite says nothing about whether the derivation is right — only about what the
/// repository does with the result it is handed. That is the split worth having: the derivation
/// has its own tests, and a suite that ran real Argon2id at production iteration counts would be
/// too slow to keep running.
@MainActor
final class AuthRepositoryVerifyMasterPasswordTests: XCTestCase {

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
    }

    /// Seeds the same Keychain keys `unlockWithPassword` needs and marks the vault unlocked.
    ///
    /// The unlocked flag is not incidental: verification compares against the *live* key, so the
    /// session is the one thing this call genuinely depends on.
    private func seedSession(userId: String = "user-001", withKdfParams: Bool = true) throws {
        let env = ServerEnvironment(base: URL(string: "https://vault.example.com")!, overrides: nil)
        let kdf = KdfParams(type: .pbkdf2, iterations: 600_000, memory: nil, parallelism: nil)
        mockKeychain.seed(key: "bw.macos:activeUserId",         value: userId)
        mockKeychain.seed(key: "bw.macos:\(userId):email",      value: "alice@example.com")
        mockKeychain.seed(key: "bw.macos:\(userId):encUserKey", value: "2.encKey==")
        mockKeychain.seed(key: "bw.macos:\(userId):serverEnvironment",
                          value: String(data: try JSONEncoder().encode(env), encoding: .utf8)!)
        if withKdfParams {
            mockKeychain.seed(key: "bw.macos:\(userId):kdfParams",
                              value: String(data: try JSONEncoder().encode(kdf), encoding: .utf8)!)
        }
        mockCrypto._isUnlocked = true
    }

    // MARK: - The answer

    func testCorrectPassword_returnsTrue() async throws {
        try seedSession()

        let matches = try await sut.verifyMasterPassword(Data("masterPassword1!".utf8))

        XCTAssertTrue(matches)
    }

    /// A wrong password is `false` and never a thrown error. It fails the MAC check inside the
    /// encrypted user key, which is the expected answer to a question rather than a fault — and
    /// if it threw, every mistyped password would reach the user as an error banner.
    func testWrongPassword_returnsFalse() async throws {
        try seedSession()
        mockCrypto.decryptSymmetricKeyError = PrizmCryptoServiceError.invalidEncUserKey

        let matches = try await sut.verifyMasterPassword(Data("wrong".utf8))

        XCTAssertFalse(matches)
    }

    /// The comparison, not merely the decryption.
    ///
    /// A successful decryption says "this password produced *a* key". The gate needs "this
    /// password produced the key this vault is open with". Those only differ if the decrypted
    /// result can differ from the live key, which is what `stubbedDecryptedSymmetricKeys` is
    /// for — without it the comparison can never fail and so is never actually tested.
    func testDecryptedKeyDiffersFromLiveKey_returnsFalse() async throws {
        try seedSession()
        mockCrypto.stubbedDecryptedSymmetricKeys = CryptoKeys(
            encryptionKey: Data(repeating: 0xAA, count: 32),
            macKey:        Data(repeating: 0xBB, count: 32)
        )

        let matches = try await sut.verifyMasterPassword(Data("masterPassword1!".utf8))

        XCTAssertFalse(matches)
    }

    // MARK: - Could not check

    /// A locked vault is "this could not be checked", and reporting it as "wrong password" would
    /// be the same answer for a different reason. The live key is fetched before the derivation
    /// precisely so this stays distinguishable.
    func testLockedVault_throws() async throws {
        try seedSession()
        mockCrypto._isUnlocked = false

        await XCTAssertThrowsErrorAsync(
            try await sut.verifyMasterPassword(Data("masterPassword1!".utf8))
        ) { error in
            XCTAssertEqual(error as? PrizmCryptoServiceError, .vaultLocked)
        }
    }

    func testNoStoredSession_throwsNoStoredSession() async throws {
        // Unlocked but with nothing stored — the only way to reach the missing-session path.
        // Leaving the default (locked) would surface `PrizmCryptoServiceError.vaultLocked`
        // first, because the live key is fetched before anything is read from the Keychain.
        mockCrypto._isUnlocked = true

        await XCTAssertThrowsErrorAsync(
            try await sut.verifyMasterPassword(Data("any".utf8))
        ) { error in
            XCTAssertEqual(error as? AuthError, .noStoredSession)
        }
    }

    /// Stored KDF parameters that are missing are a broken session, not a wrong password. Reusing
    /// `.invalidCredentials` here would put "check your password" on screen for a problem the
    /// user's password has nothing to do with.
    func testMissingKdfParams_throwsNoStoredSession() async throws {
        try seedSession(withKdfParams: false)

        await XCTAssertThrowsErrorAsync(
            try await sut.verifyMasterPassword(Data("masterPassword1!".utf8))
        ) { error in
            XCTAssertEqual(error as? AuthError, .noStoredSession)
        }
    }

    // MARK: - The session is not disturbed

    /// The whole reason this is not `unlockWithPassword`. A read-only question must not be
    /// answered by mutating anything: no re-derivation into the live key cache, no token
    /// refresh, no reconfiguration of the API client.
    func testVerificationLeavesTheSessionUntouched() async throws {
        try seedSession()

        _ = try await sut.verifyMasterPassword(Data("masterPassword1!".utf8))

        XCTAssertEqual(mockCrypto.unlockWithCallCount, 0,
                       "verification must not re-derive into the live key cache")
        XCTAssertEqual(mockCrypto.lockVaultCallCount, 0,
                       "verification must not clear key material")
        XCTAssertTrue(mockCrypto.isUnlocked, "the vault must still be unlocked afterwards")
        XCTAssertNil(mockAPI.storedAccessToken,
                     "no access token should be set — nothing was authenticated")
        XCTAssertNil(mockAPI.baseURL,
                     "the API client must not be reconfigured by a purely local check")
    }
}
