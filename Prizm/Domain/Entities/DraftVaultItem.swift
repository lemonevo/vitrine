import Foundation

// MARK: - DraftLoginURI

/// Mutable mirror of `LoginURI` used exclusively within the edit flow.
///
/// Why mutable mirror instead of mutating `LoginURI` directly: `LoginURI` is a value type with
/// `let` fields, which prevents accidental mutation in read-only views. By introducing a separate
/// `DraftLoginURI` we confine mutability to the edit sheet and keep the read path immutable.
nonisolated struct DraftLoginURI: Equatable, Identifiable {
    let id = UUID()
    var uri: String
    var matchType: URIMatchType?

    init(uri: String = "", matchType: URIMatchType? = nil) {
        self.uri = uri
        self.matchType = matchType
    }

    init(_ source: LoginURI) {
        self.uri = source.uri
        self.matchType = source.matchType
    }

    // Exclude `id` from equality — two drafts with the same content are equal regardless of identity.
    static func == (lhs: DraftLoginURI, rhs: DraftLoginURI) -> Bool {
        lhs.uri == rhs.uri && lhs.matchType == rhs.matchType
    }
}

// MARK: - DraftCustomField

/// Mutable mirror of `CustomField` used exclusively within the edit flow.
///
/// Every field is mutable, because the edit sheet supports the full lifecycle: adding a field,
/// renaming it, changing its type, reordering it and deleting it.
nonisolated struct DraftCustomField: Equatable, Identifiable {

    /// Stable row identity, independent of position.
    ///
    /// **Why this is not just `ForEach(indices)`.** The list can be reordered and have rows removed.
    /// Identifying rows by index makes SwiftUI reuse the view state of the row that used to occupy
    /// that index — so deleting row 1 would hand row 2's `@State` (such as whether a hidden value is
    /// revealed) to the wrong field. A stable id keeps each row's transient state with its field.
    let id: UUID

    var name: String
    var value: String?
    var type: CustomFieldType
    /// Non-nil only when `type == .linked`.
    var linkedId: LinkedFieldId?

    init(name: String = "", value: String? = nil,
         type: CustomFieldType = .text, linkedId: LinkedFieldId? = nil) {
        self.id = UUID()
        self.name = name
        self.value = value
        self.type = type
        self.linkedId = linkedId
    }

    init(_ source: CustomField) {
        self.id = UUID()
        self.name = source.name
        self.value = source.value
        self.type = source.type
        self.linkedId = source.linkedId
    }

    /// Whether the name is blank once whitespace is trimmed.
    ///
    /// The wire format requires a field name and the mapper skips unnamed fields, so such a field
    /// would be silently discarded on save. The edit sheet blocks saving instead.
    var hasBlankName: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Excludes `id` — two drafts with the same content are equal regardless of identity.
    static func == (lhs: DraftCustomField, rhs: DraftCustomField) -> Bool {
        lhs.name == rhs.name
            && lhs.value == rhs.value
            && lhs.type == rhs.type
            && lhs.linkedId == rhs.linkedId
    }
}

// MARK: - Draft content types

/// Mutable mirror of `LoginContent` used exclusively within the edit flow.
///
/// See `DraftVaultItem` for the rationale behind the mutable mirror pattern.
nonisolated struct DraftLoginContent: Equatable {
    var username: String?
    var password: String?
    var uris: [DraftLoginURI]
    /// The TOTP seed — `var` because the edit form writes it, which is the point of the mirror.
    ///
    /// It is the one field here whose value is both a secret and something the user has to be able
    /// to *enter*: a seed can only be obtained from the issuing service's own "can't scan the QR
    /// code" page, so an item imported without one could never be finished inside Prizm. Leaving
    /// it `let` did not protect anything — the value was already decrypted and on screen — it just
    /// made the one place a seed can be recorded unreachable.
    var totp: String?
    var notes: String?
    /// Custom fields are fully editable: values, adding, deleting and reordering all happen in
    /// `CustomFieldsEditSection`. This line used to say the last three were "out of scope", which was
    /// written before they were built and would now send a reader looking for a limitation that is
    /// not there.
    var customFields: [DraftCustomField]

    init(_ source: LoginContent) {
        self.username = source.username
        self.password = source.password
        self.uris = source.uris.map(DraftLoginURI.init)
        self.totp = source.totp
        self.notes = source.notes
        self.customFields = source.customFields.map(DraftCustomField.init)
    }
}

/// Mutable mirror of `CardContent` used exclusively within the edit flow.
///
/// See `DraftVaultItem` for the rationale behind the mutable mirror pattern.
nonisolated struct DraftCardContent: Equatable {
    var cardholderName: String?
    var brand: String?
    var number: String?
    var expMonth: String?
    var expYear: String?
    var code: String?
    var notes: String?
    var customFields: [DraftCustomField]

    init(_ source: CardContent) {
        self.cardholderName = source.cardholderName
        self.brand = source.brand
        self.number = source.number
        self.expMonth = source.expMonth
        self.expYear = source.expYear
        self.code = source.code
        self.notes = source.notes
        self.customFields = source.customFields.map(DraftCustomField.init)
    }
}

/// Mutable mirror of `IdentityContent` used exclusively within the edit flow.
///
/// See `DraftVaultItem` for the rationale behind the mutable mirror pattern.
nonisolated struct DraftIdentityContent: Equatable {
    var title: String?
    var firstName: String?
    var middleName: String?
    var lastName: String?
    var address1: String?
    var address2: String?
    var address3: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String?
    var company: String?
    var email: String?
    var phone: String?
    var ssn: String?
    var username: String?
    var passportNumber: String?
    var licenseNumber: String?
    var notes: String?
    var customFields: [DraftCustomField]

    init(_ source: IdentityContent) {
        self.title = source.title
        self.firstName = source.firstName
        self.middleName = source.middleName
        self.lastName = source.lastName
        self.address1 = source.address1
        self.address2 = source.address2
        self.address3 = source.address3
        self.city = source.city
        self.state = source.state
        self.postalCode = source.postalCode
        self.country = source.country
        self.company = source.company
        self.email = source.email
        self.phone = source.phone
        self.ssn = source.ssn
        self.username = source.username
        self.passportNumber = source.passportNumber
        self.licenseNumber = source.licenseNumber
        self.notes = source.notes
        self.customFields = source.customFields.map(DraftCustomField.init)
    }
}

/// Mutable mirror of `SecureNoteContent` used exclusively within the edit flow.
///
/// See `DraftVaultItem` for the rationale behind the mutable mirror pattern.
nonisolated struct DraftSecureNoteContent: Equatable {
    var notes: String?
    var customFields: [DraftCustomField]
    /// Mutable, so it can be chosen in the form. It is round-tripped to the server like every other
    /// field — the previous hardcoded write of `0` reset every note to Generic on save.
    var subtype: SecureNoteSubtype

    init(_ source: SecureNoteContent) {
        self.notes = source.notes
        self.customFields = source.customFields.map(DraftCustomField.init)
        self.subtype = source.subtype
    }
}

/// Mutable mirror of `SSHKeyContent` used exclusively within the edit flow.
///
/// `keyFingerprint` is read-only in the form because it is *derived* from the key, not because it is
/// unsent: it is round-tripped to the server like every other field, and the server stores it as an
/// `EncString` it cannot read. Showing it as editable would invite a value that disagrees with the
/// key.
nonisolated struct DraftSSHKeyContent: Equatable {
    var privateKey: String?
    var publicKey: String?
    /// Read-only display value, carried through so a save does not erase it. Derived by whichever
    /// client created the item; never recomputed here, so replacing the key leaves it describing the
    /// previous one.
    let keyFingerprint: String?
    var notes: String?
    var customFields: [DraftCustomField]

    init(_ source: SSHKeyContent) {
        self.privateKey = source.privateKey
        self.publicKey = source.publicKey
        self.keyFingerprint = source.keyFingerprint
        self.notes = source.notes
        self.customFields = source.customFields.map(DraftCustomField.init)
    }
}

// MARK: - DraftItemContent

/// Mutable discriminated union mirroring `ItemContent`, used exclusively within the edit flow.
///
/// Mirrors `ItemContent` case-for-case so `ItemEditView` can switch on content type and
/// project a `Binding<DraftLoginContent>` (etc.) for the per-type edit form without casting.
/// The enum is mutable by carrying mutable associated values (`var` structs), which allows
/// SwiftUI to propagate changes back through `@Binding` chains to the ViewModel's `draft`.
///
/// See `DraftVaultItem` for the rationale behind the mutable mirror pattern.
nonisolated enum DraftItemContent: Equatable {
    case login(DraftLoginContent)
    case secureNote(DraftSecureNoteContent)
    case card(DraftCardContent)
    case identity(DraftIdentityContent)
    case sshKey(DraftSSHKeyContent)
}

// MARK: - DraftVaultItem

/// Mutable mirror of `VaultItem` used exclusively within the edit flow.
///
/// Why a mutable mirror instead of mutating `VaultItem`:
/// `VaultItem` has `let` fields to prevent accidental mutation anywhere in the app. Widening
/// mutation to `var` would require `@State` copies in every read-only detail view and remove
/// the safety guarantee that domain entities are never modified outside the write path.
/// `DraftVaultItem` confines that mutability to the edit sheet where it is intentional.
///
/// Lifecycle:
/// 1. Created via `DraftVaultItem.init(_ item: VaultItem)` when the edit sheet opens.
/// 2. Mutated as the user edits fields in the `ItemEditViewModel`.
/// 3. Passed to `EditVaultItemUseCase.execute(draft:)` on save.
/// 4. Cleared from memory when the sheet is dismissed.
nonisolated struct DraftVaultItem: Equatable {
    /// Immutable — item identity cannot change during an edit.
    let id: String
    var folderId: String?
    var name: String
    var isFavorite: Bool
    /// Deletion state is not editable in v1.
    let isDeleted: Bool
    /// Dates are server-managed; not editable.
    let creationDate: Date
    let revisionDate: Date
    var content: DraftItemContent
    /// Master-password re-prompt setting, as the wire integer (0 = off, 1 = on).
    ///
    /// **Mutable as of wave C (design D13).** Nearly every other property here is `let` on
    /// purpose — identity, deletion state, dates and preserved wire fields are not editable —
    /// so a `var` in the middle of them needs saying out loud: the edit form now carries a
    /// toggle for this setting and the value travels to the server on save.
    ///
    /// Still an `Int` rather than a `Bool` because `CipherMapper` and the server agree on the
    /// integer; the form binds to a Bool derived from it rather than changing the wire shape.
    var reprompt: Int
    /// Non-nil when this draft is being created/edited within a Bitwarden organization.
    var organizationId: String?
    /// The collections this item is assigned to within its organization.
    /// Empty for personal items and org items not yet assigned to a collection.
    var collectionIds: [String]
    /// Wire fields Prizm does not interpret, carried through the edit unchanged.
    ///
    /// Not user-editable and never displayed — its only job is to reach
    /// `CipherMapper.toRawCipher` so the outgoing `PUT` body still contains the passkeys,
    /// password history and per-item key the item arrived with. See `PreservedCipherFields`.
    let preserved: PreservedCipherFields

    /// The login password this draft started from, kept only so that a **change** can be detected
    /// and the value being replaced recorded in `passwordHistory`.
    ///
    /// `nil` for a new item, and for every non-login type. This is a second copy of a secret that is
    /// already in `content.password`, and it is held only while the sheet is open — the draft is
    /// cleared when the sheet closes. The alternative,
    /// comparing the newly encrypted password against the stored EncString, cannot work: encryption
    /// draws a fresh IV each time, so the same plaintext produces different ciphertext.
    let replacedPassword: String?

    /// Creates a blank draft for a new item of the given type.
    static func blank(type: ItemType) -> DraftVaultItem {
        let now = Date()
        let content: DraftItemContent = switch type {
        case .login:      .login(DraftLoginContent(LoginContent(username: nil, password: nil, uris: [LoginURI(uri: "", matchType: nil)], totp: nil, notes: nil, customFields: [])))
        case .card:       .card(DraftCardContent(CardContent(cardholderName: nil, brand: nil, number: nil, expMonth: nil, expYear: nil, code: nil, notes: nil, customFields: [])))
        case .identity:   .identity(DraftIdentityContent(IdentityContent(title: nil, firstName: nil, middleName: nil, lastName: nil, address1: nil, address2: nil, address3: nil, city: nil, state: nil, postalCode: nil, country: nil, company: nil, email: nil, phone: nil, ssn: nil, username: nil, passportNumber: nil, licenseNumber: nil, notes: nil, customFields: [])))
        case .secureNote: .secureNote(DraftSecureNoteContent(SecureNoteContent(notes: nil, customFields: [])))
        case .sshKey:     .sshKey(DraftSSHKeyContent(SSHKeyContent(privateKey: nil, publicKey: nil, keyFingerprint: nil, notes: nil, customFields: [])))
        }
        return DraftVaultItem(
            id: UUID().uuidString,
            folderId: nil,
            name: "",
            isFavorite: false,
            isDeleted: false,
            creationDate: now,
            revisionDate: now,
            content: content,
            reprompt: 0
        )
    }

    /// Memberwise initialiser for programmatic construction (blank drafts, tests).
    init(id: String, folderId: String? = nil, name: String, isFavorite: Bool, isDeleted: Bool,
         creationDate: Date, revisionDate: Date, content: DraftItemContent, reprompt: Int,
         organizationId: String? = nil, collectionIds: [String] = [],
         preserved: PreservedCipherFields = .empty,
         replacedPassword: String? = nil) {
        self.id = id
        self.folderId = folderId
        self.name = name
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.creationDate = creationDate
        self.revisionDate = revisionDate
        self.content = content
        self.reprompt = reprompt
        self.organizationId = organizationId
        self.collectionIds = collectionIds
        self.preserved = preserved
        self.replacedPassword = replacedPassword
    }

    /// Converts an immutable `VaultItem` into a mutable draft ready for editing.
    init(_ item: VaultItem) {
        self.id = item.id
        self.folderId = item.folderId
        self.name = item.name
        self.isFavorite = item.isFavorite
        self.isDeleted = item.isDeleted
        self.creationDate = item.creationDate
        self.revisionDate = item.revisionDate
        self.reprompt = item.reprompt
        self.organizationId = item.organizationId
        self.collectionIds = item.collectionIds
        self.preserved = item.preserved
        if case .login(let login) = item.content {
            self.replacedPassword = login.password
        } else {
            self.replacedPassword = nil
        }
        self.content = {
            switch item.content {
            case .login(let c):      return .login(DraftLoginContent(c))
            case .secureNote(let c): return .secureNote(DraftSecureNoteContent(c))
            case .card(let c):       return .card(DraftCardContent(c))
            case .identity(let c):   return .identity(DraftIdentityContent(c))
            case .sshKey(let c):     return .sshKey(DraftSSHKeyContent(c))
            }
        }()
    }

    // MARK: - Duplicate

    /// Builds a draft that creates a copy of `item`.
    ///
    /// **What is copied.** Everything the user can see: name (with a "(copy)" suffix), all
    /// type-specific content, notes, custom fields, URIs, folder assignment, organisation and
    /// collection membership, and the re-prompt flag.
    ///
    /// **What is deliberately not copied**, each for a reason that would be a defect if reversed:
    ///
    /// - `preserved` as a whole. `cipherKey` is what the *original's* attachments are wrapped with —
    ///   a copy has no attachments, and sharing the key would leave the original's attachments
    ///   wrapped with a key two ciphers now claim. `fido2Credentials` is a credential for one
    ///   account; two ciphers holding the same passkey is a state no Bitwarden client expects, and
    ///   Prizm offers no UI to inspect or remove the copy. `passwordHistory` belongs to the original
    ///   cipher, and `archivedDate` would make a brand-new item arrive archived.
    /// - Attachments, matching the official clients.
    ///
    /// **The favorite flag is reset.** Favorites is a deliberate shortlist; adding to it is the
    /// user's decision rather than a side effect of duplicating.
    ///
    /// The draft is handed to the ordinary `create` path, so a duplicate is encrypted, org-key
    /// resolved and cached exactly like any other new item.
    static func duplicate(of item: VaultItem) -> DraftVaultItem {
        let source = DraftVaultItem(item)
        let now    = Date()
        return DraftVaultItem(
            id:             UUID().uuidString,
            folderId:       source.folderId,
            name:           L("%@ (copy)", source.name),
            isFavorite:     false,
            isDeleted:      false,
            creationDate:   now,
            revisionDate:   now,
            content:        source.content,
            reprompt:       source.reprompt,
            organizationId: source.organizationId,
            collectionIds:  source.collectionIds,
            preserved:      .empty
        )
    }

    // MARK: - Custom field access

    /// Every custom field on the draft, whichever content type it holds.
    ///
    /// The five content types each carry their own `customFields` array, so validation that must
    /// apply to all of them needs one place to look.
    var allCustomFields: [DraftCustomField] {
        switch content {
        case .login(let c):      return c.customFields
        case .card(let c):       return c.customFields
        case .identity(let c):   return c.customFields
        case .secureNote(let c): return c.customFields
        case .sshKey(let c):     return c.customFields
        }
    }

    /// Custom fields that cannot be saved because they have no name.
    var unnamedCustomFields: [DraftCustomField] {
        allCustomFields.filter(\.hasBlankName)
    }
}

// MARK: - VaultItem ← DraftVaultItem

extension VaultItem {
    /// Reconstructs an immutable `VaultItem` from a saved draft.
    ///
    /// Only called after a successful `PUT /ciphers/{id}` response has been decoded into a
    /// server-confirmed `VaultItem` via `CipherMapper`. This path is provided for any
    /// post-save local patching if needed; normally the API response is used directly.
    init(_ draft: DraftVaultItem) {
        self.id = draft.id
        self.folderId = draft.folderId
        self.name = draft.name
        self.isFavorite = draft.isFavorite
        self.isDeleted = draft.isDeleted
        self.creationDate = draft.creationDate
        self.revisionDate = draft.revisionDate
        self.reprompt = draft.reprompt
        self.organizationId = draft.organizationId
        self.collectionIds = draft.collectionIds
        // Carried through unchanged: this reconstruction happens on the way *back* from an edit,
        // so the unmodelled wire fields must survive it or a save would drop them.
        self.preserved = draft.preserved
        // Drafts do not carry attachment state — attachments are managed via
        // AttachmentRepository and written back through the server response, not through
        // the edit draft. Preserve an empty list here; the actual attachments come from
        // the fresh VaultItem returned by PUT /ciphers/{id}.
        self.attachments = []
        self.content = {
            switch draft.content {
            case .login(let c):
                return .login(LoginContent(
                    username: c.username,
                    password: c.password,
                    uris: c.uris.map { LoginURI(uri: $0.uri, matchType: $0.matchType) },
                    totp: c.totp,
                    notes: c.notes,
                    customFields: c.customFields.map {
                        CustomField(name: $0.name, value: $0.value, type: $0.type, linkedId: $0.linkedId)
                    }
                ))
            case .secureNote(let c):
                return .secureNote(SecureNoteContent(
                    notes: c.notes,
                    customFields: c.customFields.map {
                        CustomField(name: $0.name, value: $0.value, type: $0.type, linkedId: $0.linkedId)
                    },
                    subtype: c.subtype
                ))
            case .card(let c):
                return .card(CardContent(
                    cardholderName: c.cardholderName,
                    brand: c.brand,
                    number: c.number,
                    expMonth: c.expMonth,
                    expYear: c.expYear,
                    code: c.code,
                    notes: c.notes,
                    customFields: c.customFields.map {
                        CustomField(name: $0.name, value: $0.value, type: $0.type, linkedId: $0.linkedId)
                    }
                ))
            case .identity(let c):
                return .identity(IdentityContent(
                    title: c.title,
                    firstName: c.firstName,
                    middleName: c.middleName,
                    lastName: c.lastName,
                    address1: c.address1,
                    address2: c.address2,
                    address3: c.address3,
                    city: c.city,
                    state: c.state,
                    postalCode: c.postalCode,
                    country: c.country,
                    company: c.company,
                    email: c.email,
                    phone: c.phone,
                    ssn: c.ssn,
                    username: c.username,
                    passportNumber: c.passportNumber,
                    licenseNumber: c.licenseNumber,
                    notes: c.notes,
                    customFields: c.customFields.map {
                        CustomField(name: $0.name, value: $0.value, type: $0.type, linkedId: $0.linkedId)
                    }
                ))
            case .sshKey(let c):
                return .sshKey(SSHKeyContent(
                    privateKey: c.privateKey,
                    publicKey: c.publicKey,
                    keyFingerprint: c.keyFingerprint,
                    notes: c.notes,
                    customFields: c.customFields.map {
                        CustomField(name: $0.name, value: $0.value, type: $0.type, linkedId: $0.linkedId)
                    }
                ))
            }
        }()
    }
}
