import XCTest
@testable import Prizm

/// `SyncRepositoryImpl` against a session that ends while the sync is in flight.
///
/// This is the half of the lock race the view model cannot fix: the store and the key caches are
/// populated by the repository, before the presentation layer is ever told. A sync that outlives its
/// session must therefore refuse to write, not merely have its result ignored.
@MainActor
final class SyncRepositorySessionEpochTests: XCTestCase {

    private var sut:       SyncRepositoryImpl!
    private var mockAPI:   MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var mockVault: MockVaultRepository!
    private var mockCache: MockVaultCacheStore!
    private var vaultKeyCache: VaultKeyCache!
    private var epoch:         SessionEpoch!

    private let testUserId = "11111111-2222-3333-4444-555555555555"
    private let serverURL  = URL(string: "https://vault.example.com")!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI       = MockPrizmAPIClient()
        mockCrypto    = MockPrizmCryptoService()
        mockVault     = MockVaultRepository()
        mockCache     = MockVaultCacheStore()
        vaultKeyCache = VaultKeyCache()
        epoch         = SessionEpoch()
        mockAPI.baseURL = serverURL
        sut = SyncRepositoryImpl(
            apiClient:       mockAPI,
            crypto:          mockCrypto,
            vaultRepository: mockVault,
            vaultKeyCache:   vaultKeyCache,
            orgKeyCache:     OrgKeyCache(),
            vaultCache:      mockCache,
            sessionEpoch:    epoch,
            currentUserId:   { [testUserId] in testUserId }
        )
    }

    // MARK: - Fixtures

    private func syncJSON(cipherCount: Int) -> Data {
        let ciphers = (0..<cipherCount).map { i in
            #"{"id":"cipher-\#(i)","type":2,"name":"2.name\#(i)==","favorite":false,"collectionIds":[]}"#
        }.joined(separator: ",")
        let json = """
        {
          "profile": {"id":"pid","email":"test@example.com","name":null,"key":"2.k==","privateKey":null},
          "ciphers": [\(ciphers)],
          "folders": []
        }
        """
        return Data(json.utf8)
    }

    /// Wires a fetch that succeeds, with one per-item key so "the key cache was populated" is a
    /// separate observable from "the store was populated".
    private func prepareASuccessfulFetch(cipherCount: Int = 2, delay: TimeInterval = 0.3) async {
        await mockCrypto.unlockWith(keys: CryptoKeys(
            encryptionKey: Data(count: 32), macKey: Data(count: 32)
        ))
        mockCrypto.stubbedDecryptList = (0..<cipherCount).map { i in
            VaultItem(
                id: "cipher-\(i)", name: "Item \(i)", isFavorite: false, isDeleted: false,
                creationDate: .now, revisionDate: .now,
                content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
            )
        }
        mockCrypto.stubbedCipherKeys = ["cipher-0": Data(count: 64)]
        mockAPI.syncPayloadBody = syncJSON(cipherCount: cipherCount)
        mockAPI.syncResponse    = try? JSONDecoder().decode(
            SyncResponse.self, from: syncJSON(cipherCount: cipherCount)
        )
        mockAPI.syncDelay = delay
    }

    private func waitForFetchToStart() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    // MARK: - 4.1 a sync that outlives its session refuses

    func testSync_whenTheSessionEndsMidFlight_throwsSessionEnded() async throws {
        await prepareASuccessfulFetch()

        let sync = Task { try await self.sut.sync(progress: { _ in }) }
        await waitForFetchToStart()
        epoch.advance()   // the vault locks

        do {
            _ = try await sync.value
            XCTFail("Expected the sync to refuse a session that has ended")
        } catch let error as SyncError {
            XCTAssertEqual(
                error, .sessionEnded,
                "a sign-out must not be reported as a network problem"
            )
        }
    }

    /// Asserted on each store rather than on the thrown error: the error being right while a write
    /// slipped through is the failure mode being guarded.
    func testSync_whenTheSessionEndsMidFlight_populatesNothing() async throws {
        await prepareASuccessfulFetch()

        let sync = Task { try await self.sut.sync(progress: { _ in }) }
        await waitForFetchToStart()
        epoch.advance()
        _ = try? await sync.value
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(
            mockVault.populatedItems.isEmpty,
            "the vault store must not be repopulated after the teardown cleared it"
        )
        let cachedKey = await vaultKeyCache.key(for: "cipher-0")
        XCTAssertNil(cachedKey, "key material for a locked session must not be put back")
        XCTAssertEqual(
            mockCache.writeCallCount, 0,
            "nothing may be written for a session that has ended"
        )
    }

    // MARK: - 4.3 a sync within its session is unaffected

    func testSync_whenTheSessionIsStillLive_populatesEverything() async throws {
        await prepareASuccessfulFetch(cipherCount: 3, delay: 0)

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(result.totalCiphers, 3)
        XCTAssertEqual(mockVault.populatedItems.count, 3)
        let cachedKey = await vaultKeyCache.key(for: "cipher-0")
        XCTAssertNotNil(cachedKey)
        XCTAssertEqual(mockCache.writeCallCount, 1, "a live server sync still caches its payload")
    }

    /// The other side of the guard: a session ending *after* a sync finished must not retroactively
    /// invalidate a sync that had already applied itself.
    func testSync_thatCompletesBeforeTheSessionEnds_isApplied() async throws {
        await prepareASuccessfulFetch(delay: 0)

        _ = try await sut.sync(progress: { _ in })
        epoch.advance()

        XCTAssertFalse(mockVault.populatedItems.isEmpty)
        XCTAssertEqual(mockCache.writeCallCount, 1)
    }
}
