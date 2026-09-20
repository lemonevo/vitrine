import Foundation

// MARK: - PasswordHistoryEntry

/// One previous password of a login item, as maintained by the server.
///
/// **Why this is a separate type from `PreservedCipherFields.passwordHistory`.** That field holds
/// the history in its encrypted wire form (`[JSONValue]`) and is carried through every save
/// untouched. This type is the *decrypted* form, produced on demand by
/// `VaultRepository.passwordHistory(for:)` for exactly two callers: the export, which has to write
/// the previous passwords in plaintext because that is what the interchange format contains, and
/// the detail view, which shows them behind the master-password re-prompt gate.
///
/// **It is a secret.** A previous password is frequently the current password of the account next
/// door. Values of this type must not be cached, logged, or written anywhere except an export file
/// the user explicitly asked for.
nonisolated struct PasswordHistoryEntry: Equatable, Sendable {

    /// The password that was in use before the current one.
    let password: String

    /// When the server recorded this password as replaced.
    ///
    /// `nil` when the entry carries no date or the date could not be parsed. The date is
    /// display metadata only, so an unparseable one is not a reason to hide the password.
    let lastUsedDate: Date?
}
