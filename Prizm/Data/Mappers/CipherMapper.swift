import Foundation
import os.log

// MARK: - CipherMapperError

/// Errors that can be thrown by `CipherMapper.map(raw:keys:)`.
nonisolated enum CipherMapperError: Error, Equatable {
    /// The cipher belongs to an organisation and is intentionally skipped in
    /// the personal vault view (organizationId != nil).
    case organisationCipherSkipped
    /// The cipher has an unknown `type` integer.
    case unsupportedCipherType(Int)
    /// A required encrypted field could not be decrypted.
    case fieldDecryptionFailed(String)
}

// MARK: - CipherMapper

/// Transforms a `RawCipher` (wire-format, encrypted) into a `VaultItem` (domain,
/// decrypted) using the provided symmetric `CryptoKeys`.
///
/// **Responsibilities** (one responsibility each):
/// - Decrypt each EncString field using AES-256-CBC + HMAC-SHA256 (EncString type-2).
///   Decryption is eager (at sync time, inside the mapper) rather than lazy (at display
///   time, inside Views). This keeps `VaultItem` domain entities as plain decrypted
///   Swift structs, so the Presentation layer never imports or calls crypto code.
///   Decryption failures are surfaced once during sync rather than scattered across the UI.
/// - Map the raw `type` integer to a typed `ItemContent` enum case.
/// - Filter out organisation ciphers (`organizationId != nil`) — personal vault only.
/// - Map raw `RawField` array to `[CustomField]` domain values.
///
/// **What this class does NOT do**:
/// - Network I/O.
/// - Keychain access.
/// - KDF derivation.
// `Sendable`: all state is immutable (let properties, nonisolated(unsafe) static).
nonisolated final class CipherMapper: Sendable {

    private let attachmentMapper = AttachmentMapper()

    private static let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "CipherMapper")

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Public API

    /// Maps a single `RawCipher` to a `VaultItem` and returns the effective cipher key.
    ///
    /// The returned tuple is used by:
    /// - **Callers that only need the item** (`SyncRepositoryImpl`, `VaultRepositoryImpl.update`,
    ///   `VaultRepositoryImpl.create`): destructure and discard the `cipherKey` value.
    /// - **`SyncRepositoryImpl`**: collect all `cipherKey` values and populate `VaultKeyCache`.
    ///
    /// **Effective cipher key derivation** (Bitwarden Security Whitepaper §4):
    /// - If `raw.key` is non-nil (cipher has a per-item symmetric key), decrypt it with the
    ///   vault key and return the 64-byte plaintext as the effective key.
    /// - If `raw.key` is nil, the cipher uses the vault-level key directly — return
    ///   `keys.encryptionKey + keys.macKey` (64 bytes).
    ///
    /// - Parameters:
    ///   - raw:      The encrypted wire-format cipher from the sync response.
    ///   - vaultKeys: The personal vault symmetric key pair (used for personal ciphers).
    ///   - orgKeys:  Snapshot of `OrgKeyCache` keyed by organization ID. Pass `[:]` when
    ///               no org key support is available (personal-only vault).
    /// - Returns: A tuple of the decrypted `VaultItem` and its 64-byte effective cipher key.
    /// - Throws: `CipherMapperError.organisationCipherSkipped` when the cipher's org key is absent from `orgKeys`.
    /// - Throws: `CipherMapperError.unsupportedCipherType` for unknown type integers.
    /// - Throws: `EncStringError` or `CipherMapperError.fieldDecryptionFailed` on decryption failure.
    func map(raw: RawCipher, vaultKeys: CryptoKeys, orgKeys: [String: CryptoKeys] = [:]) throws -> (item: VaultItem, cipherKey: Data) {
        // Select the key to use for this cipher.
        // Org ciphers use the org's symmetric key; personal ciphers use the vault key.
        let activeKeys: CryptoKeys
        if let orgId = raw.organizationId {
            guard let orgKey = orgKeys[orgId] else {
                // Org key not available (org sync not yet complete, or org key unwrap failed).
                // Skip this cipher rather than showing garbled content.
                throw CipherMapperError.organisationCipherSkipped
            }
            activeKeys = orgKey
        } else {
            activeKeys = vaultKeys
        }

        // Effective cipher key: per-item key if present, otherwise the active (vault or org) key.
        // Reference: Bitwarden Security Whitepaper §4 — "Cipher Key Wrapping".
        // Must be resolved FIRST, before anything is decrypted: a cipher carrying a per-item key
        // encrypts *all* of its data with that key — name, notes, custom fields, the type-specific
        // payload, password history and attachments alike. The vault/org key is then used only to
        // unwrap it. Verified against the official client, `Cipher.decrypt` in
        // libs/common/src/vault/models/domain/cipher.ts: `userKeyOrOrgKey` is passed solely to
        // `encryptService.unwrapSymmetricKey(this.key, userKeyOrOrgKey)`, and the unwrapped key is
        // what decrypts every field. Decrypting with `activeKeys` instead made items that have a
        // per-item key unreadable — the fields were encrypted with a key this client never tried.
        let cipherKey: Data
        if let encItemKey = raw.key {
            // Per-item key: decrypt the EncString-wrapped key using the active key (vault OR org).
            do {
                let enc = try EncString(string: encItemKey)
                cipherKey = try enc.decrypt(keys: activeKeys)
            } catch {
                Self.logger.fault("Per-item key decryption failed for cipher \(raw.id, privacy: .public)")
                throw CipherMapperError.fieldDecryptionFailed("key")
            }
        } else {
            // No per-item key — use the active key directly.
            cipherKey = activeKeys.encryptionKey + activeKeys.macKey
        }

        // Build CryptoKeys from the resolved 64-byte cipher key (first 32 bytes = enc, last 32 = mac).
        let effectiveKeys = CryptoKeys(
            encryptionKey: cipherKey.prefix(32),
            macKey:        cipherKey.suffix(32)
        )

        let name   = try decryptRequired(raw.name, field: "name", keys: effectiveKeys)
        let notes  = try raw.notes.map { try decryptRequired($0, field: "notes", keys: effectiveKeys) }
        let fields = try mapFields(raw.fields ?? [], keys: effectiveKeys)

        let content: ItemContent = try mapContent(
            type:   raw.type,
            raw:    raw,
            notes:  notes,
            fields: fields,
            keys:   effectiveKeys
        )

        let fallbackDate = Date(timeIntervalSince1970: 0)
        let creationDate  = raw.creationDate.flatMap  { Self.iso8601.date(from: $0) } ?? fallbackDate
        let revisionDate  = raw.revisionDate.flatMap  { Self.iso8601.date(from: $0) } ?? fallbackDate

        // Map attachments using the cipher's effective key, not the raw vault key.
        // Attachment filenames are encrypted under the same key as the cipher's fields.
        let attachments: [Attachment] = (raw.attachments ?? []).compactMap { dto in
            do {
                return try attachmentMapper.map(dto, cipherKey: effectiveKeys)
            } catch {
                Self.logger.error("Attachment mapping failed for cipher \(raw.id, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }

        // Fields Prizm has no UI for, carried verbatim so a later save cannot delete them.
        // `PUT /api/ciphers/{id}` replaces the whole cipher: Vaultwarden assigns `key`,
        // `password_history` and `archived_date` unconditionally and stores the `login` object
        // verbatim, so anything missing from the request body is erased server-side.
        // See `PreservedCipherFields` and openspec/changes/critical-integrity-fixes.
        let preserved = PreservedCipherFields(
            passwordHistory:      raw.passwordHistory ?? [],
            archivedDate:         raw.archivedDate,
            cipherKey:            raw.key,
            fido2Credentials:     raw.login?.fido2Credentials ?? [],
            passwordRevisionDate: raw.login?.passwordRevisionDate,
            autofillOnPageLoad:   raw.login?.autofillOnPageLoad,
            revisionDate:         raw.revisionDate
        )

        let item = VaultItem(
            id:             raw.id,
            name:           name,
            isFavorite:     raw.favorite,
            isDeleted:      raw.deletedDate != nil,
            creationDate:   creationDate,
            revisionDate:   revisionDate,
            content:        content,
            reprompt:       raw.reprompt ?? 0,
            attachments:    attachments,
            folderId:       raw.folderId,
            organizationId: raw.organizationId,
            collectionIds:  raw.collectionIds,
            preserved:      preserved
        )
        return (item: item, cipherKey: cipherKey)
    }

    /// Backward-compatible overload — passes empty orgKeys (personal vault, no org support).
    func map(raw: RawCipher, keys: CryptoKeys) throws -> (item: VaultItem, cipherKey: Data) {
        try map(raw: raw, vaultKeys: keys, orgKeys: [:])
    }

    // MARK: - Private: Content dispatch

    private func mapContent(
        type:   Int,
        raw:    RawCipher,
        notes:  String?,
        fields: [CustomField],
        keys:   CryptoKeys
    ) throws -> ItemContent {
        // Type integers match the Bitwarden server CipherType enum:
        // 1=Login, 2=SecureNote, 3=Card, 4=Identity, 5=SSHKey.
        // Reference: github.com/bitwarden/server CipherType.cs; vaultwarden CipherType enum.
        switch type {
        case 1: return try mapLogin(raw.login,       notes: notes, fields: fields, keys: keys)
        case 2: return mapSecureNote(raw.secureNote, notes: notes, fields: fields)
        case 3: return try mapCard(raw.card,         notes: notes, fields: fields, keys: keys)
        case 4: return try mapIdentity(raw.identity, notes: notes, fields: fields, keys: keys)
        case 5: return try mapSSHKey(raw.sshKey,     notes: notes, fields: fields, keys: keys)
        default:
            throw CipherMapperError.unsupportedCipherType(type)
        }
    }

    // MARK: - Login

    private func mapLogin(
        _ data: RawLoginData?,
        notes:  String?,
        fields: [CustomField],
        keys:   CryptoKeys
    ) throws -> ItemContent {
        let login = data ?? RawLoginData(username: nil, password: nil, uris: [], totp: nil)
        let uris: [LoginURI] = try (login.uris ?? []).compactMap { rawURI in
            guard let encUri = rawURI.uri else { return nil }
            let uriStr = try decryptRequired(encUri, field: "uri", keys: keys)
            let match  = rawURI.match.map { URIMatchType(rawValue: $0) }
            return LoginURI(uri: uriStr, matchType: match)
        }
        return .login(LoginContent(
            username:     try login.username.map { try decryptRequired($0, field: "username", keys: keys) },
            password:     try login.password.map { try decryptRequired($0, field: "password", keys: keys) },
            uris:         uris,
            totp:         try login.totp.map { try decryptRequired($0, field: "totp", keys: keys) },
            notes:        notes,
            customFields: fields
        ))
    }

    // MARK: - Secure Note

    /// - Parameter data: The secure-note payload. `nil` for items that predate the subtype field,
    ///   which decode as `.generic` — the same value a payload of `type: 0` carries, so the two are
    ///   indistinguishable downstream and the UI can hide the row without a special case.
    private func mapSecureNote(_ data: RawSecureNoteData?, notes: String?, fields: [CustomField]) -> ItemContent {
        .secureNote(SecureNoteContent(
            notes:        notes,
            customFields: fields,
            subtype:      SecureNoteSubtype(rawValue: data?.type ?? 0)
        ))
    }

    // MARK: - Card

    private func mapCard(
        _ data: RawCardData?,
        notes:  String?,
        fields: [CustomField],
        keys:   CryptoKeys
    ) throws -> ItemContent {
        let card = data ?? RawCardData(cardholderName: nil, brand: nil, number: nil,
                                      expMonth: nil, expYear: nil, code: nil)
        return .card(CardContent(
            cardholderName: try card.cardholderName.map { try decryptRequired($0, field: "cardholderName", keys: keys) },
            brand:          try card.brand.map          { try decryptRequired($0, field: "brand",          keys: keys) },
            number:         try card.number.map         { try decryptRequired($0, field: "number",         keys: keys) },
            expMonth:       try card.expMonth.map       { try decryptRequired($0, field: "expMonth",       keys: keys) },
            expYear:        try card.expYear.map        { try decryptRequired($0, field: "expYear",        keys: keys) },
            code:           try card.code.map           { try decryptRequired($0, field: "code",           keys: keys) },
            notes:          notes,
            customFields:   fields
        ))
    }

    // MARK: - Identity

    private func mapIdentity(
        _ data: RawIdentityData?,
        notes:  String?,
        fields: [CustomField],
        keys:   CryptoKeys
    ) throws -> ItemContent {
        let id = data ?? RawIdentityData(
            title: nil, firstName: nil, middleName: nil, lastName: nil,
            address1: nil, address2: nil, address3: nil, city: nil, state: nil,
            postalCode: nil, country: nil, company: nil, email: nil, phone: nil,
            ssn: nil, username: nil, passportNumber: nil, licenseNumber: nil
        )
        func dec(_ s: String?, field: String) throws -> String? {
            try s.map { try decryptRequired($0, field: field, keys: keys) }
        }
        return .identity(IdentityContent(
            title:          try dec(id.title,           field: "title"),
            firstName:      try dec(id.firstName,       field: "firstName"),
            middleName:     try dec(id.middleName,      field: "middleName"),
            lastName:       try dec(id.lastName,        field: "lastName"),
            address1:       try dec(id.address1,        field: "address1"),
            address2:       try dec(id.address2,        field: "address2"),
            address3:       try dec(id.address3,        field: "address3"),
            city:           try dec(id.city,            field: "city"),
            state:          try dec(id.state,           field: "state"),
            postalCode:     try dec(id.postalCode,      field: "postalCode"),
            country:        try dec(id.country,         field: "country"),
            company:        try dec(id.company,         field: "company"),
            email:          try dec(id.email,           field: "email"),
            phone:          try dec(id.phone,           field: "phone"),
            ssn:            try dec(id.ssn,             field: "ssn"),
            username:       try dec(id.username,        field: "username"),
            passportNumber: try dec(id.passportNumber,  field: "passportNumber"),
            licenseNumber:  try dec(id.licenseNumber,   field: "licenseNumber"),
            notes:          notes,
            customFields:   fields
        ))
    }

    // MARK: - SSH Key

    private func mapSSHKey(
        _ data: RawSSHKeyData?,
        notes:  String?,
        fields: [CustomField],
        keys:   CryptoKeys
    ) throws -> ItemContent {
        let ssh = data ?? RawSSHKeyData(privateKey: nil, publicKey: nil, keyFingerprint: nil)
        return .sshKey(SSHKeyContent(
            privateKey:     try ssh.privateKey.map  { try decryptRequired($0, field: "privateKey",  keys: keys) },
            publicKey:      try ssh.publicKey.map   { try decryptRequired($0, field: "publicKey",   keys: keys) },
            keyFingerprint: try ssh.keyFingerprint.map { try decryptRequired($0, field: "keyFingerprint", keys: keys) },
            notes:          notes,
            customFields:   fields
        ))
    }

    // MARK: - Custom Fields

    private func mapFields(_ rawFields: [RawField], keys: CryptoKeys) throws -> [CustomField] {
        try rawFields.compactMap { raw in
            // name is required for CustomField; skip fields with no name
            guard let rawName = raw.name else { return nil }
            let name     = try decryptRequired(rawName, field: "field.name", keys: keys)
            let value    = try raw.value.map { try decryptRequired($0, field: "field.value", keys: keys) }
            let type     = CustomFieldType(rawValue: raw.type) ?? .text
            let linkedId = raw.linkedId.flatMap { LinkedFieldId(rawValue: $0) }
            return CustomField(name: name, value: value, type: type, linkedId: linkedId)
        }
    }

    // MARK: - Reverse mapper (domain → wire)

    /// Converts a mutable `DraftVaultItem` into an encrypted `RawCipher` ready for
    /// `PUT /ciphers/{id}`.
    ///
    /// - Security goal: ensures that no vault secret (password, card number, private key, etc.)
    ///   ever leaves the device in plaintext. Every string field that is an EncString on the
    ///   Bitwarden wire format is re-encrypted here before the request body is serialised.
    ///
    /// - Algorithm: EncString type-2 — AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC).
    ///   Spec reference: Bitwarden Security Whitepaper §4 (https://bitwarden.com/images/resources/security-white-paper-download.pdf).
    ///   Standard reference: AES-CBC per NIST SP 800-38A; HMAC-SHA256 per RFC 2104.
    ///   Each field gets a cryptographically random 16-byte IV via `SecRandomCopyBytes`
    ///   (Security.framework). Reusing IVs across fields would break CBC confidentiality;
    ///   the fresh-IV-per-field approach matches the Bitwarden client reference implementation.
    ///
    /// - Deviations from the Bitwarden reference: none. The EncString type-2 format and
    ///   key material (AES key + MAC key from `CryptoKeys`) are identical to what the
    ///   official web vault uses when editing an item.
    ///
    /// - What is NOT done:
    ///   • `id`, `type`, `favorite` are plain JSON values (not EncStrings) — sent as-is.
    ///   • `deletedDate`, `creationDate`, `revisionDate` are sent as `nil` — the server is
    ///     authoritative for these timestamps and ignores client-provided values on PUT.
    ///   • `attachments` is sent as `nil` — verified safe against Vaultwarden
    ///     (`if let Some(attachments) = data.attachments2` guards the only attachment write, so
    ///     an absent key leaves stored attachments untouched).
    ///   • Biometric re-authentication before re-encryption is not performed here; it is
    ///     the caller's responsibility (see `VaultRepositoryImpl.update` TODO).
    ///
    /// - What IS done to avoid destroying data: every wire field Prizm does not interpret
    ///   (`passwordHistory`, `archivedDate`, `key`, `login.fido2Credentials`,
    ///   `login.passwordRevisionDate`, `login.autofillOnPageLoad`) is copied out of
    ///   `draft.preserved` unchanged. `PUT` replaces the whole cipher, so omitting one of them
    ///   deletes it server-side.
    ///
    /// - Parameter draft: The edited item to re-encrypt.
    /// - Parameter keys:  The wrapping key pair (vault key for personal items, org key for org
    ///   items). When the draft carries a per-item key, that key is unwrapped from this one and
    ///   used for the actual field encryption — see `resolveFieldKeys`.
    /// - Returns: A `RawCipher` with all sensitive string fields encrypted as EncStrings.
    /// - Throws: `EncStringError` if IV generation or AES/HMAC computation fails.
    /// - Throws: `CipherMapperError.fieldDecryptionFailed("key")` if a per-item key is present
    ///   but cannot be unwrapped with `keys`.
    func toRawCipher(_ draft: DraftVaultItem, encryptedWith keys: CryptoKeys) throws -> RawCipher {
        // Resolve the key that actually protects this cipher's fields *before* encrypting
        // anything. A cipher carrying a per-item key encrypts its fields — and its attachments —
        // with that key; re-encrypting with the wrapping key would change the cipher's key
        // structure and orphan every attachment whose key was wrapped with the old one.
        let fieldKeys = try resolveFieldKeys(preserved: draft.preserved, wrapping: keys)

        let encName  = try encryptString(draft.name, keys: fieldKeys)
        let encNotes: String? = try {
            switch draft.content {
            case .login(let c):      return try c.notes.map { try encryptString($0, keys: fieldKeys) }
            case .secureNote(let c): return try c.notes.map { try encryptString($0, keys: fieldKeys) }
            case .card(let c):       return try c.notes.map { try encryptString($0, keys: fieldKeys) }
            case .identity(let c):   return try c.notes.map { try encryptString($0, keys: fieldKeys) }
            case .sshKey(let c):     return try c.notes.map { try encryptString($0, keys: fieldKeys) }
            }
        }()
        let encFields = try toRawFields(customFieldsOf(draft.content), keys: fieldKeys)

        let (type, loginData, cardData, identityData, secureNoteData, sshKeyData) =
            try encryptContent(draft.content, preserved: draft.preserved, keys: fieldKeys)

        return RawCipher(
            id:             draft.id,
            organizationId: draft.organizationId,
            folderId:       draft.folderId,
            type:           type,
            name:           encName,
            notes:          encNotes,
            favorite:       draft.isFavorite,
            reprompt:       draft.reprompt,
            // No source: `DraftVaultItem` keeps only `isDeleted`, so the timestamp is not available
            // to send back. Timestamps are server-authoritative on a PUT, so `nil` is right for the
            // latter two.
            //
            // `deletedDate` is different in kind, and is safe **only because nothing reaches it**:
            // the edit sheet refuses trashed items and the trash toolbar replaces Edit with
            // Restore/Delete, so a draft is never built from a trashed cipher. Vaultwarden also
            // ignores the field on update. Both of those are load-bearing — a new path that builds a
            // draft from a trashed item would send `nil` and un-trash it. See the sweep in
            // `openspec/changes/collection-permission-round-trip/design.md`.
            deletedDate:    nil,
            creationDate:   nil,
            revisionDate:   nil,
            login:          loginData,
            card:           cardData,
            identity:       identityData,
            secureNote:     secureNoteData,
            sshKey:         sshKeyData,
            fields:         encFields.isEmpty ? nil : encFields,
            key:            draft.preserved.cipherKey,
            collectionIds:  draft.collectionIds,
            attachments:    nil,
            passwordHistory: try passwordHistoryToSend(for: draft, keys: fieldKeys),
            archivedDate:    draft.preserved.archivedDate,
            // Distinct from `revisionDate: nil` above: that is the cipher's own timestamp, which
            // the server owns. This is the revision *this client last saw*, and it is what stops a
            // save from silently overwriting a newer copy. Carried verbatim from `preserved` —
            // reformatting the `Date` would send an approximation of an instant the server compares
            // exactly.
            lastKnownRevisionDate: draft.preserved.revisionDate
        )
    }

    // MARK: - Private: password history

    /// `passwordHistory` as it will be sent: the history the item arrived with, plus the password
    /// this save replaces, when the user actually changed one.
    ///
    /// **Why the client has to do this.** The server stores exactly the array it is sent and keeps
    /// no history of its own (Vaultwarden's `update_cipher_from_data` writes `data.password_history`
    /// straight through). A client that only round-trips the array therefore records nothing — and
    /// because a full `PUT` replaces the whole cipher, a save made without an intervening sync
    /// re-sends the older array over anything another client appended in the meantime.
    ///
    /// **When an entry is added.** Only when the login's password changed to a *non-empty* value.
    /// Clearing the password is a deliberate removal rather than a replacement, and recording it
    /// would put a password the user just deleted into the history they are shown.
    ///
    /// **`lastUsedDate` is the moment of the replacement**, which is when the previous password
    /// stopped being used. Bitwarden's own export model falls back to the current time when the
    /// field is absent, so that is the reading this follows; the exact convention its clients write
    /// was not established from a first-party source, which is recorded in the change's tasks.
    private func passwordHistoryToSend(for draft: DraftVaultItem,
                                       keys: CryptoKeys) throws -> [JSONValue] {
        var history = draft.preserved.passwordHistory

        guard case .login(let login) = draft.content,
              let replaced = draft.replacedPassword,
              let current = login.password,
              !current.isEmpty,
              current != replaced
        else { return history }

        history.append(.object([
            "password":     .string(try encryptString(replaced, keys: keys)),
            "lastUsedDate": .string(Self.iso8601.string(from: Date())),
        ]))
        return history
    }

    // MARK: - Private: per-item key resolution

    /// Returns the key that encrypts this cipher's fields.
    ///
    /// A cipher may carry a per-item key (`raw.key`) which is itself wrapped with the vault key
    /// (personal ciphers) or the organisation key (org ciphers). When present, that key — not the
    /// wrapping key — protects the cipher's fields and attachments.
    ///
    /// Reference: Bitwarden Security Whitepaper §4 — "Cipher Key Wrapping".
    ///
    /// - Parameters:
    ///   - preserved: The draft's carried-through wire fields; `cipherKey` is the wrapped key.
    ///   - keys:      The wrapping key (vault or org), used only to unwrap the per-item key.
    /// - Returns: `keys` when there is no per-item key, otherwise the unwrapped per-item key.
    /// - Throws: `CipherMapperError.fieldDecryptionFailed("key")` when a per-item key exists but
    ///   cannot be unwrapped or is not 64 bytes. Refusing to write is the safe failure: encrypting
    ///   with the wrong key would produce an item no client can read.
    private func resolveFieldKeys(preserved: PreservedCipherFields,
                                 wrapping keys: CryptoKeys) throws -> CryptoKeys {
        guard let encItemKey = preserved.cipherKey else { return keys }
        do {
            let enc     = try EncString(string: encItemKey)
            let rawKey  = try enc.decrypt(keys: keys)
            guard let perItemKey = CryptoKeys(data: rawKey) else {
                throw CipherMapperError.fieldDecryptionFailed("key")
            }
            return perItemKey
        } catch {
            Self.logger.error("Per-item key could not be unwrapped — refusing to re-encrypt with the wrong key")
            throw CipherMapperError.fieldDecryptionFailed("key")
        }
    }

    // MARK: - Private: Reverse content dispatch

    private func encryptContent(
        _ content: DraftItemContent,
        preserved: PreservedCipherFields,
        keys: CryptoKeys
    ) throws -> (
        type: Int,
        login: RawLoginData?,
        card: RawCardData?,
        identity: RawIdentityData?,
        secureNote: RawSecureNoteData?,
        sshKey: RawSSHKeyData?
    ) {
        // Type integers: 1=Login, 2=SecureNote, 3=Card, 4=Identity, 5=SSHKey.
        // Must match the forward mapper (mapContent) and the Bitwarden server CipherType enum.
        switch content {
        case .login(let c):
            return (1, try toRawLogin(c, preserved: preserved, keys: keys), nil, nil, nil, nil)
        case .secureNote(let c):
            // The subtype is round-tripped, not invented. Sending a literal 0 here reset every note
            // to Generic on save, including notes whose subtype was set by another client.
            return (2, nil, nil, nil, RawSecureNoteData(type: c.subtype.rawValue), nil)
        case .card(let c):
            return (3, nil, try toRawCard(c, keys: keys), nil, nil, nil)
        case .identity(let c):
            return (4, nil, nil, try toRawIdentity(c, keys: keys), nil, nil)
        case .sshKey(let c):
            return (5, nil, nil, nil, nil, try toRawSSHKey(c, keys: keys))
        }
    }

    // MARK: - Private: Login reverse map

    /// Re-encrypts a login draft.
    ///
    /// The three trailing fields are copied from `preserved` rather than encrypted: they belong to
    /// features Prizm does not implement, and Vaultwarden stores the whole `login` object verbatim
    /// (`cipher.data = type_data.to_string()`), so omitting them deletes them server-side.
    private func toRawLogin(_ c: DraftLoginContent,
                            preserved: PreservedCipherFields,
                            keys: CryptoKeys) throws -> RawLoginData {
        let rawURIs: [RawURI] = try c.uris.map { uri in
            let encURI = try encryptString(uri.uri, keys: keys)
            return RawURI(uri: encURI, match: uri.matchType?.rawValue)
        }
        return RawLoginData(
            username: try c.username.map { try encryptString($0, keys: keys) },
            password: try c.password.map { try encryptString($0, keys: keys) },
            uris:     rawURIs,
            totp:     try c.totp.map { try encryptString($0, keys: keys) },
            fido2Credentials:     preserved.fido2Credentials.isEmpty ? nil : preserved.fido2Credentials,
            passwordRevisionDate: preserved.passwordRevisionDate,
            autofillOnPageLoad:   preserved.autofillOnPageLoad
        )
    }

    // MARK: - Private: Card reverse map

    private func toRawCard(_ c: DraftCardContent, keys: CryptoKeys) throws -> RawCardData {
        RawCardData(
            cardholderName: try c.cardholderName.map { try encryptString($0, keys: keys) },
            brand:          try c.brand.map          { try encryptString($0, keys: keys) },
            number:         try c.number.map         { try encryptString($0, keys: keys) },
            expMonth:       try c.expMonth.map       { try encryptString($0, keys: keys) },
            expYear:        try c.expYear.map        { try encryptString($0, keys: keys) },
            code:           try c.code.map           { try encryptString($0, keys: keys) }
        )
    }

    // MARK: - Private: Identity reverse map

    private func toRawIdentity(_ c: DraftIdentityContent, keys: CryptoKeys) throws -> RawIdentityData {
        func enc(_ s: String?) throws -> String? { try s.map { try encryptString($0, keys: keys) } }
        return RawIdentityData(
            title:          try enc(c.title),
            firstName:      try enc(c.firstName),
            middleName:     try enc(c.middleName),
            lastName:       try enc(c.lastName),
            address1:       try enc(c.address1),
            address2:       try enc(c.address2),
            address3:       try enc(c.address3),
            city:           try enc(c.city),
            state:          try enc(c.state),
            postalCode:     try enc(c.postalCode),
            country:        try enc(c.country),
            company:        try enc(c.company),
            email:          try enc(c.email),
            phone:          try enc(c.phone),
            ssn:            try enc(c.ssn),
            username:       try enc(c.username),
            passportNumber: try enc(c.passportNumber),
            licenseNumber:  try enc(c.licenseNumber)
        )
    }

    // MARK: - Private: SSH Key reverse map

    /// Reverse map for an SSH key item.
    ///
    /// `keyFingerprint` is **client-derived** — whichever Bitwarden client created the item computed
    /// it and encrypted it, and the server stores the resulting `EncString` opaquely. It has no vault
    /// key, so it cannot derive or restore one. Omitting the field here therefore does not leave it
    /// to the server; it **erases it on every save**. This used to send `nil` with a comment claiming
    /// the opposite, and the erase happened on any edit at all — changing a note was enough.
    ///
    /// **Known limitation.** The fingerprint is round-tripped, not recomputed, so replacing the key
    /// material in the edit form leaves the stored fingerprint describing the *previous* key. That is
    /// a stale verification aid rather than a corruption: the key still works, and any client that
    /// does derive the value corrects it on its next save. Recomputing needs SSH public-key wire
    /// format parsing and is deliberately not part of this fix — see
    /// `openspec/changes/ssh-key-fingerprint-preservation/`.
    private func toRawSSHKey(_ c: DraftSSHKeyContent, keys: CryptoKeys) throws -> RawSSHKeyData {
        RawSSHKeyData(
            privateKey:     try c.privateKey.map  { try encryptString($0, keys: keys) },
            publicKey:      try c.publicKey.map   { try encryptString($0, keys: keys) },
            keyFingerprint: try c.keyFingerprint.map { try encryptString($0, keys: keys) }
        )
    }

    // MARK: - Private: Custom fields reverse map

    private func toRawFields(_ fields: [DraftCustomField], keys: CryptoKeys) throws -> [RawField] {
        try fields.map { f in
            RawField(
                type:     f.type.rawValue,
                name:     try encryptString(f.name, keys: keys),
                value:    try f.value.map { try encryptString($0, keys: keys) },
                linkedId: f.linkedId?.rawValue
            )
        }
    }

    // MARK: - Private: Custom field extractor

    private func customFieldsOf(_ content: DraftItemContent) -> [DraftCustomField] {
        switch content {
        case .login(let c):      return c.customFields
        case .secureNote(let c): return c.customFields
        case .card(let c):       return c.customFields
        case .identity(let c):   return c.customFields
        case .sshKey(let c):     return c.customFields
        }
    }

    // MARK: - Encrypt helper

    /// Encrypts a plaintext string as a Type-2 EncString and returns its wire representation.
    private func encryptString(_ plaintext: String, keys: CryptoKeys) throws -> String {
        guard let data = plaintext.data(using: .utf8) else {
            throw CipherMapperError.fieldDecryptionFailed("utf8-encode")
        }
        return try EncString.encrypt(data: data, keys: keys).toString()
    }

    // MARK: - Decrypt helpers

    /// Decrypts an EncString field that is expected to be present.
    private func decryptRequired(_ encStr: String, field: String, keys: CryptoKeys) throws -> String {
        do {
            let enc  = try EncString(string: encStr)
            let data = try enc.decrypt(keys: keys)
            guard let str = String(data: data, encoding: .utf8) else {
                throw CipherMapperError.fieldDecryptionFailed(field)
            }
            return str
        } catch let e as EncStringError {
            throw e
        } catch {
            Self.logger.error("Field decryption failed: \(field, privacy: .public)")
            throw CipherMapperError.fieldDecryptionFailed(field)
        }
    }
}
