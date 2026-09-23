import Foundation

// MARK: - VerifyMasterPasswordUseCase

/// Answers whether a password is this account's master password. Used only by the re-prompt gate.
///
/// **Why a use case for a single method.** The gate is presentation code, and a view model that
/// prompts for a master password should not also have to know which repository holds the KDF
/// parameters and the encrypted user key. This is thin for the same reason
/// `GetPasswordHistoryUseCase` is thin: the view model depends on a domain protocol and cannot
/// reach past it.
///
/// **What it is not.** It is not an unlock, and a `true` answer changes nothing. The vault stays
/// exactly as it was — same keys, same selection, no token refresh, no sync — because the caller
/// only ever asks while the vault is already open (design D7).
protocol VerifyMasterPasswordUseCase: Sendable {

    /// - Parameter password: The candidate master password. The caller owns these bytes and
    ///   zeroes them; the password is `Data` rather than `String` for that reason.
    /// - Returns: `true` when `password` is the master password of the stored account.
    /// - Throws: when the check could not be performed at all — never for a wrong password.
    func execute(_ password: Data) async throws -> Bool
}
