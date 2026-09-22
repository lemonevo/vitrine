import XCTest
@testable import Prizm

/// What `SyncResult.failedDecryptionCount` counts.
///
/// It is the number the sidebar reports, so an under-count would be a visible lie about the vault
/// being complete. Personal and organisation ciphers are counted by different code paths — the
/// personal pass skips org ciphers outright (`PrizmCryptoService.decryptList`), and the org pass
/// counts its own failures into a local variable — so the two have to be brought together, and there
/// is nothing in either path that would notice if they were not.
@MainActor
final class SyncRepositoryUnreadableCountTests: XCTestCase {

    private var sut: SyncRepositoryImpl!
    private var mockAPI: MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var mockVault: MockVaultRepository!

    private let testUserId = "11111111-2222-3333-4444-555555555555"
    private let serverURL  = URL(string: "https://vault.example.com")!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI    = MockPrizmAPIClient()
        mockCrypto = MockPrizmCryptoService()
        mockVault  = MockVaultRepository()
        mockAPI.baseURL = serverURL
        sut = SyncRepositoryImpl(
            apiClient:       mockAPI,
            crypto:          mockCrypto,
            vaultRepository: mockVault,
            vaultKeyCache:   VaultKeyCache(),
            orgKeyCache:     OrgKeyCache(),
            vaultCache:      MockVaultCacheStore(),
            currentUserId:   { [testUserId] in testUserId }
        )
    }

    // MARK: - Fixtures

    /// The key `MockPrizmCryptoService.unwrapOrgKey` hands back for every organisation, so a fixture
    /// can produce a name the org pass will genuinely decrypt.
    private let orgStubKey = CryptoKeys(
        encryptionKey: Data(count: 32), macKey: Data(count: 32)
    )

    /// A name encrypted with the stubbed org key.
    ///
    /// Without this the fixtures carried a fake EncString, which failed to decrypt for a reason that
    /// had nothing to do with what the test was about — so "not counted" and "counted" were both
    /// being demonstrated by the same accident.
    private func orgReadableName(_ text: String) throws -> String {
        try EncString.encrypt(data: Data(text.utf8), keys: orgStubKey).toString()
    }

    private func cipher(
        id: String,
        organizationId: String? = nil,
        type: Int = 2,
        name: String? = nil
    ) -> RawCipher {
        RawCipher(
            id: id, organizationId: organizationId, folderId: nil, type: type,
            name: name ?? "2.name\(id)==", notes: nil, favorite: false, reprompt: nil,
            deletedDate: nil, creationDate: nil, revisionDate: nil,
            login: nil, card: nil, identity: nil, secureNote: nil, sshKey: nil,
            fields: [], key: nil, collectionIds: [], attachments: nil
        )
    }

    private func response(
        ciphers: [RawCipher],
        organizations: [RawOrganization] = []
    ) -> SyncResponse {
        SyncResponse(
            profile: RawProfile(
                id: "profile-id", email: "alice@example.com", name: nil,
                key: "2.encKey==",
                // Required for the org block to run at all.
                privateKey: organizations.isEmpty ? nil : "2.encPrivKey=="
            ),
            ciphers: ciphers,
            folders: [],
            organizations: organizations,
            collections: []
        )
    }

    private func vaultItem(id: String) -> VaultItem {
        VaultItem(
            id: id, name: "Item \(id)", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
    }

    // MARK: - 1.1 organisation failures are reported

    /// The org cipher names an organisation the response does not describe, so its key is not in the
    /// snapshot and the mapper skips it — the shape of a failed org-key unwrap. The count used to
    /// reach only a log line.
    func testSync_unreadableOrgCipher_isIncludedInTheCount() async throws {
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(count: 32), macKey: Data(count: 32)
        ))
        mockCrypto.stubbedDecryptList = []
        // The item itself is perfectly readable; only its organisation's key is missing. So the
        // count is following the key failure, not a broken fixture.
        mockAPI.syncResponse = response(
            ciphers: [cipher(id: "org-1", organizationId: "org-unknown",
                             name: try orgReadableName("Org Item"))],
            organizations: [RawOrganization(id: "org-known", name: "Acme", key: "2.k==", type: 3)]
        )

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(
            result.failedDecryptionCount, 1,
            "an unreadable organisation item is an item the user cannot see"
        )
    }

    // MARK: - 1.2 the two counts are summed

    func testSync_unreadablePersonalAndOrgCiphers_areSummed() async throws {
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(count: 32), macKey: Data(count: 32)
        ))
        // Two personal ciphers the crypto service reports as failed.
        mockCrypto.stubbedFailedCount = 2
        mockCrypto.stubbedDecryptList = [vaultItem(id: "p-1")]
        mockAPI.syncResponse = response(
            ciphers: [
                cipher(id: "p-1"), cipher(id: "p-2"), cipher(id: "p-3"),
                cipher(id: "org-1", organizationId: "org-unknown",
                       name: try orgReadableName("Org Item"))
            ],
            organizations: [RawOrganization(id: "org-known", name: "Acme", key: "2.k==", type: 3)]
        )

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(
            result.failedDecryptionCount, 3,
            "2 personal + 1 organisation — reporting either half alone under-counts"
        )
    }

    // MARK: - 1.3 a clean sync reports zero

    /// The regression guard: a count that is never zero would be worse than none, because the
    /// sidebar would report a problem that does not exist.
    func testSync_noFailures_reportsZero() async throws {
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(count: 32), macKey: Data(count: 32)
        ))
        mockCrypto.stubbedFailedCount = 0
        mockCrypto.stubbedDecryptList = [vaultItem(id: "p-1")]
        mockAPI.syncResponse = response(ciphers: [cipher(id: "p-1")])

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(result.failedDecryptionCount, 0)
    }

    /// An organisation the response *does* describe unwraps successfully, so nothing is counted —
    /// proving the count follows the failure rather than merely the presence of an org cipher.
    func testSync_readableOrgCipher_isNotCounted() async throws {
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(count: 32), macKey: Data(count: 32)
        ))
        mockCrypto.stubbedDecryptList = []
        mockAPI.syncResponse = response(
            ciphers: [cipher(id: "org-1", organizationId: "org-known",
                             name: try orgReadableName("Org Item"))],
            organizations: [RawOrganization(id: "org-known", name: "Acme", key: "2.k==", type: 3)]
        )

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(result.failedDecryptionCount, 0)
    }
}
