import Foundation

// MARK: - Reading an export back
//
// Kept separate from `VaultExportDocument.swift` so that "what the format is" and "how to read it
// back" can be read independently. The writing side is a projection of the entities; this side is
// a projection *into* them, and the two have different failure modes.

nonisolated extension VaultExportDocument {

    // MARK: - Decoding

    /// Decodes a file, refusing anything that is not an unencrypted Bitwarden export.
    ///
    /// The probe runs before the typed decode so the three refusals can be told apart. A single
    /// `try? decode(...)` would collapse "this is not JSON", "this is JSON but not an export" and
    /// "this is an encrypted export" into one unhelpful message, and an encrypted export is
    /// exactly the case where the user needs to be told what is wrong — the file *is* a real
    /// export, just not one Prizm can read.
    static func decode(from data: Data) throws -> VaultExportDocument {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VaultExportDocumentError.notAnUnencryptedExport
        }

        // Checked before the `items` presence test: an encrypted export has an `items` array too,
        // and reporting "not an export" for it would be false.
        if let encrypted = object["encrypted"] as? Bool, encrypted {
            throw VaultExportDocumentError.encryptedExportUnsupported
        }

        guard object["items"] is [Any] else {
            throw VaultExportDocumentError.notAnUnencryptedExport
        }

        do {
            return try JSONDecoder().decode(VaultExportDocument.self, from: data)
        } catch {
            throw VaultExportDocumentError.malformedExport
        }
    }

    // MARK: - Folders

    /// Maps each folder id in the file to the name it carries.
    ///
    /// This is the only thing that makes an item's `folderId` resolvable: the id is file-local and
    /// means nothing on this server, so the *name* is what has to survive the round trip.
    var folderNamesById: [String: String] {
        var map: [String: String] = [:]
        for folder in folders where !folder.id.isEmpty {
            map[folder.id] = folder.name
        }
        return map
    }

    /// The folder names this document refers to, deduplicated case-insensitively, first-seen
    /// order preserved.
    ///
    /// Only folders an item actually points at are listed. An empty folder in the file is not
    /// worth creating: the user asked to import their items, and inventing empty folders is a
    /// side effect they did not ask for.
    var referencedFolderNames: [String] {
        let namesById = folderNamesById
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            guard let folderId = item.folderId,
                  let name = namesById[folderId],
                  !name.isEmpty
            else { continue }
            let key = name.lowercased()
            if seen.insert(key).inserted { result.append(name) }
        }
        return result
    }

    // MARK: - Items

    /// Builds a draft for one item in the file.
    ///
    /// - Parameters:
    ///   - item: the item to convert.
    ///   - folderIdsByName: a folder name (lowercased) mapped to a folder id **on this server**.
    ///     An item whose folder is absent from the map is imported unfoldered rather than dropped.
    ///   - now: the creation and revision instants for the new draft. Injected so tests are
    ///     deterministic.
    ///
    /// - Throws: `VaultExportDocumentError.unsupportedItemType` for a type integer outside 1–5,
    ///   `missingItemName` for an item with a blank name.
    ///
    /// **What is deliberately dropped.** `organizationId` and `collectionIds` are not carried
    /// over. The user may not belong to that organisation on this server, and writing an item into
    /// a collection the account cannot see would create an item invisible in every client —
    /// including the one that just imported it. `ImportVaultUseCase` reports that this happened
    /// rather than doing it silently.
    ///
    /// **What is deliberately not preserved.** `preserved` is `.empty`: a new cipher has no
    /// per-item key, no passkeys and no password history of its own, exactly as with a duplicate.
    /// `id` is not carried either — the server assigns it.
    ///
    /// A missing type payload degrades to an empty one rather than failing the item, matching the
    /// reference implementation's `toView`, which only maps a payload when it is non-null.
    func makeDraft(from item: ExportItem,
                   folderIdsByName: [String: String],
                   now: Date) throws -> DraftVaultItem {

        guard let exportType = ExportItemType(rawValue: item.type) else {
            throw VaultExportDocumentError.unsupportedItemType(item.type)
        }
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultExportDocumentError.missingItemName
        }

        let fields = (item.fields ?? []).compactMap(Self.makeField)

        let content: DraftItemContent
        switch exportType {
        case .login:
            let login = item.login ?? ExportLogin(uris: nil, username: nil, password: nil, totp: nil)
            content = .login(DraftLoginContent(LoginContent(
                username:     login.username,
                password:     login.password,
                uris:         (login.uris ?? []).map {
                    // Every integer names something: a value this build does not know becomes
                    // `.unknown(raw)` and is written back unchanged. It used to degrade to `nil` —
                    // "use the default strategy" — which quietly rewrote a strategy the file had
                    // recorded.
                    LoginURI(uri: $0.uri, matchType: $0.match.map(URIMatchType.init))
                },
                totp:         login.totp,
                notes:        item.notes,
                customFields: fields
            )))

        case .secureNote:
            // An absent payload is Generic, which is also what the server sends for notes that
            // predate the field.
            content = .secureNote(DraftSecureNoteContent(SecureNoteContent(
                notes:        item.notes,
                customFields: fields,
                subtype:      SecureNoteSubtype(rawValue: item.secureNote?.type ?? 0)
            )))

        case .card:
            let card = item.card ?? ExportCard(
                cardholderName: nil, brand: nil, number: nil,
                expMonth: nil, expYear: nil, code: nil
            )
            content = .card(DraftCardContent(CardContent(
                cardholderName: card.cardholderName,
                brand:          card.brand,
                number:         card.number,
                expMonth:       card.expMonth,
                expYear:        card.expYear,
                code:           card.code,
                notes:          item.notes,
                customFields: fields
            )))

        case .identity:
            let id = item.identity ?? ExportIdentity(
                title: nil, firstName: nil, middleName: nil, lastName: nil,
                address1: nil, address2: nil, address3: nil, city: nil, state: nil,
                postalCode: nil, country: nil, company: nil, email: nil, phone: nil,
                ssn: nil, username: nil, passportNumber: nil, licenseNumber: nil
            )
            content = .identity(DraftIdentityContent(IdentityContent(
                title:          id.title,
                firstName:      id.firstName,
                middleName:     id.middleName,
                lastName:       id.lastName,
                address1:       id.address1,
                address2:       id.address2,
                address3:       id.address3,
                city:           id.city,
                state:          id.state,
                postalCode:     id.postalCode,
                country:        id.country,
                company:        id.company,
                email:          id.email,
                phone:          id.phone,
                ssn:            id.ssn,
                username:       id.username,
                passportNumber: id.passportNumber,
                licenseNumber:  id.licenseNumber,
                notes:          item.notes,
                customFields: fields
            )))

        case .sshKey:
            let ssh = item.sshKey ?? ExportSSHKey(privateKey: nil, publicKey: nil, keyFingerprint: nil)
            content = .sshKey(DraftSSHKeyContent(SSHKeyContent(
                privateKey:     ssh.privateKey,
                publicKey:      ssh.publicKey,
                keyFingerprint: ssh.keyFingerprint,
                notes:          item.notes,
                customFields: fields
            )))
        }

        return DraftVaultItem(
            id:             UUID().uuidString,
            folderId:       resolveFolderId(for: item, folderIdsByName: folderIdsByName),
            name:           item.name,
            isFavorite:     item.favorite,
            isDeleted:      false,
            creationDate:   now,
            revisionDate:   now,
            content:        content,
            reprompt:       item.reprompt,
            organizationId: nil,
            collectionIds:  [],
            preserved:      .empty
        )
    }

    /// Resolves an item's folder through the file's folder list and then through this server's
    /// names. Returns `nil` when either hop fails, so an unresolvable folder imports unfoldered.
    private func resolveFolderId(for item: ExportItem,
                                 folderIdsByName: [String: String]) -> String? {
        guard let fileFolderId = item.folderId,
              let name = folderNamesById[fileFolderId]
        else { return nil }
        return folderIdsByName[name.lowercased()]
    }

    /// Converts a field, dropping the ones that cannot be represented.
    ///
    /// A field with a blank name is dropped: `CipherMapper` skips unnamed fields on the way out,
    /// so such a field would be silently discarded on the first save anyway. Dropping it at import
    /// means the count the user is shown matches what actually lands in the vault.
    private static func makeField(_ field: ExportCustomField) -> CustomField? {
        guard !field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let type = CustomFieldType(rawValue: field.type) ?? .text
        let linkedId = type == .linked ? field.linkedId.flatMap(LinkedFieldId.init) : nil
        return CustomField(name: field.name, value: field.value, type: type, linkedId: linkedId)
    }
}
