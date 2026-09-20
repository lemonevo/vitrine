import Foundation

// MARK: - VerifyMasterPasswordUseCaseImpl

/// Asks `AuthRepository` whether a password is the account's master password.
///
/// Deliberately a one-line delegation. The stored KDF parameters, the encrypted user key and the
/// comparison all belong to the repository, which is the layer that already owns the key
/// material; a second copy of any of that here would drift from the first, and the drift would
/// be in the one place where being wrong means granting access.
///
/// The one thing this layer does decide is what not to do: it does not cache the answer. A
/// cached "yes" is a grant that outlives the moment it was given, which is precisely what the
/// gate holds per item and per unlock session instead.
///
/// A class, and not a `nonisolated struct` like `GetPasswordHistoryUseCaseImpl`: `AuthRepository`
/// is a mutable, main-actor repository and is not `Sendable`, so a value type could not hold it
/// without either weakening the protocol or lying about thread safety. `UnlockUseCaseImpl` and
/// `LoginUseCaseImpl` make the same choice for the same reason.
final class VerifyMasterPasswordUseCaseImpl: VerifyMasterPasswordUseCase {

    private let auth: any AuthRepository

    init(auth: any AuthRepository) {
        self.auth = auth
    }

    func execute(_ password: Data) async throws -> Bool {
        try await auth.verifyMasterPassword(password)
    }
}
