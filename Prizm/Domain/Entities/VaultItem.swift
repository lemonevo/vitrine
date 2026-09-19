import Foundation

// MARK: - PreservedCipherFields

/// Wire-format cipher fields that Prizm does not interpret, carried so that saving an item
/// cannot delete data another Bitwarden client wrote.
///
/// **Why this exists.** `PUT /api/ciphers/{id}` replaces the *entire* cipher. Vaultwarden's
/// `update_cipher_from_data` (`src/api/core/ciphers.rs`) assigns `key`, `password_history` and
/// `archived_date` unconditionally and stores the `login` object verbatim, so every field that is
/// absent from the request body is erased server-side. Prizm has no UI for passkeys, password
/// history or per-item keys — without this type, editing an item's notes would silently delete
/// all three, and toggling a favourite would do the same.
///
/// **What is deliberately NOT done.** Nothing here is ever decrypted. Passkey private keys and
/// historical passwords stay in their EncString form because no screen displays them, and
/// decrypting secrets you do not show only widens the attack surface (Constitution §III).
///
/// Reference: Bitwarden server `CipherModel` / `CipherLoginModel`, Vaultwarden `CipherData`.
nonisolated struct PreservedCipherFields: Sendable, Equatable, Hashable {

    /// `passwordHistory[]` — the server-maintained list of previous passwords (EncStrings).
    /// Cleared by the server when absent from the request body.
    var passwordHistory: [JSONValue] = []

    /// `archivedDate` — ISO-8601 timestamp set by the official clients' Archive feature.
    /// When absent the server runs its **un-archive** path, so an edit in Prizm would silently
    /// take an archived item out of the archive.
    var archivedDate: String?

    /// `key` — the cipher's per-item key, wrapped as an EncString.
    ///
    /// When present, the cipher's fields *and its attachments* are encrypted with this key rather
    /// than with the vault/org key. It must therefore be used for re-encryption and returned
    /// unchanged; sending `null` makes the server drop it, which orphans every attachment whose
    /// key was wrapped with it.
    var cipherKey: String?

    /// `login.fido2Credentials[]` — passkeys stored by Bitwarden's browser extension or mobile
    /// app. Opaque to Prizm: preserved, never read.
    var fido2Credentials: [JSONValue] = []

    /// `login.passwordRevisionDate` — when the login's password was last changed.
    var passwordRevisionDate: String?

    /// `login.autofillOnPageLoad` — per-item override of the global autofill setting.
    var autofillOnPageLoad: Bool?

    /// Nothing to send back. Used by tests and by `RawCipher` construction to decide whether a
    /// field can be omitted rather than sent as an empty value.
    static let empty = PreservedCipherFields()

    var isEmpty: Bool {
        passwordHistory.isEmpty
            && archivedDate == nil
            && cipherKey == nil
            && fido2Credentials.isEmpty
            && passwordRevisionDate == nil
            && autofillOnPageLoad == nil
    }
}

// MARK: - VaultItem

/// A fully-decrypted vault entry. Produced by `CipherMapper` from a `RawCipher`.
/// Value type — safe to pass across layers without defensive copying.
nonisolated struct VaultItem: Identifiable, Equatable, Hashable {
    let id: String
    let folderId: String?
    let name: String
    let isFavorite: Bool
    let isDeleted: Bool
    let creationDate: Date
    let revisionDate: Date
    let content: ItemContent
    /// Master-password re-prompt setting mirrored from the Bitwarden wire format.
    /// 0 = disabled (default), 1 = require master password before revealing fields.
    /// Stored here so `CipherMapper.toRawCipher` can round-trip it unchanged on PUT,
    /// preventing silent loss of re-prompt protection during edits.
    let reprompt: Int
    /// File attachments belonging to this vault item.
    /// Empty (`[]`) when the server returns no attachments or an explicit `null`.
    let attachments: [Attachment]
    /// Non-nil when this item belongs to a Bitwarden organization.
    /// Nil for personal vault items.
    let organizationId: String?
    /// The collections this item is assigned to within its organization.
    /// Empty (`[]`) for personal items and org items not assigned to any collection.
    let collectionIds: [String]
    /// Wire fields Prizm does not interpret. Populated by `CipherMapper.map` and sent back
    /// unchanged by `CipherMapper.toRawCipher`, so a save never deletes a passkey, password
    /// history, the per-item key or the archived flag. See `PreservedCipherFields`.
    let preserved: PreservedCipherFields

    /// Custom memberwise init with `reprompt` defaulted to 0, `attachments` defaulted to `[]`,
    /// `organizationId` defaulted to nil, and `collectionIds` defaulted to `[]` so existing
    /// call sites that pre-date these fields do not need to be updated.
    init(
        id: String, name: String, isFavorite: Bool, isDeleted: Bool,
        creationDate: Date, revisionDate: Date, content: ItemContent,
        reprompt: Int = 0,
        attachments: [Attachment] = [],
        folderId: String? = nil,
        organizationId: String? = nil,
        collectionIds: [String] = [],
        preserved: PreservedCipherFields = .empty
    ) {
        self.id = id
        self.folderId = folderId
        self.name = name
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.creationDate = creationDate
        self.revisionDate = revisionDate
        self.content = content
        self.reprompt = reprompt
        self.attachments = attachments
        self.organizationId = organizationId
        self.collectionIds = collectionIds
        self.preserved = preserved
    }
}

// MARK: - Field-wise copy

// `nonisolated` because the Data layer patches the cached vault from a background actor; the
// project builds with `-default-isolation MainActor`, which an extension does not inherit from
// the type it extends.
nonisolated extension VaultItem {

    /// Returns a copy with the given fields replaced. Every parameter defaults to `nil`, meaning
    /// "keep the current value".
    ///
    /// **Why this exists.** `VaultItem` has twelve stored properties, and the in-memory cache is
    /// patched in seven places that each change one or two of them. Spelling the memberwise
    /// initialiser out at each site is how `organizationId` and `collectionIds` were silently
    /// dropped when a folder was deleted or an item moved — see `openspec/specs/org-vault-items`.
    /// With this helper a call site states only what it means to change, and a field added later
    /// cannot be lost by an older call site.
    ///
    /// - Parameters:
    ///   - folderId: pass `.some(nil)` to remove the item from its folder; omit to keep it.
    ///     The nested optional exists because "clear the folder" and "leave it alone" are both
    ///     meaningful requests and `String?` cannot express both.
    ///   - organizationId: same convention — `.some(nil)` clears org membership.
    /// - Returns: A copy of the receiver with the supplied fields replaced.
    func with(
        name: String? = nil,
        isFavorite: Bool? = nil,
        isDeleted: Bool? = nil,
        revisionDate: Date? = nil,
        content: ItemContent? = nil,
        reprompt: Int? = nil,
        attachments: [Attachment]? = nil,
        folderId: String?? = nil,
        organizationId: String?? = nil,
        collectionIds: [String]? = nil,
        preserved: PreservedCipherFields? = nil
    ) -> VaultItem {
        VaultItem(
            id:             id,
            name:           name           ?? self.name,
            isFavorite:     isFavorite     ?? self.isFavorite,
            isDeleted:      isDeleted      ?? self.isDeleted,
            creationDate:   creationDate,
            revisionDate:   revisionDate   ?? self.revisionDate,
            content:        content        ?? self.content,
            reprompt:       reprompt       ?? self.reprompt,
            attachments:    attachments    ?? self.attachments,
            folderId:       folderId       ?? self.folderId,
            organizationId: organizationId ?? self.organizationId,
            collectionIds:  collectionIds  ?? self.collectionIds,
            preserved:      preserved      ?? self.preserved
        )
    }
}

// MARK: - Item content discriminator

/// Discriminated union of all five Bitwarden vault item types.
nonisolated enum ItemContent: Equatable, Hashable {
    case login(LoginContent)
    case secureNote(SecureNoteContent)
    case card(CardContent)
    case identity(IdentityContent)
    case sshKey(SSHKeyContent)
}

// MARK: - Login

nonisolated struct LoginContent: Equatable, Hashable {
    let username: String?
    let password: String?
    let uris: [LoginURI]
    /// Stored TOTP seed. Present on some items but never displayed in v1 (FR-038).
    let totp: String?
    let notes: String?
    let customFields: [CustomField]
}

nonisolated struct LoginURI: Equatable, Hashable {
    let uri: String
    let matchType: URIMatchType?
}

/// URI-matching strategy used when auto-filling (stored per URI, not used in v1 display).
nonisolated enum URIMatchType: Int, Equatable, Hashable {
    case domain = 0
    case host = 1
    case startsWith = 2
    case exact = 3
    case regularExpression = 4
    case never = 5
}

// MARK: - Card

nonisolated struct CardContent: Equatable, Hashable {
    let cardholderName: String?
    let brand: String?
    let number: String?
    let expMonth: String?
    let expYear: String?
    let code: String?
    let notes: String?
    let customFields: [CustomField]
}

// MARK: - Identity

nonisolated struct IdentityContent: Equatable, Hashable {
    let title: String?
    let firstName: String?
    let middleName: String?
    let lastName: String?
    let address1: String?
    let address2: String?
    let address3: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let company: String?
    let email: String?
    let phone: String?
    let ssn: String?
    let username: String?
    let passportNumber: String?
    let licenseNumber: String?
    let notes: String?
    let customFields: [CustomField]
}

// MARK: - Secure Note

nonisolated struct SecureNoteContent: Equatable, Hashable {
    let notes: String?
    let customFields: [CustomField]
}

// MARK: - SSH Key

nonisolated struct SSHKeyContent: Equatable, Hashable {
    let privateKey: String?
    let publicKey: String?
    let keyFingerprint: String?
    let notes: String?
    let customFields: [CustomField]
}
