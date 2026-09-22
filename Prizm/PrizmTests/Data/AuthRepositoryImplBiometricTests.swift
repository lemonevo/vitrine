import LocalAuthentication
import Security
import XCTest
@testable import Prizm

/// Tests for `AuthRepositoryImpl` biometric unlock methods.
@MainActor
final class AuthRepositoryImplBiometricTests: XCTestCase {

    private var sut: AuthRepositoryImpl!
    private var mockAPI: MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var mockKeychain: MockKeychainService!
    private var mockBiometricKeychain: MockBiometricKeychainService!
    private var mockVaultCache: MockVaultCacheStore!

    private let testUserId = "test-user-id"
    private let testEmail  = "test@example.com"
    private let testEnv    = ServerEnvironment(
        base: URL(string: "https://vault.example.com")!,
        overrides: nil
    )

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
        // Seed Keychain with a stored session so account(for:) works.
        seedStoredSession()
        // Clear UserDefaults between tests.
        UserDefaults.standard.removeObject(forKey: "biometricUnlockEnabled")
        UserDefaults.standard.removeObject(forKey: "biometricEnrollmentPromptShown")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "biometricUnlockEnabled")
        UserDefaults.standard.removeObject(forKey: "biometricEnrollmentPromptShown")
        try await super.tearDown()
    }

    // MARK: - enableBiometricUnlock

    func testEnableBiometricUnlock_vaultLocked_throws() async {
        mockCrypto._isUnlocked = false
        do {
            try await sut.enableBiometricUnlock()
            XCTFail("Expected biometricUnavailable")
        } catch {
            XCTAssertEqual(error as? AuthError, .biometricUnavailable)
        }
    }

    func testEnableBiometricUnlock_vaultUnlocked_writesKeychain() async throws {
        mockCrypto._isUnlocked = true
        try await sut.enableBiometricUnlock()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"))
        // Verify the biometric keychain has a 64-byte item.
        let key = KeychainKey.biometricVaultKey(testUserId)
        let data = try await mockBiometricKeychain.readBiometric(key: key)
        XCTAssertEqual(data.count, 64)
    }

    /// An ad-hoc signed build cannot create a biometric Keychain item: macOS rejects the
    /// write with `errSecMissingEntitlement` because `keychain-access-groups` is missing.
    /// That must surface as a named error — the old code let the write throw and the
    /// Settings toggle flipped back with no explanation at all.
    func testEnableBiometricUnlock_missingEntitlement_reportsUnsupportedBuild() async {
        mockCrypto._isUnlocked = true
        mockBiometricKeychain.writeError = KeychainError.unexpectedStatus(errSecMissingEntitlement)

        do {
            try await sut.enableBiometricUnlock()
            XCTFail("Expected biometricUnsupportedInBuild")
        } catch {
            XCTAssertEqual(error as? AuthError, .biometricUnsupportedInBuild)
        }
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"),
            "a failed write must not leave the preference enabled"
        )
    }

    /// Only the entitlement failure gets the friendly name; anything else stays a
    /// `KeychainError` so the caller can still see the raw OSStatus.
    func testEnableBiometricUnlock_otherKeychainFailure_propagates() async {
        mockCrypto._isUnlocked = true
        mockBiometricKeychain.writeError = KeychainError.unexpectedStatus(errSecIO)

        do {
            try await sut.enableBiometricUnlock()
            XCTFail("Expected the KeychainError to propagate")
        } catch {
            XCTAssertEqual(error as? KeychainError, .unexpectedStatus(errSecIO))
        }
    }

    // MARK: - disableBiometricUnlock

    /// **The setting stays on when the key would not delete.** Clearing the flag over a failed delete
    /// would report "off" while a stored key an enrolled fingerprint can still unwrap is left behind,
    /// and it would take away the only retry the user has — a switch that already reads off cannot be
    /// turned off again.
    func testDisableBiometricUnlock_whenTheDeleteFails_keepsTheSettingOnAndThrows() async throws {
        mockCrypto._isUnlocked = true
        try await sut.enableBiometricUnlock()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"))

        mockBiometricKeychain.deleteError = KeychainError.unexpectedStatus(errSecIO)

        do {
            try await sut.disableBiometricUnlock()
            XCTFail("a key that survived must not be reported as deleted")
        } catch let error as AuthError {
            XCTAssertEqual(error, .secretRetirementFailed)
        }

        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"),
                      "the feature is still genuinely available, so the setting must say so")

        // Retrying once the Keychain cooperates finishes the job.
        mockBiometricKeychain.deleteError = nil
        try await sut.disableBiometricUnlock()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"))
    }

    func testDisableBiometricUnlock_clearsPreferenceAndKeychain() async throws {
        // Enable first.
        mockCrypto._isUnlocked = true
        try await sut.enableBiometricUnlock()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"))

        try await sut.disableBiometricUnlock()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"))
        // Keychain item should be gone.
        let key = KeychainKey.biometricVaultKey(testUserId)
        do {
            _ = try await mockBiometricKeychain.readBiometric(key: key)
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    // MARK: - unlockWithBiometrics

    func testUnlockWithBiometrics_success_returnsAccount() async throws {
        // Seed a biometric key.
        let keys = CryptoKeys(encryptionKey: Data(count: 32), macKey: Data(count: 32))
        try mockBiometricKeychain.writeBiometric(
            data: keys.toData(),
            key: KeychainKey.biometricVaultKey(testUserId)
        )

        let account = try await sut.unlockWithBiometrics()
        XCTAssertEqual(account.email, testEmail)
    }

    func testUnlockWithBiometrics_itemNotFound_throwsBiometricItemNotFound() async {
        // No biometric key in keychain — externally deleted or never written.
        // Must throw .biometricItemNotFound (silent degradation), not .biometricInvalidated.
        do {
            _ = try await sut.unlockWithBiometrics()
            XCTFail("Expected biometricItemNotFound")
        } catch {
            XCTAssertEqual(error as? AuthError, .biometricItemNotFound)
            XCTAssertFalse(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"))
            XCTAssertFalse(UserDefaults.standard.bool(forKey: "biometricEnrollmentPromptShown"))
        }
    }

    /// The system locked the sensor after repeated failures. Before this case existed the raw
    /// `LAError` reached the unlock screen, whose generic handler prints `localizedDescription` — an
    /// untranslated framework string that names neither the cause nor the way out.
    func testUnlockWithBiometrics_sensorLockedOut_reportsLockout() async {
        mockBiometricKeychain.readError = LAError(.biometryLockout)

        do {
            _ = try await sut.unlockWithBiometrics()
            XCTFail("Expected biometricLockout")
        } catch {
            XCTAssertEqual(error as? AuthError, .biometricLockout)
        }
    }

    /// Lockout is the sensor resting, not the enrollment changing. Turning biometric unlock off here
    /// would punish the user for something macOS will undo on its own, and would mean the next launch
    /// has no Touch ID at all for someone whose only crime was five bad fingers.
    func testUnlockWithBiometrics_lockoutDoesNotDisableTheFeature() async {
        UserDefaults.standard.set(true, forKey: "biometricUnlockEnabled")
        UserDefaults.standard.set(true, forKey: "biometricEnrollmentPromptShown")
        mockBiometricKeychain.readError = LAError(.biometryLockout)

        _ = try? await sut.unlockWithBiometrics()

        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"),
                      "A locked-out sensor must leave the setting on")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricEnrollmentPromptShown"),
                      "…and must not clear the seen-prompt flag, which would nag again on next unlock")
    }

    // MARK: - signOut clears biometric

    func testSignOut_deletesBiometricKeychainItem() async throws {
        mockCrypto._isUnlocked = true
        try await sut.enableBiometricUnlock()
        try await sut.signOut()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "biometricUnlockEnabled"))
    }

    // MARK: - Helpers

    private func seedStoredSession() {
        mockKeychain.seed(key: "bw.macos:activeUserId", value: testUserId)
        mockKeychain.seed(key: "bw.macos:\(testUserId):email", value: testEmail)
        let env = try! JSONEncoder().encode(testEnv)
        mockKeychain.seed(key: "bw.macos:\(testUserId):serverEnvironment", data: env)
        mockKeychain.seed(key: "bw.macos:\(testUserId):accessToken", value: "token")
        mockKeychain.seed(key: "bw.macos:\(testUserId):refreshToken", value: "refresh")
    }
}
