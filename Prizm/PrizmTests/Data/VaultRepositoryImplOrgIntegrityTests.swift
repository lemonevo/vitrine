import XCTest
@testable import Prizm

// MARK: - VaultRepositoryImplOrgIntegrityTests

/// Regression tests for the cache patches and the encryption-key selection in
/// `VaultRepositoryImpl` (openspec change `critical-integrity-fixes`, task 3.6).
///
/// **Defect under test.** Seven places patch the in-memory vault cache by rebuilding a
/// `VaultItem` from its parts. The original hand-written memberwise rebuilds listed only the
/// fields the patch intended to change, so `organizationId` and `collectionIds` were reset to
/// their defaults. The damage is not merely cosmetic: once `organizationId` is nil, the next
/// `update` selects the *personal* vault key and re-encrypts an organisation cipher with it,
/// producing an item no other org member — and no other Bitwarden client — can read.
///
/// Covers:
///   - `deleteFolder` clears `folderId` without touching org membership
///   - `moveItemToFolder` / `moveItemsToFolder` keep org membership
///   - `deleteItem` / `restoreItem` / `updateAttachments` keep org membership and `preserved`
///   - an org draft with no unwrapped org key is refused, with no network request made
///   - a personal draft never requires an org key (control — guards against over-correction)
@MainActor
final class VaultRepositoryImplOrgIntegrityTests: XCTestCase {

    private var sut: VaultRepositoryImpl!
    private var mockAPI: MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var orgKeyCache: OrgKeyCache!

    private let orgId = "org-1"
    private let collectionId = "col-1"
    private let folderId = "folder-1"

    /// Distinguishable key material: if the wrong key is selected the round trip fails loudly
    /// rather than silently succeeding with identical bytes.
    private let vaultKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0xAA, count: 32),
        macKey:        Data(repeating: 0xBB, count: 32)
    )
    private let orgKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0x11, count: 32),
        macKey:        Data(repeating: 0x22, count: 32)
    )

    override func setUp() async throws {
        try await super.setUp()
        mockAPI     = MockPrizmAPIClient()
        mockCrypto  = MockPrizmCryptoService()
        orgKeyCache = OrgKeyCache()
        mockCrypto.stubbedVaultKeys = vaultKeys
        await mockCrypto.unlockWith(keys: vaultKeys)
        sut = VaultRepositoryImpl(apiClient: mockAPI, crypto: mockCrypto, orgKeyCache: orgKeyCache)
    }

    // MARK: - Helpers

    /// A non-empty `PreservedCipherFields` that needs no key unwrapping, so it can be used on
    /// every cache-patch test without pulling the per-item-key path in as a confounder.
    /// (The per-item key path is covered in `CipherWireIntegrityTests`.)
    private var samplePreserved: PreservedCipherFields {
        PreservedCipherFields(
            passwordHistory: [.string("2.oldPassword==")],
            archivedDate: "2026-01-01T00:00:00.000Z",
            cipherKey: nil,
            fido2Credentials: [.object([
                "credentialId": .string("cred-1"),
                "discoverable": .bool(true),
                "counter":      .string("0"),
            ])],
            passwordRevisionDate: "2026-01-02T00:00:00.000Z",
            autofillOnPageLoad: true
        )
    }

    private func makeLogin(
        id: String = UUID().uuidString,
        name: String,
        folderId: String? = nil,
        organizationId: String? = nil,
        collectionIds: [String] = [],
        isDeleted: Bool = false,
        preserved: PreservedCipherFields = .empty
    ) -> VaultItem {
        VaultItem(
            id: id,
            name: name,
            isFavorite: false,
            isDeleted: isDeleted,
            creationDate: Date(),
            revisionDate: Date(),
            content: .login(LoginContent(
                username: "user@example.com", password: "s3cret", uris: [],
                totp: nil, notes: nil, customFields: []
            )),
            folderId: folderId,
            organizationId: organizationId,
            collectionIds: collectionIds,
            preserved: preserved
        )
    }

    private func makeOrgLogin(
        id: String = UUID().uuidString,
        name: String,
        folderId: String? = nil,
        isDeleted: Bool = false,
        preserved: PreservedCipherFields = .empty
    ) -> VaultItem {
        makeLogin(id: id, name: name, folderId: folderId,
                  organizationId: orgId, collectionIds: [collectionId],
                  isDeleted: isDeleted, preserved: preserved)
    }

    /// Asserts the item still belongs to `orgId`/`collectionId` and says which mutation broke it.
    private func assertOrgMembershipIntact(id: String, after operation: String,
                                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let item = try await sut.itemDetail(id: id)
        XCTAssertEqual(item.organizationId, orgId,
                       "\(operation) dropped organizationId — the next save would re-encrypt this item with the personal vault key",
                       file: file, line: line)
        XCTAssertEqual(item.collectionIds, [collectionId],
                       "\(operation) dropped collectionIds",
                       file: file, line: line)
    }

    private func seed(folder: Folder? = nil, items: [VaultItem]) async {
        await sut.populate(items: items,
                           folders: folder.map { [$0] } ?? [],
                           organizations: [],
                           collections: [OrgCollection(id: collectionId, organizationId: orgId, name: "Team")],
                           syncedAt: Date())
    }

    // MARK: - deleteFolder

    func testDeleteFolder_personalItemInFolder_clearsFolderId() async throws {
        let folder = Folder(id: folderId, name: "Work")
        let item = makeLogin(id: "personal-1", name: "Personal", folderId: folderId)
        await seed(folder: folder, items: [item])

        try await sut.deleteFolder(id: folderId)

        let updated = try await sut.itemDetail(id: "personal-1")
        XCTAssertNil(updated.folderId, "Item should be unfolded when its folder is deleted")
    }

    func testDeleteFolder_orgItemInFolder_keepsOrganizationAndCollections() async throws {
        // Org items are not filed into personal folders in normal use, but the unfold loop
        // matches on `folderId` alone, so this state is reachable and must not corrupt the item.
        let folder = Folder(id: folderId, name: "Work")
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login", folderId: folderId)
        await seed(folder: folder, items: [item])

        try await sut.deleteFolder(id: folderId)

        let updated = try await sut.itemDetail(id: "org-1-item")
        XCTAssertNil(updated.folderId, "Folder reference should still be cleared")
        try await assertOrgMembershipIntact(id: "org-1-item", after: "deleteFolder")
    }

    // MARK: - moveItemToFolder

    func testMoveItemToFolder_orgItem_keepsOrganizationAndCollections() async throws {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login")
        await seed(folder: Folder(id: folderId, name: "Work"), items: [item])

        try await sut.moveItemToFolder(itemId: "org-1-item", folderId: folderId)

        let updated = try await sut.itemDetail(id: "org-1-item")
        XCTAssertEqual(updated.folderId, folderId, "Move should be reflected in the cache")
        try await assertOrgMembershipIntact(id: "org-1-item", after: "moveItemToFolder")
    }

    func testMoveItemToFolder_orgItem_keepsPreservedFields() async throws {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login", preserved: samplePreserved)
        await seed(items: [item])

        try await sut.moveItemToFolder(itemId: "org-1-item", folderId: folderId)

        let updated = try await sut.itemDetail(id: "org-1-item")
        XCTAssertEqual(updated.preserved, samplePreserved,
                       "A folder move must not drop passkeys / password history")
    }

    func testMoveItemsToFolder_orgItems_keepOrganizationAndCollections() async throws {
        let a = makeOrgLogin(id: "org-a", name: "A")
        let b = makeOrgLogin(id: "org-b", name: "B")
        let personal = makeLogin(id: "personal-1", name: "Personal")
        await seed(items: [a, b, personal])

        try await sut.moveItemsToFolder(itemIds: ["org-a", "org-b"], folderId: folderId)

        for id in ["org-a", "org-b"] {
            let updated = try await sut.itemDetail(id: id)
            XCTAssertEqual(updated.folderId, folderId)
            try await assertOrgMembershipIntact(id: id, after: "moveItemsToFolder")
        }
        // The untouched item must not be dragged along by the bulk patch.
        let untouched = try await sut.itemDetail(id: "personal-1")
        XCTAssertNil(untouched.folderId, "Bulk move must only affect the requested ids")
    }

    // MARK: - deleteItem / restoreItem / updateAttachments

    func testDeleteItem_orgItem_keepsOrganizationAndCollections() async throws {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login", preserved: samplePreserved)
        await seed(items: [item])

        try await sut.deleteItem(id: "org-1-item")

        let trashed = try await sut.items(for: .trash)
        XCTAssertEqual(trashed.count, 1)
        try await assertOrgMembershipIntact(id: "org-1-item", after: "deleteItem")
        XCTAssertEqual(trashed[0].preserved, samplePreserved,
                       "Trashing must not drop preserved wire fields")
    }

    func testRestoreItem_orgItem_keepsPreservedFieldsAndOrgMembership() async throws {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login",
                                isDeleted: true, preserved: samplePreserved)
        await seed(items: [item])

        try await sut.restoreItem(id: "org-1-item")

        let restored = try await sut.itemDetail(id: "org-1-item")
        XCTAssertFalse(restored.isDeleted)
        XCTAssertEqual(restored.preserved, samplePreserved,
                       "Restoring from Trash must not drop passkeys / password history")
        try await assertOrgMembershipIntact(id: "org-1-item", after: "restoreItem")
    }

    func testUpdateAttachments_orgItem_keepsPreservedFieldsAndOrgMembership() async throws {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login", preserved: samplePreserved)
        await seed(items: [item])

        let attachment = Attachment(
            id: "att-1", fileName: "notes.pdf", encryptedKey: "2.attKey==",
            size: 1024, sizeName: "1 KB", url: nil, isUploadIncomplete: false
        )
        await sut.updateAttachments([attachment], for: "org-1-item")

        let updated = try await sut.itemDetail(id: "org-1-item")
        XCTAssertEqual(updated.attachments.map(\.id), ["att-1"])
        XCTAssertEqual(updated.preserved, samplePreserved,
                       "An attachment refresh must not drop preserved wire fields")
        try await assertOrgMembershipIntact(id: "org-1-item", after: "updateAttachments")
    }

    // MARK: - Encryption key selection (refuses to write under the wrong key)

    func testUpdate_orgDraftWithoutOrgKey_throwsAndMakesNoRequest() async throws {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login")
        await seed(items: [item])
        // Deliberately do NOT store an org key — simulates a sync that has not unwrapped it yet.
        var draft = DraftVaultItem(item)
        draft.name = "Renamed"

        do {
            _ = try await sut.update(draft)
            XCTFail("Expected the write to be refused when the org key is missing")
        } catch let error as VaultError {
            guard case .decryptionFailed(let message) = error else {
                return XCTFail("Expected .decryptionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains(orgId),
                          "Error should name the org so the failure is diagnosable — got: \(message)")
        }

        XCTAssertEqual(mockAPI.updateCipherCallCount, 0,
                       "No cipher may be written when the correct key is unavailable")
        XCTAssertEqual(mockAPI.updateCipherCollectionsCallCount, 0)
    }

    func testCreate_orgDraftWithoutOrgKey_throwsAndMakesNoRequest() async throws {
        let draft = DraftVaultItem.blank(type: .login).with(organizationId: orgId,
                                                            collectionIds: [collectionId])

        do {
            _ = try await sut.create(draft)
            XCTFail("Expected the create to be refused when the org key is missing")
        } catch let error as VaultError {
            guard case .decryptionFailed(_) = error else {
                return XCTFail("Expected .decryptionFailed, got \(error)")
            }
        }

        XCTAssertEqual(mockAPI.createOrgCipherCallCount, 0)
        XCTAssertEqual(mockAPI.createCipherCallCount, 0,
                       "An org draft must never fall back to the personal create endpoint")
    }

    func testUpdate_orgDraftWithOrgKey_succeeds() async throws {
        await orgKeyCache.store(key: orgKeys, for: orgId)
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login")
        await seed(items: [item])
        var draft = DraftVaultItem(item)
        draft.name = "Renamed"

        let updated = try await sut.update(draft)

        XCTAssertEqual(mockAPI.updateCipherCallCount, 1)
        XCTAssertEqual(updated.name, "Renamed", "Org cipher should round-trip through the org key")
        XCTAssertEqual(updated.organizationId, orgId)
        XCTAssertEqual(updated.collectionIds, [collectionId])
    }

    func testUpdate_personalDraft_doesNotRequireOrgKey() async throws {
        let item = makeLogin(id: "personal-1", name: "Personal")
        await seed(items: [item])
        var draft = DraftVaultItem(item)
        draft.name = "Renamed"

        let updated = try await sut.update(draft)

        XCTAssertEqual(mockAPI.updateCipherCallCount, 1,
                       "A personal item must still save when no org key is loaded")
        XCTAssertEqual(updated.name, "Renamed")
        XCTAssertNil(updated.organizationId)
    }

    // MARK: - Cache-patch helper coverage

    func testWith_folderIdSomeNil_clearsFolderButKeepsEverythingElse() {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login",
                                folderId: folderId, preserved: samplePreserved)

        let cleared = item.with(folderId: .some(nil))

        XCTAssertNil(cleared.folderId)
        XCTAssertEqual(cleared.organizationId, orgId)
        XCTAssertEqual(cleared.collectionIds, [collectionId])
        XCTAssertEqual(cleared.preserved, samplePreserved)
        XCTAssertEqual(cleared.name, item.name)
    }

    func testWith_omittingFolderId_keepsExistingFolder() {
        let item = makeOrgLogin(id: "org-1-item", name: "Org Login", folderId: folderId)

        let renamed = item.with(name: "New name")

        XCTAssertEqual(renamed.folderId, folderId,
                       "A nil argument means 'leave alone', not 'clear'")
        XCTAssertEqual(renamed.name, "New name")
    }
}

// MARK: - DraftVaultItem test helper

private extension DraftVaultItem {
    /// Returns a copy of the draft assigned to an organization, for create-path tests.
    func with(organizationId: String, collectionIds: [String]) -> DraftVaultItem {
        var copy = self
        copy.organizationId = organizationId
        copy.collectionIds = collectionIds
        return copy
    }
}
