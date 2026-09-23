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

    /// The `revisionDate` string this item was last synced with, kept **verbatim**.
    ///
    /// Not here because Vitrine fails to interpret it — `VaultItem.revisionDate` is the parsed
    /// `Date` the interface displays. It is here because the only correct value to send as
    /// `lastKnownRevisionDate` is the server's own string: reformatting a `Date` would send a
    /// reconstruction, and Vaultwarden compares the two as instants to decide whether this client
    /// is editing a stale copy. Sending nothing disables that check, so a save made without an
    /// intervening sync overwrites whatever another client wrote.
    var revisionDate: String?

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
            && revisionDate == nil
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

/// URI-matching strategy for one website entry.
///
/// **The integers are Bitwarden's `UriMatchStrategySetting`, and they are the contract.** This enum
/// used to be `Int`-backed starting at `domain = 0`, which is one step short of the wire: Bitwarden
/// reserves 0 for "default" and puts "base domain" at 1. Every choice above the first was therefore
/// written as its neighbour — picking "Never" sent 5, which the wire reads as *regular expression* —
/// and 6 ("Never") had no case at all, so a value set in the web vault decoded to nothing and the next
/// save erased it. Because a favourite toggle goes through the same full `PUT`, one click on a star was
/// enough to do it.
///
/// Held as an explicit mapping rather than a raw-value enum, so that a number this build does not know
/// is carried through unchanged instead of being normalised away. `SecureNoteSubtype` learned the same
/// lesson the hard way; see its comment for why a mapping that is wrong in both directions is worse
/// than one that fails loudly.
///
/// `nil` on `LoginURI.matchType` means the user chose nothing, which the wire writes as `null`;
/// `.defaultMatch` is an explicit 0. Both mean "the client decides", and both survive as themselves.
nonisolated enum URIMatchType: Equatable, Hashable {
    case defaultMatch
    case baseDomain
    case host
    case startsWith
    case exact
    case regularExpression
    case never
    /// A strategy this build does not know. Carried, never normalised.
    case unknown(Int)

    init(rawValue: Int) {
        switch rawValue {
        case 0:  self = .defaultMatch
        case 1:  self = .baseDomain
        case 2:  self = .host
        case 3:  self = .startsWith
        case 4:  self = .exact
        case 5:  self = .regularExpression
        case 6:  self = .never
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: Int {
        switch self {
        case .defaultMatch:      return 0
        case .baseDomain:        return 1
        case .host:              return 2
        case .startsWith:        return 3
        case .exact:             return 4
        case .regularExpression: return 5
        case .never:             return 6
        case .unknown(let raw):  return raw
        }
    }

    /// What the picker offers, in Bitwarden's order. `.unknown` is absent on purpose: it is what a
    /// stored value becomes when this build cannot name it, not a thing to choose.
    static let selectable: [URIMatchType] = [
        .baseDomain, .host, .startsWith, .exact, .regularExpression, .never
    ]
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

/// Bitwarden's secure-note subtype.
///
/// **Why this is not a closed enum.** A server newer than this build can serve a subtype the enum has
/// never heard of, and a closed enum has only two ways to respond: throw, or fall back to `.generic`.
/// The second is what a `switch` reaches for, and it is a data loss — a passport note becomes a
/// generic one the next time it is saved, because the write path then sends `0`.
///
/// `.unknown` makes "not recognised" a value that can be *held*, so it survives a round trip
/// whichever build opens the item. The UI shows the raw number for it, which is honest about what
/// this build knows.
nonisolated enum SecureNoteSubtype: Equatable, Hashable {
    case generic
    case bankAccount
    case driversLicense
    case passport
    case medicalRecord
    case membership
    case socialSecurity
    case wifi
    case softwareLicense
    /// A subtype this build does not know. Carried, never normalised.
    case unknown(Int)

    /// Bitwarden's `SecureNoteType` integers. Asserted in the tests per case, because a mapping that
    /// is wrong in the same way in both directions would round-trip perfectly while mislabelling the
    /// item — and a wrong label is recoverable, whereas a lost value is not.
    init(rawValue: Int) {
        switch rawValue {
        case 0:  self = .generic
        case 1:  self = .bankAccount
        case 2:  self = .driversLicense
        case 3:  self = .passport
        case 4:  self = .medicalRecord
        case 5:  self = .membership
        case 6:  self = .socialSecurity
        case 7:  self = .wifi
        case 8:  self = .softwareLicense
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: Int {
        switch self {
        case .generic:         return 0
        case .bankAccount:     return 1
        case .driversLicense:  return 2
        case .passport:        return 3
        case .medicalRecord:   return 4
        case .membership:      return 5
        case .socialSecurity:  return 6
        case .wifi:            return 7
        case .softwareLicense: return 8
        case .unknown(let raw): return raw
        }
    }

    /// The subtypes offered by the picker, in Bitwarden's order. `.unknown` is deliberately absent:
    /// it is what a stored value becomes when this build cannot name it, not something to choose.
    static let selectable: [SecureNoteSubtype] = [
        .generic, .bankAccount, .driversLicense, .passport, .medicalRecord,
        .membership, .socialSecurity, .wifi, .softwareLicense
    ]
}

nonisolated struct SecureNoteContent: Equatable, Hashable {
    let notes: String?
    let customFields: [CustomField]
    /// Defaults to `.generic`, which is also what the server sends for notes that predate the field.
    let subtype: SecureNoteSubtype

    init(notes: String?, customFields: [CustomField], subtype: SecureNoteSubtype = .generic) {
        self.notes        = notes
        self.customFields = customFields
        self.subtype      = subtype
    }
}

// MARK: - SSH Key

nonisolated struct SSHKeyContent: Equatable, Hashable {
    let privateKey: String?
    let publicKey: String?
    let keyFingerprint: String?
    let notes: String?
    let customFields: [CustomField]
}
