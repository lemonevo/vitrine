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
/// **What is deliberately NOT done.** Passkey private keys (`fido2Credentials`) and the per-item
/// key (`cipherKey`) are never decrypted: no screen displays them, and decrypting secrets you do
/// not show only widens the attack surface (Constitution §III).
///
/// **The one exception, and it was added later.** `passwordHistory` *is* decrypted — on demand,
/// never cached, never logged — and the only entry point is `GetPasswordHistoryUseCase`, which
/// reads it through `VaultRepository.passwordHistory(for:)`. Two features need it: the export,
/// because the Bitwarden interchange format carries previous passwords in plaintext, and the detail
/// view's password-history section. The original comment here claimed nothing in this type is ever
/// decrypted — that is no longer true, and leaving the sentence in place would make the file lie
/// about itself (design D10).
///
/// **Reading it is one thing, showing it is another.** The section is collapsed by default and
/// expands into masked values; unmasking one requires the master-password re-prompt gate, which
/// lands in wave C along with the `reprompt` model behind it. A previous password is frequently the
/// current password of the account next door, so displaying one is held to the same standard as
/// displaying a re-prompted item's current password.
///
/// **The key is the item's own.** `cipherKey` when the cipher carries one, otherwise the vault or
/// organisation key — the same resolution `CipherMapper` performs for the current password. A
/// history entry has to decrypt with the same key its item's current password does (design D10).
/// `fido2Credentials` and `cipherKey` themselves remain never-decrypted.
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

    /// `login.fido2Credentials[]` — passkeys stored by Bitwarden's browser extension or mobile app.
    ///
    /// Preserved untouched on every save, which is the part that matters most: a full PUT that
    /// omitted them deleted passkeys the user registered elsewhere.
    ///
    /// **No longer opaque, but read only in part.** `VaultRepositoryImpl.passkeys(for:)` decrypts the
    /// display fields on demand for the read-only listing. It does **not** decrypt `keyValue`, which
    /// is the credential's private key — see `PasskeyCredential`. This comment said "never read"
    /// until that listing existed, and a comment that understates what the code does is the one kind
    /// someone acts on.
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
    /// Stored TOTP seed — the long-lived shared key, either a bare Base32 secret or a full
    /// `otpauth://totp/…` URI.
    ///
    /// **This value is never displayed and never copied.** The detail view shows a code *derived*
    /// from it (`TOTPCodeView`), and the copy commands put that derived code on the clipboard.
    /// Anyone who reads this value can generate valid codes forever, so it stays inside the
    /// generator. `Item ▸ Copy Code` used to copy it — see `FEATURE-GAP-ANALYSIS.md` §2.1.
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
