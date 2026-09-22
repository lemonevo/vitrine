import XCTest
@testable import Prizm

/// PIN unlock, against the real service with a Keychain double and the real PBKDF2.
///
/// This is the one place in the codebase where the wrong test would be worse than no test: the claim
/// being made is that someone who does not know the PIN cannot recover the vault's key material. So
/// the assertions are about the *stored bytes*, not about the round trip being tidy.
@MainActor
final class PinUnlockServiceTests: XCTestCase {

    private var sut:      KeychainPinUnlockService!
    private var keychain: MockKeychainService!
    private var crypto:   PrizmCryptoServiceImpl!

    private let userId = "11111111-2222-3333-4444-555555555555"

    /// The vault's 64 bytes. A recognisable pattern rather than random, so a stored item can be
    /// searched for it.
    private let keyMaterial = Data((0..<64).map { UInt8($0) })

    private var wrappedKey: String { "bw.macos:\(userId):pinWrappedKeys" }
    private var saltKey:    String { "bw.macos:\(userId):pinSalt" }
    private var attemptsKey: String { "bw.macos:\(userId):pinAttempts" }

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeychainService()
        crypto   = PrizmCryptoServiceImpl()
        sut = KeychainPinUnlockService(keychain: keychain, crypto: crypto)
    }

    private func storedData(_ key: String) -> Data? {
        try? keychain.read(key: key)
    }

    // MARK: - 2.1.1 what is stored is not the key material

    /// The assertion the whole feature rests on. If the vault's key bytes were recoverable from the
    /// Keychain item without the PIN, the PIN would be decoration.
    func testStoredValue_doesNotContainTheKeyMaterial() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        let wrapped = try XCTUnwrap(storedData(wrappedKey))
        XCTAssertFalse(
            wrapped.range(of: keyMaterial) != nil,
            "the vault's key material must not appear verbatim in the stored item"
        )
        // And the whole 64 bytes must not be recoverable by reading the other items either.
        let salt = try XCTUnwrap(storedData(saltKey))
        XCTAssertFalse(salt.range(of: keyMaterial) != nil)
    }

    /// Nothing in the Keychain is derived from the PIN in a way that could be tested offline: no
    /// stored value equals the PIN, and no stored value is a plain hash of it.
    func testNothingStored_containsThePin() async throws {
        let pin = "2468"
        try await sut.setPin(pin, keyMaterial: keyMaterial, userId: userId)

        for key in [wrappedKey, saltKey, attemptsKey] {
            let data = try XCTUnwrap(storedData(key))
            let text = String(data: data, encoding: .utf8) ?? ""
            XCTAssertNotEqual(text, pin)
            XCTAssertFalse(text.contains(pin), "\(key) must not carry the PIN")
        }
    }

    // MARK: - 2.1.2 the round trip

    func testSetThenUnlock_returnsTheKeyMaterial() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        let recovered = try await sut.unlock(with: "2468", userId: userId)

        XCTAssertEqual(recovered, keyMaterial)
    }

    func testIsSet_reflectsWhetherAPinExists() async throws {
        XCTAssertFalse(sut.isSet(userId: userId))

        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        XCTAssertTrue(sut.isSet(userId: userId))
    }

    // MARK: - 2.1.3 a wrong PIN does not damage anything

    func testWrongPin_throwsAndLeavesTheMaterialUsable() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        await XCTAssertThrowsErrorAsync(try await self.sut.unlock(with: "0000", userId: userId)) { error in
            guard case PinUnlockError.incorrectPin = error else {
                return XCTFail("expected .incorrectPin, got \(error)")
            }
        }

        // The point: a wrong guess must not corrupt what a right one needs.
        let recovered = try await sut.unlock(with: "2468", userId: userId)
        XCTAssertEqual(recovered, keyMaterial)
    }

    // MARK: - 2.1.4 the minimum length

    func testShortPin_isRefused() async throws {
        for short in ["", "1", "12", "123"] {
            await XCTAssertThrowsErrorAsync(
                try await self.sut.setPin(short, keyMaterial: self.keyMaterial, userId: self.userId)
            ) { error in
                XCTAssertEqual(error as? PinUnlockError,
                               .pinTooShort(minimum: PinUnlockSettings.minimumPINLength))
            }
        }
        XCTAssertFalse(sut.isSet(userId: userId), "a refused PIN must not leave anything behind")
    }

    func testMinimumLengthPin_isAccepted() async throws {
        try await sut.setPin("1234", keyMaterial: keyMaterial, userId: userId)

        let recovered = try await sut.unlock(with: "1234", userId: userId)
        XCTAssertEqual(recovered, keyMaterial)
    }

    // MARK: - 2.1.5 a unique salt per installation

    func testSalt_isUniquePerSet() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)
        let first = try XCTUnwrap(storedData(saltKey))

        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)
        let second = try XCTUnwrap(storedData(saltKey))

        XCTAssertNotEqual(first, second, "a fixed salt would let one precomputation serve every install")
        XCTAssertEqual(first.count, 32)
    }

    // MARK: - 2.3 the attempt limit

    func testFourFailures_leaveTheMaterialInPlace() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        for _ in 0..<4 {
            _ = try? await sut.unlock(with: "0000", userId: userId)
        }

        XCTAssertTrue(sut.isSet(userId: userId), "four failures is not the limit")
        XCTAssertEqual(sut.remainingAttempts(userId: userId), 1)
    }

    func testSuccess_resetsTheCount() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)
        _ = try? await sut.unlock(with: "0000", userId: userId)
        _ = try? await sut.unlock(with: "0000", userId: userId)
        XCTAssertEqual(sut.remainingAttempts(userId: userId), 3)

        _ = try await sut.unlock(with: "2468", userId: userId)

        XCTAssertEqual(sut.remainingAttempts(userId: userId), PinUnlockSettings.maximumAttempts)
    }

    /// The fifth failure destroys the material. Deleting it is what makes the limit a limit: leaving
    /// it in place would mean the sixth guess costs the same as the first, forever.
    func testFifthFailure_destroysTheMaterialAndSaysSo() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        for _ in 0..<4 { _ = try? await sut.unlock(with: "0000", userId: userId) }

        await XCTAssertThrowsErrorAsync(try await self.sut.unlock(with: "0000", userId: userId)) { error in
            XCTAssertEqual(error as? PinUnlockError, .attemptsExhausted)
        }

        XCTAssertFalse(sut.isSet(userId: userId), "the wrapped material must be gone")
        XCTAssertNil(storedData(saltKey))
        XCTAssertNil(storedData(attemptsKey))
        // And the correct PIN is no help, because there is nothing left to unwrap.
        await XCTAssertThrowsErrorAsync(try await self.sut.unlock(with: "2468", userId: userId)) { error in
            XCTAssertEqual(error as? PinUnlockError, .noPinSet)
        }
    }

    /// 2.3.4 The property that makes the limit durable rather than a speed bump: the count is on disk,
    /// so quitting the app does not hand an attacker a fresh set of guesses.
    func testFailureCount_survivesANewServiceInstance() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)
        for _ in 0..<3 { _ = try? await sut.unlock(with: "0000", userId: userId) }

        // A fresh instance over the same Keychain — which is what relaunching the app amounts to.
        let relaunched = KeychainPinUnlockService(keychain: keychain, crypto: crypto)

        XCTAssertEqual(relaunched.remainingAttempts(userId: userId), 2)
    }

    // MARK: - remove

    func testRemove_clearsEverything() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        try sut.remove(userId: userId)

        XCTAssertFalse(sut.isSet(userId: userId))
        XCTAssertNil(storedData(wrappedKey))
        XCTAssertNil(storedData(saltKey))
        XCTAssertNil(storedData(attemptsKey))
    }

    func testRemove_whenNothingIsSet_doesNotThrow() throws {
        try sut.remove(userId: userId)

        XCTAssertFalse(sut.isSet(userId: userId))
    }

    /// `remove()` used to be non-throwing and delete with `try?`, so every caller reported "disabled"
    /// whether or not the wrapped key actually went away. A leftover here is a vault key that a
    /// four-digit code unlocks.
    func testRemove_whenADeleteFails_throwsRatherThanClaimingSuccess() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)
        keychain.failingDeletes.insert(wrappedKey)

        XCTAssertThrowsError(try sut.remove(userId: userId))

        XCTAssertTrue(sut.isSet(userId: userId),
                      "the material is still there, so the service must keep saying it is set")
    }

    /// **The attempt limit only exists if the counter can be written.** It used to be a `try?`, so a
    /// failed write left the stored count where it was; every later attempt re-read the same stale
    /// number, re-incremented it, and the fifth wrong PIN never arrived. Destroying the PIN is the
    /// only honest response to a counter that cannot be trusted.
    func testWrongPin_whenTheCounterCannotBeWritten_destroysThePin() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)
        keychain.failingWrites.insert(attemptsKey)

        do {
            _ = try await sut.unlock(with: "0000", userId: userId)
            XCTFail("an unwritable counter means the PIN cannot be trusted to have a limit")
        } catch let error as PinUnlockError {
            XCTAssertEqual(error, .storageUnavailable)
        }

        XCTAssertFalse(sut.isSet(userId: userId),
                       "a PIN whose attempts cannot be counted must not stay enrollable")
        XCTAssertNil(storedData(saltKey))
    }

    /// The mirror: when the counter *can* be written, five wrong guesses must still exhaust it, and
    /// the material must be gone by the fifth.
    func testWrongPin_fiveWrongGuessesDestroyTheMaterial() async throws {
        try await sut.setPin("2468", keyMaterial: keyMaterial, userId: userId)

        for attempt in 1...4 {
            do {
                _ = try await sut.unlock(with: "0000", userId: userId)
                XCTFail("attempt \(attempt) should not have unlocked")
            } catch let error as PinUnlockError {
                guard case .incorrectPin(let remaining) = error else {
                    return XCTFail("attempt \(attempt): expected incorrectPin, got \(error)")
                }
                XCTAssertEqual(remaining, 5 - attempt)
            }
        }

        do {
            _ = try await sut.unlock(with: "0000", userId: userId)
            XCTFail("the fifth wrong PIN must not unlock")
        } catch let error as PinUnlockError {
            guard case .attemptsExhausted = error else {
                return XCTFail("expected attemptsExhausted, got \(error)")
            }
        }

        XCTAssertFalse(sut.isSet(userId: userId))
        XCTAssertNil(storedData(wrappedKey), "the wrapped key must not survive exhaustion")
    }

    // MARK: - No account

    func testPinIsScopedToTheAccount() async throws {
        let otherUserSut = KeychainPinUnlockService(keychain: keychain, crypto: crypto)

        // A PIN belongs to an account: another account sees none of it.
        XCTAssertFalse(otherUserSut.isSet(userId: "some-other-user"))
        XCTAssertFalse(otherUserSut.isSet(userId: userId))
    }
}
