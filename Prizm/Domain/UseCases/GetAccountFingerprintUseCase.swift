import Foundation

/// The account fingerprint phrase: five words that identify this account's key pair, to be read
/// aloud and compared with what another Bitwarden client shows for the same account.
///
/// It exists to answer one question — *is the key I am talking to the key my other device is
/// talking to?* — without either side ever transmitting the key. The reference implementation is
/// Bitwarden's, and `AccountFingerprintPhrase` documents the vectors that pin this to it.
///
/// **The phrase is not a secret** and is safe to show, copy and speak. That is the point: a
/// fingerprint you have to hide cannot be compared over the phone.
protocol GetAccountFingerprintUseCase {

    /// The phrase for the signed-in account.
    ///
    /// - Returns: `nil` when it cannot be computed — no session, or no public key yet because a
    ///   sync has not completed. `nil` rather than a thrown error because "not yet" is the normal
    ///   state of a window opened before the first sync, and an error would ask the user to fix
    ///   something that is not broken.
    func execute() async throws -> String?
}
