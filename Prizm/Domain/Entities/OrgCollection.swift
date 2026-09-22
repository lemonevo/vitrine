import Foundation

// MARK: - PreservedCollectionFields

/// The parts of a collection this build reads but does not model, carried so that editing a
/// collection cannot delete them.
///
/// **The mechanism, stated once here rather than rediscovered per field.** Vaultwarden stores the
/// collection object verbatim, so anything missing from a rename body is gone from the collection —
/// the same property documented for ciphers at `RawCipher.swift:123-125`. Before this existed,
/// `renameCollection` sent `groups: []` and `users: []` literally, which meant **renaming a shared
/// collection revoked everybody's access to it**.
///
/// **Why the permission arrays are opaque.** Their shape has already moved between server versions
/// (`readOnly`/`hidePasswords` first, `manage` added later) and may move again. A model would have to
/// be right about every version; round-tripping `JSONValue` has to be right about none of them. This
/// is the same choice `PreservedCipherFields.fido2Credentials` makes, for the same reason.
nonisolated struct PreservedCollectionFields: Sendable, Equatable, Hashable, Codable {

    /// `groups[]` — which groups can reach this collection, and how. Opaque.
    var groups: [JSONValue] = []

    /// `users[]` — which individual members can reach it, and how. Opaque.
    var users: [JSONValue] = []

    /// `externalId` — the identifier a directory-sync deployment keeps collections matched by.
    ///
    /// Not decoded at all before this change, so a rename cleared it as well. Kept as the string it
    /// arrives as rather than parsed: its only use here is to be sent back.
    var externalId: String?

    /// Nothing to send back. Used by tests and by callers constructing a collection that has not been
    /// read from a server — a newly created one, whose empty membership is the truth.
    static let empty = PreservedCollectionFields()
}

/// A Bitwarden collection belonging to an organization.
/// Produced by `SyncRepositoryImpl` from `RawCollection` (name decrypted with the org key).
/// Value type — safe to pass across layers without defensive copying.
///
/// Named `OrgCollection` to avoid shadowing the `Swift.Collection` protocol in files
/// that import this module.
nonisolated struct OrgCollection: Identifiable, Equatable, Hashable {
    let id: String
    let organizationId: String
    let name: String

    /// Membership and the external id, held so a rename can send them back rather than inventing
    /// empty arrays. See `PreservedCollectionFields`.
    ///
    /// On the entity and not only on the wire type, because `VaultRepositoryImpl.renameCollection`
    /// *rebuilds* this value — and rebuilding from three fields is how the local view came to agree
    /// with the server's loss.
    var preserved: PreservedCollectionFields = .empty
}
