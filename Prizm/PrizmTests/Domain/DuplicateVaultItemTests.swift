import XCTest
@testable import Prizm

/// Tests for `DraftVaultItem.duplicate(of:)` and `DuplicateVaultItemUseCaseImpl`.
///
/// Duplicating looks trivial and is not: the draft carries several wire fields that must *not* be
/// copied (a per-item key the original's attachments are wrapped with, a passkey bound to one
/// account, password history, an archive date) alongside fields that must be (folder, organization,
/// collections, reprompt). Each exclusion here corresponds to a way a copy could corrupt the
/// original.
final class DuplicateVaultItemTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeLogin(
        id: String = "id-1",
        name: String = "GitHub",
        isFavorite: Bool = false,
        folderId: String? = nil,
        organizationId: String? = nil,
        collectionIds: [String] = [],
        reprompt: Int = 0,
        preserved: PreservedCipherFields = .empty
    ) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: isFavorite, isDeleted: false,
            creationDate: baseDate, revisionDate: baseDate,
            content: .login(LoginContent(
                username: "octocat", password: "hunter2",
                uris: [LoginURI(uri: "https://github.com", matchType: .defaultMatch)],
                totp: "JBSWY3DPEHPK3PXP", notes: "notes here",
                customFields: [CustomField(name: "env", value: "prod", type: .text, linkedId: nil)]
            )),
            reprompt: reprompt,
            folderId: folderId,
            organizationId: organizationId,
            collectionIds: collectionIds,
            preserved: preserved
        )
    }

    /// A non-empty `PreservedCipherFields` standing in for a cipher that arrived with a per-item
    /// key, passkeys and password history.
    private var populatedPreserved: PreservedCipherFields {
        PreservedCipherFields(
            passwordHistory: [.string("encrypted-history")],
            archivedDate: "2026-01-01T00:00:00.000Z",
            cipherKey: "2.abc|def|ghi",
            fido2Credentials: [.string("passkey")],
            passwordRevisionDate: "2025-12-01T00:00:00.000Z",
            autofillOnPageLoad: true
        )
    }

    // MARK: - Identity and name

    func test_duplicate_assignsANewId() {
        let source = makeLogin(id: "original")
        let draft = DraftVaultItem.duplicate(of: source)

        XCTAssertNotEqual(draft.id, source.id)
        XCTAssertFalse(draft.id.isEmpty)
    }

    func test_duplicate_suffixesTheName() {
        let source = makeLogin(name: "GitHub")
        let draft = DraftVaultItem.duplicate(of: source)

        // `L("%@ (copy)", …)` is asserted structurally rather than by literal text so the test does
        // not break when the interface language changes.
        XCTAssertNotEqual(draft.name, source.name)
        XCTAssertTrue(draft.name.hasPrefix(source.name))
        XCTAssertTrue(draft.name.contains(source.name))
        XCTAssertGreaterThan(draft.name.count, source.name.count)
    }

    func test_duplicate_namesAreDistinguishableForRepeatedCopies() {
        let source = makeLogin(name: "GitHub")
        let first  = DraftVaultItem.duplicate(of: source)
        let second = DraftVaultItem.duplicate(of: VaultItem(first))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.name, second.name, "a copy of a copy must not collide with it")
    }

    // MARK: - Flags and dates

    func test_duplicate_resetsFavorite() {
        let source = makeLogin(isFavorite: true)
        XCTAssertFalse(DraftVaultItem.duplicate(of: source).isFavorite,
                       "favoriting is the user's decision, not a side effect of duplicating")
    }

    func test_duplicate_isNotDeleted() {
        XCTAssertFalse(DraftVaultItem.duplicate(of: makeLogin()).isDeleted)
    }

    /// A copy is a new item, so it must not arrive backdated — otherwise it would sort to the
    /// bottom of a "newest first" list and look lost.
    func test_duplicate_usesFreshDates() {
        let draft = DraftVaultItem.duplicate(of: makeLogin())

        XCTAssertGreaterThan(draft.creationDate, baseDate)
        XCTAssertGreaterThan(draft.revisionDate, baseDate)
        XCTAssertEqual(draft.creationDate, draft.revisionDate)
    }

    // MARK: - Fields that must be preserved

    func test_duplicate_keepsFolderOrganizationAndCollections() {
        let source = makeLogin(folderId: "folder-1", organizationId: "org-1",
                               collectionIds: ["col-1", "col-2"])
        let draft = DraftVaultItem.duplicate(of: source)

        XCTAssertEqual(draft.folderId, "folder-1")
        XCTAssertEqual(draft.organizationId, "org-1")
        XCTAssertEqual(draft.collectionIds, ["col-1", "col-2"])
    }

    func test_duplicate_keepsReprompt() {
        XCTAssertEqual(DraftVaultItem.duplicate(of: makeLogin(reprompt: 1)).reprompt, 1)
    }

    func test_duplicate_copiesTheContentExactly() {
        let source = makeLogin()
        let draft = DraftVaultItem.duplicate(of: source)

        XCTAssertEqual(draft.content, DraftVaultItem(source).content)
        // And it survives the trip back to a `VaultItem`.
        XCTAssertEqual(VaultItem(draft).content, source.content)
    }

    func test_duplicate_preservesContentForEveryItemType() {
        let contents: [ItemContent] = [
            .login(LoginContent(username: "u", password: "p", uris: [], totp: nil, notes: nil, customFields: [])),
            .card(CardContent(cardholderName: "Alice", brand: "Visa", number: "4111",
                              expMonth: "12", expYear: "2030", code: "123",
                              notes: nil, customFields: [])),
            .identity(IdentityContent(title: "Ms", firstName: "Alice", middleName: nil, lastName: "Smith",
                                      address1: nil, address2: nil, address3: nil, city: nil, state: nil,
                                      postalCode: nil, country: nil, company: nil, email: nil, phone: nil,
                                      ssn: nil, username: nil, passportNumber: nil, licenseNumber: nil,
                                      notes: nil, customFields: [])),
            .secureNote(SecureNoteContent(notes: "secret", customFields: [])),
            .sshKey(SSHKeyContent(privateKey: "priv", publicKey: "pub", keyFingerprint: "SHA256:x",
                                  notes: nil, customFields: []))
        ]

        for content in contents {
            let source = VaultItem(
                id: "id", name: "Item", isFavorite: false, isDeleted: false,
                creationDate: baseDate, revisionDate: baseDate, content: content
            )
            XCTAssertEqual(VaultItem(DraftVaultItem.duplicate(of: source)).content, content,
                           "content of \(content) must survive duplication")
        }
    }

    // MARK: - Fields that must NOT be preserved

    /// The whole reason `preserved` is cleared. `cipherKey` is what the *original's* attachments are
    /// wrapped with; sharing it would leave two ciphers claiming the same key, and `fido2Credentials`
    /// would give two ciphers the same passkey.
    func test_duplicate_clearsEveryPreservedField() {
        let draft = DraftVaultItem.duplicate(of: makeLogin(preserved: populatedPreserved))

        XCTAssertEqual(draft.preserved, .empty)
        XCTAssertTrue(draft.preserved.passwordHistory.isEmpty)
        XCTAssertNil(draft.preserved.cipherKey)
        XCTAssertNil(draft.preserved.archivedDate)
        XCTAssertTrue(draft.preserved.fido2Credentials.isEmpty)
        XCTAssertNil(draft.preserved.passwordRevisionDate)
        XCTAssertNil(draft.preserved.autofillOnPageLoad)
    }

    // MARK: - The original is untouched

    func test_duplicate_doesNotModifyTheOriginal() {
        let source = makeLogin(id: "original", name: "GitHub", isFavorite: true,
                               folderId: "folder-1", preserved: populatedPreserved)
        let before = source

        _ = DraftVaultItem.duplicate(of: source)

        XCTAssertEqual(source, before)
        XCTAssertEqual(source.name, "GitHub")
        XCTAssertTrue(source.isFavorite)
        XCTAssertEqual(source.preserved, populatedPreserved)
    }
}

// MARK: - DuplicateVaultItemUseCaseImpl

@MainActor
final class DuplicateVaultItemUseCaseTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut: DuplicateVaultItemUseCaseImpl!

    private let source = VaultItem(
        id: "1", name: "GitHub", isFavorite: true, isDeleted: false,
        creationDate: Date(timeIntervalSince1970: 1_700_000_000),
        revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
        content: .login(LoginContent(username: "octocat", password: "p", uris: [],
                                     totp: nil, notes: nil, customFields: []))
    )

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        sut = DuplicateVaultItemUseCaseImpl(repository: vault)
    }

    override func tearDown() async throws {
        vault = nil
        sut = nil
        try await super.tearDown()
    }

    func test_execute_delegatesToTheRepository() async throws {
        await vault.populate(items: [source], folders: [], organizations: [], collections: [], syncedAt: .now)

        let copy = try await sut.execute(id: "1")

        XCTAssertEqual(vault.duplicateCallCount, 1)
        XCTAssertEqual(vault.lastDuplicatedId, "1")
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertFalse(copy.isFavorite)
    }

    func test_execute_unknownId_throwsItemNotFound() async {
        await vault.populate(items: [], folders: [], organizations: [], collections: [], syncedAt: .now)

        await XCTAssertThrowsErrorAsync(try await sut.execute(id: "missing")) { error in
            guard case VaultError.itemNotFound(let id) = error else {
                return XCTFail("Expected .itemNotFound, got \(error)")
            }
            XCTAssertEqual(id, "missing")
        }
    }

    /// The copy goes through the ordinary create path, so it is encrypted and indexed exactly like
    /// a new item rather than being a second, less-tested write path.
    func test_execute_goesThroughTheCreatePath() async throws {
        await vault.populate(items: [source], folders: [], organizations: [], collections: [], syncedAt: .now)

        _ = try await sut.execute(id: "1")

        XCTAssertNotNil(vault.lastCreatedDraft, "the duplicate must be created through `create`")
        XCTAssertFalse(vault.lastCreatedDraft?.isFavorite ?? true)
    }
}
