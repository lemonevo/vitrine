import Foundation

// MARK: - PinUnlockError

nonisolated enum PinUnlockError: Error, Equatable, LocalizedError {
    /// The PIN was shorter than the minimum the official client requires.
    case pinTooShort(minimum: Int)
    /// No PIN has been set, so there is nothing to unlock with.
    case noPinSet
    /// The PIN was wrong. Carries how many attempts remain, because a limit the user cannot see is a
    /// trap rather than a protection.
    case incorrectPin(remainingAttempts: Int)
    /// The last permitted attempt was wrong. The stored material has been deleted and the caller must
    /// sign the user out.
    case attemptsExhausted
    /// The stored material could not be read back or was in a shape this build cannot use.
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .pinTooShort(let minimum):
            return L("Your PIN must be at least %d characters.", minimum)
        case .noPinSet:
            return L("No PIN has been set for this account.")
        case .incorrectPin(let remaining):
            return remaining == 1
                ? L("Incorrect PIN. One attempt left.")
                : L("Incorrect PIN. %d attempts left.", remaining)
        case .attemptsExhausted:
            return L("Too many incorrect PINs. The PIN has been removed and you have been signed out.")
        case .storageUnavailable:
            return L("The stored PIN could not be read.")
        }
    }
}

// MARK: - PinUnlockService

/// An alternative way into the vault: a short numeric code that unwraps the key material.
///
/// **Why this exists next to biometrics, and how it differs.** The biometric key is *stored* and the
/// Keychain does the gating: `.biometryCurrentSet` refuses to hand the bytes over until Touch ID
/// succeeds. A PIN cannot work that way — no Keychain access control evaluates one — so the gating has
/// to be cryptographic. The same 64 bytes are stored, but **wrapped under a key derived from the PIN**,
/// and unwrapping is the unlock.
///
/// **What is being given up, so that it is not discovered later.** A four-character PIN is roughly ten
/// thousand guesses. The protection therefore does not rest on the derivation being slow; it rests on
/// the wrapped material living in a device-only Keychain item and on the attempt limit below. The
/// official documentation says the same thing in its own words: using a PIN "can weaken the level of
/// encryption that protects your application's local vault database".
///
/// **The account id is a parameter, not a provider.** The alternative is a closure the service calls
/// to discover who is signed in, and that closure would have to be `@Sendable` and synchronous while
/// the Keychain method behind it is main-actor isolated — two requirements that cannot both be met
/// without either an unsafe cast or a hop the sync accessors cannot make. Every caller already knows
/// the account, so it says so.
///
/// **`Data`, not `CryptoKeys`.** `CryptoKeys` is a Data-layer type and this protocol is Domain
/// (Constitution §II); the same reason `VaultKeyService` deals in the raw 64-byte blob.
protocol PinUnlockService: AnyObject {

    /// Whether a PIN is set for `userId`.
    func isSet(userId: String) -> Bool

    /// How many attempts remain before the material is destroyed for `userId`.
    func remainingAttempts(userId: String) -> Int

    /// Derives a key from `pin`, wraps `keyMaterial` (the vault's 64 bytes) with it, and stores the
    /// result together with the salt it was derived against.
    ///
    /// - Throws: `PinUnlockError.pinTooShort`.
    func setPin(_ pin: String, keyMaterial: Data, userId: String) async throws

    /// Derives with the entered PIN and returns the wrapped key material.
    ///
    /// - Throws: `PinUnlockError.incorrectPin` (carrying the remaining attempts) for a wrong PIN, and
    ///   `PinUnlockError.attemptsExhausted` when that was the last one — in which case the stored
    ///   material has already been destroyed and the caller is responsible for signing the user out.
    func unlock(with pin: String, userId: String) async throws -> Data

    /// Removes the wrapped material, its salt and the attempt count for `userId`.
    ///
    /// - Throws: `PinUnlockError.storageUnavailable` if any of the three items could not be deleted.
    ///   This is not a housekeeping detail: the wrapped blob is the thing an attacker brute-forces, and
    ///   a caller that reports "the PIN is off" while it survives would both mislead the user and
    ///   remove their reason to retry. Deleting an item that is not there is not an error.
    func remove(userId: String) throws
}
