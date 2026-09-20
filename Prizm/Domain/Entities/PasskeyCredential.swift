import Foundation

// MARK: - PasskeyCredential

/// One passkey stored on a login item, in the only form Prizm is allowed to hold it.
///
/// **What is deliberately absent is the most important thing about this type.** A FIDO2 credential
/// carries `keyValue`, and `keyValue` is the **private** key: Bitwarden's authenticator stores
/// `crypto.subtle.exportKey("pkcs8", keyPair.privateKey)` and later imports it to sign an assertion.
/// It is the most sensitive value on the item, and nothing in a read-only listing needs it — so it
/// is not a field here, and no code path in the app decrypts it. Leaving it off the type is what
/// makes that a fact rather than a convention someone has to remember.
///
/// **Why a separate type from `PreservedCipherFields.fido2Credentials`.** That field holds the
/// credentials in their encrypted wire form (`[JSONValue]`) and is carried through every save
/// untouched, so that editing an item cannot delete passkeys the user registered elsewhere. This
/// type is the decrypted, display-only form, produced on demand.
///
/// These values are not secrets in the way a password is — a relying party id and a user name are
/// what a website already knows — but they are vault contents, so they are decrypted when the
/// section is shown and not retained (see the repository method that produces them).
nonisolated struct PasskeyCredential: Equatable, Sendable, Identifiable {

    /// The relying party the credential is registered with — the site it signs in to.
    let rpId: String

    /// The relying party's human-readable name, when the credential carries one.
    let rpName: String?

    /// The user name shown at registration time, when present.
    let userName: String?

    /// The display name shown at registration time, when present.
    let userDisplayName: String?

    /// When the credential was created.
    ///
    /// `nil` when the entry carries no date or the date could not be parsed. The date is the one
    /// field that is **not** an EncString on the wire, so an unparseable one means the server or
    /// client wrote something unexpected — still not a reason to drop the whole credential.
    let creationDate: Date?

    var id: String { rpId + "|" + (userName ?? "") + "|" + String(describing: creationDate) }
}
