import Foundation

// MARK: - VaultExportDocument

/// The Bitwarden unencrypted JSON export format, as a Swift value type.
///
/// **What this is.** A backup that only Prizm can read is not an escape hatch, it is a second
/// lock. This type therefore models *Bitwarden's* interchange format rather than a Prizm one, so
/// the file can be restored by Prizm, by the official desktop client, by `bw`, or by any
/// Vaultwarden-compatible tool.
///
/// **Where the shape comes from.** It was read out of the reference implementation, not
/// reconstructed from memory — `libs/common/src/models/export/*.export.ts` and
/// `libs/tools/export-vault-core/src/services/individual-vault-export.service.ts` in
/// `bitwarden/clients`. The details that are easy to get wrong, each verified against that source:
///
/// - **Folders carry an `id`.** `FolderExport` alone has only a `name`; the individual export
///   builds `FolderWithIdExport`. An item's `folderId` therefore resolves inside the file.
/// - **Items carry an `id`** (`CipherWithIdExport`). It is written but **never read back on
///   import** — the server assigns ids and a file-local one means nothing on another server.
/// - **`match` on a URI is an integer**, not a string — `URIMatchType.rawValue`, matching
///   Bitwarden's `UriMatchStrategySetting`. 0 is "default" and 1 is "base domain"; a build that
///   numbered its own cases from `domain = 0` would write every strategy one step off.
/// - **`collectionIds` is `null`, not `[]`, for a personal item.** Modelled as an optional and
///   omitted when nil, which every conforming parser treats identically.
/// - **`key` is deleted before writing.** The unencrypted export carries no per-item key.
/// - **Deleted items are not exported.** The reference filters `deletedDate == null`, so Trash is
///   deliberately not part of a backup.
/// - **`passwordHistory` is part of the format** — `{ password, lastUsedDate }`. Previous
///   passwords are therefore exported; see the note on `ExportItem.passwordHistory`.
///
/// **One deliberate difference from the reference.** The official *individual* export filters out
/// every item with a non-nil `organizationId`, so "export my vault" silently omits everything the
/// user holds through an organisation. This type includes them, with `organizationId` and
/// `collectionIds` populated exactly as the official *org* export does. Every field used is one of
/// the reference classes' own fields, so the file stays readable by any client — the difference is
/// that it does not throw data away.
///
/// **Nothing here is encrypted, and nothing here is logged.** Encoding this type writes every
/// password in the vault as plaintext.
nonisolated struct VaultExportDocument: Codable, Equatable {

    /// Always `false`. This is what makes every client treat the file as plaintext rather than
    /// trying to decrypt it, and the importer refuses a document where it is `true`.
    let encrypted: Bool

    let folders: [ExportFolder]
    let items: [ExportItem]

    /// `folders` is defaulted rather than required: a file produced by a tool that omits an empty
    /// `folders` array is still a valid export, and refusing it would be pedantry that costs the
    /// user their import.
    init(encrypted: Bool, folders: [ExportFolder], items: [ExportItem]) {
        self.encrypted = encrypted
        self.folders   = folders
        self.items     = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.encrypted = try container.decode(Bool.self, forKey: .encrypted)
        self.folders   = try container.decodeIfPresent([ExportFolder].self, forKey: .folders) ?? []
        self.items     = try container.decode([ExportItem].self, forKey: .items)
    }

    /// Declared rather than synthesised: this type provides its own `init(from:)`, and spelling
    /// the keys out keeps the wire names visible next to the format they belong to.
    enum CodingKeys: String, CodingKey {
        case encrypted, folders, items
    }
}

// MARK: - Folders

nonisolated struct ExportFolder: Codable, Equatable {
    let id: String
    let name: String
}

// MARK: - Items

nonisolated struct ExportItem: Codable, Equatable {

    /// The server's cipher id. Written for fidelity; never read back on import.
    let id: String

    /// Non-nil for an item that belongs to an organisation.
    let organizationId: String?

    /// The `id` of an entry in the document's `folders` array, or nil for an unfoldered item.
    let folderId: String?

    /// Omitted for personal items, matching the reference's `collectionIds = null`.
    let collectionIds: [String]?

    /// The server's `CipherType` enum: 1 login, 2 secure note, 3 card, 4 identity, 5 SSH key.
    /// Must match `CipherMapper.mapContent`.
    let type: Int

    /// 0 = no re-prompt, 1 = require the master password before revealing.
    let reprompt: Int

    let name: String

    /// The item's notes. Top-level on the item, not inside the per-type sub-object — the
    /// reference's `LoginExport` and friends have no `notes` field of their own.
    let notes: String?

    let favorite: Bool

    /// Custom fields. Also top-level, for the same reason as `notes`.
    let fields: [ExportCustomField]?

    let login: ExportLogin?
    let secureNote: ExportSecureNote?
    let card: ExportCard?
    let identity: ExportIdentity?
    let sshKey: ExportSSHKey?

    /// The previous passwords the server has been keeping, oldest entries last.
    ///
    /// **Exported, not omitted.** The first draft of the design claimed the format had no place
    /// for this and that it would be dropped. That was wrong: `CipherExport.passwordHistory`
    /// exists and `PasswordHistoryExport` is `{ password, lastUsedDate }`. The file already
    /// contains every *current* password in plaintext, so the previous ones add no new class of
    /// exposure — and leaving them out would mean a restore silently loses them.
    let passwordHistory: [ExportPasswordHistoryEntry]?

    let creationDate: String?
    let revisionDate: String?
    let deletedDate: String?
    let archivedDate: String?
}

nonisolated struct ExportCustomField: Codable, Equatable {
    let name: String
    let value: String?
    /// `CustomFieldType` raw value: 0 text, 1 hidden, 2 boolean, 3 linked.
    let type: Int
    /// `LinkedFieldId` raw value; present only when `type == 3`.
    let linkedId: Int?
}

nonisolated struct ExportPasswordHistoryEntry: Codable, Equatable {
    let password: String
    let lastUsedDate: String?
}

// MARK: - Per-type payloads

nonisolated struct ExportLogin: Codable, Equatable {
    let uris: [ExportLoginURI]?
    let username: String?
    let password: String?
    /// The stored TOTP seed. Exported because the format carries it and a restore without it
    /// would silently disable two-factor on every account.
    let totp: String?
}

nonisolated struct ExportLoginURI: Codable, Equatable {
    let uri: String
    /// `URIMatchType` raw value. An integer, matching `UriMatchStrategySetting`.
    let match: Int?
}

/// The note's subtype, as Bitwarden's `SecureNoteType` integer.
///
/// This comment used to say the type was "always 0", and the code made that true by hardcoding it —
/// so exporting a passport note wrote a generic one. It carries the item's actual subtype now.
nonisolated struct ExportSecureNote: Codable, Equatable {
    let type: Int
}

nonisolated struct ExportCard: Codable, Equatable {
    let cardholderName: String?
    let brand: String?
    let number: String?
    let expMonth: String?
    let expYear: String?
    let code: String?
}

nonisolated struct ExportIdentity: Codable, Equatable {
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
}

nonisolated struct ExportSSHKey: Codable, Equatable {
    let privateKey: String?
    let publicKey: String?
    let keyFingerprint: String?
}

// MARK: - Item type mapping

/// The server's `CipherType` enum, as used by the interchange format.
///
/// A separate type from `ItemType` on purpose: `ItemType` is a `String`-backed enum used for
/// sidebar selection and storage keys, and changing its raw values to integers would ripple
/// through the sidebar, the counts index and `SidebarSelection`. This maps between them, in one
/// place, with the reference citation attached.
nonisolated enum ExportItemType: Int, CaseIterable {
    case login      = 1
    case secureNote = 2
    case card       = 3
    case identity   = 4
    case sshKey     = 5

    init(_ itemType: ItemType) {
        switch itemType {
        case .login:      self = .login
        case .secureNote: self = .secureNote
        case .card:       self = .card
        case .identity:   self = .identity
        case .sshKey:     self = .sshKey
        }
    }

    var itemType: ItemType {
        switch self {
        case .login:      return .login
        case .secureNote: return .secureNote
        case .card:       return .card
        case .identity:   return .identity
        case .sshKey:     return .sshKey
        }
    }
}

// MARK: - Errors

nonisolated enum VaultExportDocumentError: Error, LocalizedError, Equatable {

    /// The item's type integer is not one of 1–5. Reported with the number so the user can see
    /// what the file asked for rather than being told "invalid file".
    case unsupportedItemType(Int)

    /// The item has no name. The server requires one, so an import cannot invent it.
    case missingItemName

    /// Not JSON, or JSON with no `items` array.
    case notAnUnencryptedExport

    /// A valid export whose `encrypted` flag is `true`. Called out separately from
    /// `notAnUnencryptedExport` because the file is a real export and the user deserves to be told
    /// *which* kind is unsupported rather than that their file is not an export at all.
    case encryptedExportUnsupported

    /// The document's shape is right but an item could not be read.
    case malformedExport

    var errorDescription: String? {
        switch self {
        case .unsupportedItemType(let type):
            return L("Item type %lld is not supported.", type)
        case .missingItemName:
            return L("An item has no name.")
        case .notAnUnencryptedExport:
            return L("This file is not an unencrypted Bitwarden export.")
        case .encryptedExportUnsupported:
            return L("This is an encrypted export. Vitrine can only import unencrypted exports.")
        case .malformedExport:
            return L("The export file could not be read.")
        }
    }
}

// MARK: - Entity → document

nonisolated extension VaultExportDocument {

    /// Builds the document from the decrypted vault.
    ///
    /// - Parameters:
    ///   - items: every item to export. Callers pass the active vault, not Trash — the reference
    ///     filters `deletedDate == null`, and this type does not second-guess that.
    ///   - folders: the folders the items may reference.
    ///   - passwordHistory: decrypted history keyed by item id. An item absent from the map, or
    ///     mapped to an empty array, is written without a `passwordHistory` key. The history is
    ///     supplied by the caller because producing it requires decryption, which this pure
    ///     value type deliberately does not do.
    init(items: [VaultItem],
         folders: [Folder],
         passwordHistory: [String: [PasswordHistoryEntry]] = [:]) {

        self.encrypted = false
        self.folders   = folders.map { ExportFolder(id: $0.id, name: $0.name) }
        self.items     = items.map { item in
            ExportItem(item, history: passwordHistory[item.id] ?? [])
        }
    }
}

private nonisolated extension ExportItem {

    init(_ item: VaultItem, history: [PasswordHistoryEntry]) {
        let notesAndFields = item.content.notesAndCustomFields

        self.id             = item.id
        self.organizationId = item.organizationId
        self.folderId       = item.folderId
        self.collectionIds  = item.collectionIds.isEmpty ? nil : item.collectionIds
        self.type           = ExportItemType(item.content.itemType).rawValue
        self.reprompt       = item.reprompt
        self.name           = item.name
        self.notes          = notesAndFields.notes
        self.favorite       = item.isFavorite
        self.fields         = notesAndFields.fields.isEmpty
            ? nil
            : notesAndFields.fields.map(ExportCustomField.init)

        self.login      = item.content.loginPayload
        self.secureNote = item.content.secureNotePayload
        self.card       = item.content.cardPayload
        self.identity   = item.content.identityPayload
        self.sshKey     = item.content.sshKeyPayload

        self.passwordHistory = history.isEmpty
            ? nil
            : history.map {
                ExportPasswordHistoryEntry(
                    password:     $0.password,
                    lastUsedDate: $0.lastUsedDate.map(VaultExportDocument.formatISO8601)
                )
            }

        self.creationDate = VaultExportDocument.formatISO8601(item.creationDate)
        self.revisionDate = VaultExportDocument.formatISO8601(item.revisionDate)
        // Never written: this type is only ever built from the active vault. Present in the model
        // so a document read from a file round-trips rather than losing the field.
        self.deletedDate  = nil
        self.archivedDate = item.preserved.archivedDate
    }
}

private nonisolated extension ExportCustomField {
    init(_ field: CustomField) {
        self.name     = field.name
        self.value    = field.value
        self.type     = field.type.rawValue
        self.linkedId = field.type == .linked ? field.linkedId?.rawValue : nil
    }
}

// MARK: - Content projection

/// Reads the pieces the export needs out of `ItemContent` without a five-way `switch` at each
/// use site. Each accessor returns `nil` for content of the wrong type, so a card item simply has
/// no `login` payload rather than a fabricated empty one.
private nonisolated extension ItemContent {

    var itemType: ItemType {
        switch self {
        case .login:      return .login
        case .secureNote: return .secureNote
        case .card:       return .card
        case .identity:   return .identity
        case .sshKey:     return .sshKey
        }
    }

    /// Notes and custom fields, which the format carries at the top level of the item rather than
    /// inside the per-type payload.
    var notesAndCustomFields: (notes: String?, fields: [CustomField]) {
        switch self {
        case .login(let c):      return (c.notes, c.customFields)
        case .secureNote(let c): return (c.notes, c.customFields)
        case .card(let c):       return (c.notes, c.customFields)
        case .identity(let c):   return (c.notes, c.customFields)
        case .sshKey(let c):     return (c.notes, c.customFields)
        }
    }

    var loginPayload: ExportLogin? {
        guard case .login(let c) = self else { return nil }
        return ExportLogin(
            uris: c.uris.map { ExportLoginURI(uri: $0.uri, match: $0.matchType?.rawValue) },
            username: c.username,
            password: c.password,
            totp: c.totp
        )
    }

    var secureNotePayload: ExportSecureNote? {
        guard case .secureNote(let c) = self else { return nil }
        return ExportSecureNote(type: c.subtype.rawValue)
    }

    var cardPayload: ExportCard? {
        guard case .card(let c) = self else { return nil }
        return ExportCard(
            cardholderName: c.cardholderName,
            brand: c.brand,
            number: c.number,
            expMonth: c.expMonth,
            expYear: c.expYear,
            code: c.code
        )
    }

    var identityPayload: ExportIdentity? {
        guard case .identity(let c) = self else { return nil }
        return ExportIdentity(
            title: c.title, firstName: c.firstName, middleName: c.middleName,
            lastName: c.lastName, address1: c.address1, address2: c.address2,
            address3: c.address3, city: c.city, state: c.state,
            postalCode: c.postalCode, country: c.country, company: c.company,
            email: c.email, phone: c.phone, ssn: c.ssn,
            username: c.username, passportNumber: c.passportNumber,
            licenseNumber: c.licenseNumber
        )
    }

    var sshKeyPayload: ExportSSHKey? {
        guard case .sshKey(let c) = self else { return nil }
        return ExportSSHKey(
            privateKey: c.privateKey,
            publicKey: c.publicKey,
            keyFingerprint: c.keyFingerprint
        )
    }
}

// MARK: - Dates

nonisolated extension VaultExportDocument {

    /// Formats a date the way the reference does: `JSON.stringify` of a JS `Date` is
    /// `Date.prototype.toISOString()`, which is always UTC with millisecond precision.
    static func formatISO8601(_ date: Date) -> String {
        iso8601WithFraction.string(from: date)
    }

    /// Parses either form. `ISO8601DateFormatter` with `.withFractionalSeconds` rejects a string
    /// without them, and Vaultwarden writes both, so both are tried.
    static func parseISO8601(_ raw: String) -> Date? {
        iso8601WithFraction.date(from: raw) ?? iso8601Plain.date(from: raw)
    }

    private nonisolated(unsafe) static let iso8601WithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
