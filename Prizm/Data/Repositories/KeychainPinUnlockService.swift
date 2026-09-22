import Foundation
import Security
import os.log

// MARK: - KeychainPinUnlockService

/// `PinUnlockService` backed by the Keychain.
///
/// Three items per account:
///
/// | item | contents |
/// |---|---|
/// | `pinWrappedKeys` | the vault's 64 bytes, encrypted under a PIN-derived key |
/// | `pinSalt`        | the salt those bytes were derived against |
/// | `pinAttempts`    | consecutive failures so far |
///
/// All three are `WhenUnlockedThisDeviceOnly` — device-only, not synchronised to iCloud, not in a
/// backup, and unreadable while the Mac is locked. That, plus the attempt limit, is what protects the
/// wrapped key; the derivation deliberately is not load-bearing (see `PinUnlockService`).
///
/// **The attempt count is stored, not held in memory.** An in-memory counter is cleared by quitting
/// the app, so someone with the disk could take five guesses, restart, and take five more — that is
/// the appearance of a limit rather than one. The count survives a restart; nothing else here does.
final class KeychainPinUnlockService: PinUnlockService {

    /// PBKDF2-SHA256 rounds.
    ///
    /// Deliberately **not** the account's KDF iteration count. That number is tuned for a master
    /// password, which has far more entropy; applying it here would make every PIN unlock about as slow
    /// as a master-password login — slow enough that people stop using the feature — without closing a
    /// ten-thousand-value search space. This figure raises the cost of a bulk offline attack on the
    /// wrapped blob and is honest about being a speed bump rather than the wall.
    static let derivationRounds: UInt32 = 210_000

    private let keychain: KeychainService
    private let crypto:   any PrizmCryptoService
    private let logger = Logger(subsystem: "com.prizm", category: "PinUnlock")

    init(keychain: KeychainService, crypto: any PrizmCryptoService) {
        self.keychain = keychain
        self.crypto   = crypto
    }

    // MARK: - Availability

    func isSet(userId: String) -> Bool {
        do {
            return try keychain.read(key: Self.wrappedKey(userId)) != nil
        } catch {
            // `false`, and said out loud rather than guessed at. The PIN stops being offered until the
            // Keychain reads again; the alternative is an error on the unlock screen that blocks master
            // password entry over a convenience feature.
            logger.error("Could not check whether a PIN is set: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func remainingAttempts(userId: String) -> Int {
        let failures = (try? readAttempts(userId)) ?? 0
        return max(0, PinUnlockSettings.maximumAttempts - failures)
    }

    // MARK: - Setting

    func setPin(_ pin: String, keyMaterial: Data, userId: String) async throws {
        guard pin.count >= PinUnlockSettings.minimumPINLength else {
            throw PinUnlockError.pinTooShort(minimum: PinUnlockSettings.minimumPINLength)
        }

        let salt = try Self.makeSalt()
        let wrapped = try await wrap(keyMaterial, pin: pin, salt: salt)

        do {
            // Salt first, then the wrapped value, then the count. The wrapped value is what `isSet()`
            // looks for, so writing it before its salt would leave a window in which a PIN appears to
            // be set but cannot be used.
            try keychain.write(data: salt, key: Self.saltKey(userId))
            try keychain.write(data: Data(wrapped.utf8), key: Self.wrappedKey(userId))
            try keychain.write(data: Data("0".utf8), key: Self.attemptsKey(userId))
        } catch {
            logger.error("Could not store the PIN material: \(error.localizedDescription, privacy: .public)")
            // Cleanup after a half-written enrollment. If this also fails there is a wrapped blob
            // without a usable salt; `remove` has already logged that, and the throw below is what the
            // user hears.
            try? remove(userId: userId)
            throw PinUnlockError.storageUnavailable
        }
        logger.info("PIN unlock enabled")
    }

    // MARK: - Unlocking

    func unlock(with pin: String, userId: String) async throws -> Data {
        guard let salt = try? keychain.read(key: Self.saltKey(userId)),
              let wrappedData = try? keychain.read(key: Self.wrappedKey(userId)),
              let wrapped = String(data: wrappedData, encoding: .utf8) else {
            throw PinUnlockError.noPinSet
        }

        do {
            let material = try await unwrap(wrapped, pin: pin, salt: salt)
            // Only a success resets the count — resetting on any completed attempt would let a wrong
            // PIN buy another five. A failed reset is deliberately not fatal: the count stays high, so
            // the next wrong guess locks out early. That is the safe direction to be wrong in.
            do {
                try keychain.write(data: Data("0".utf8), key: Self.attemptsKey(userId))
            } catch {
                logger.error("""
                The PIN attempt counter could not be reset after a successful unlock \
                (\(error.localizedDescription, privacy: .public)); the next wrong PIN may lock out sooner \
                than it should.
                """)
            }
            logger.info("PIN unlock succeeded")
            return material
        } catch {
            let remaining = try recordFailure(userId)
            logger.error("PIN unlock failed; \(remaining, privacy: .public) attempt(s) remaining")
            // The material is gone by now, so there is nothing left to try against. Saying so is
            // what tells the caller to sign the user out rather than show "wrong PIN" again.
            throw remaining > 0 ? PinUnlockError.incorrectPin(remainingAttempts: remaining)
                                : PinUnlockError.attemptsExhausted
        }
    }

    // MARK: - Removing

    func remove(userId: String) throws {
        // `KeychainService.delete` treats an absent item as success, so a PIN that was never set does
        // not make this throw. Anything that does fail is a real failure to destroy key material.
        let keys = [Self.wrappedKey(userId), Self.saltKey(userId), Self.attemptsKey(userId)]
        let survivors = keys.filter { (try? keychain.delete(key: $0)) == nil }
        guard survivors.isEmpty else {
            logger.fault("""
            PIN material could not be fully removed: \(survivors.count, privacy: .public) of \
            \(keys.count, privacy: .public) items survived. The wrapped key material may still be \
            unlockable by guessing the PIN.
            """)
            throw PinUnlockError.storageUnavailable
        }
    }

    // MARK: - Private

    private func wrap(_ keyMaterial: Data, pin: String, salt: Data) async throws -> String {
        let pinKeys = try await deriveKeys(pin: pin, salt: salt)
        return try EncString.encrypt(data: keyMaterial, keys: pinKeys).toString()
    }

    private func unwrap(_ wrapped: String, pin: String, salt: Data) async throws -> Data {
        let pinKeys = try await deriveKeys(pin: pin, salt: salt)
        return try EncString(string: wrapped).decrypt(keys: pinKeys)
    }

    private func deriveKeys(pin: String, salt: Data) async throws -> CryptoKeys {
        try await crypto.derivePinKeys(
            pin:        pin,
            salt:       salt,
            iterations: Self.derivationRounds
        )
    }

    /// Reads the failure count, treating a missing or unreadable value as zero.
    ///
    /// Zero rather than the maximum: a counter that cannot be read is not evidence of attempts, and
    /// treating it as such would lock a user out over a Keychain hiccup.
    private func readAttempts(_ userId: String) throws -> Int {
        guard let data = try? keychain.read(key: Self.attemptsKey(userId)),
              let text = String(data: data, encoding: .utf8),
              let value = Int(text) else {
            return 0
        }
        return value
    }

    /// Counts a failure and destroys the material when that was the last permitted attempt.
    ///
    /// Returns the attempts remaining, so the caller does not have to re-derive it. It cannot:
    /// `remove()` has just deleted the count, and re-reading it would report a full allowance again —
    /// which is exactly how an exhausted PIN would come back looking untouched.
    ///
    /// **A counter that cannot be written destroys the PIN instead of carrying on.** This counter *is*
    /// the PIN's entire protection against guessing: a four-digit PIN is about ten thousand candidates,
    /// and the only thing between that number and an attacker is that the app stops after five. Used to
    /// be `try?` here, so a failed write left the stored count where it was, every later attempt
    /// re-incremented the same stale number, and the limit quietly never arrived. Losing a convenience
    /// the user can set again beats keeping a bound they cannot see.
    @discardableResult
    private func recordFailure(_ userId: String) throws -> Int {
        let failures = ((try? readAttempts(userId)) ?? 0) + 1
        guard failures < PinUnlockSettings.maximumAttempts else {
            try remove(userId: userId)
            logger.fault("PIN attempts exhausted; the stored key material has been destroyed")
            return 0
        }
        do {
            try keychain.write(data: Data(String(failures).utf8), key: Self.attemptsKey(userId))
        } catch {
            logger.fault("""
            The PIN attempt counter could not be written (\(error.localizedDescription, privacy: .public)); \
            removing the PIN rather than leaving it without a limit.
            """)
            // Whatever this returns, the caller is told the PIN path is unavailable.
            try? remove(userId: userId)
            throw PinUnlockError.storageUnavailable
        }
        return PinUnlockSettings.maximumAttempts - failures
    }

    private static func makeSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw PinUnlockError.storageUnavailable
        }
        return Data(bytes)
    }

    private static func wrappedKey(_ userId: String) -> String { "bw.macos:\(userId):pinWrappedKeys" }
    private static func saltKey(_ userId: String)    -> String { "bw.macos:\(userId):pinSalt" }
    private static func attemptsKey(_ userId: String) -> String { "bw.macos:\(userId):pinAttempts" }
}
