import XCTest
@testable import Prizm

/// The vault cache as `SyncRepositoryImpl` uses it: what it writes, when it reads, and — the part
/// that carries the risk — when it must not.
@MainActor
final class SyncRepositoryVaultCacheTests: XCTestCase {

    private var sut: SyncRepositoryImpl!
    private var mockAPI: MockPrizmAPIClient!
    private var mockCrypto: MockPrizmCryptoService!
    private var mockVault: MockVaultRepository!
    private var mockVaultCache: MockVaultCacheStore!

    private let testUserId = "11111111-2222-3333-4444-555555555555"
    private let serverURL = URL(string: "https://vault.example.com")!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI        = MockPrizmAPIClient()
        mockCrypto     = MockPrizmCryptoService()
        mockVault      = MockVaultRepository()
        mockVaultCache = MockVaultCacheStore()
        mockAPI.baseURL = serverURL
        sut = SyncRepositoryImpl(
            apiClient:       mockAPI,
            crypto:          mockCrypto,
            vaultRepository: mockVault,
            vaultKeyCache:   VaultKeyCache(),
            orgKeyCache:     OrgKeyCache(),
            vaultCache:      mockVaultCache,
            currentUserId:   { [testUserId] in testUserId }
        )
    }

    // MARK: - Fixtures

    /// A `/api/sync` body with `cipherCount` secure notes.
    ///
    /// Written as JSON rather than built from `SyncResponse` on purpose: the cache stores bytes, and
    /// a test that produced those bytes by encoding the model would be unable to tell a real payload
    /// from a re-encoded one.
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

    private func makeVaultItem(id: String = UUID().uuidString) -> VaultItem {
        VaultItem(
            id:           id,
            name:         "Cached Item",
            isFavorite:   false,
            isDeleted:    false,
            creationDate: Date(),
            revisionDate: Date(),
            content:      .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )
    }

    private func cachedPayload(cipherCount: Int, writtenAt: Date) -> VaultCachePayload {
        VaultCachePayload(body: syncJSON(cipherCount: cipherCount), writtenAt: writtenAt)
    }

    // MARK: - 3.1 A successful sync persists the payload

    func testSync_serverSourced_persistsBodyForTheSignedInUser() async throws {
        let body = syncJSON(cipherCount: 2)
        mockAPI.syncPayloadBody       = body
        mockCrypto.stubbedDecryptList = [makeVaultItem(), makeVaultItem()]

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(result.source, .server)
        XCTAssertEqual(mockVaultCache.writeCallCount, 1, "A live sync must cache what it fetched")
        let write = try XCTUnwrap(mockVaultCache.writes.first)
        XCTAssertEqual(write.identity.userId, testUserId)
        XCTAssertEqual(write.payload.body, body, "The bytes stored must be the bytes received")
    }

    // MARK: - 3.3 The write records the server and a time

    func testSync_serverSourced_recordsServerURLAndWriteTime() async throws {
        mockAPI.syncPayloadBody       = syncJSON(cipherCount: 0)
        mockCrypto.stubbedDecryptList = []

        let before = Date()
        let result = try await sut.sync(progress: { _ in })

        let write = try XCTUnwrap(mockVaultCache.writes.first)
        XCTAssertEqual(write.identity.serverURL, serverURL)
        XCTAssertGreaterThanOrEqual(write.payload.writtenAt, before)
        XCTAssertLessThanOrEqual(write.payload.writtenAt, result.syncedAt)
    }

    // MARK: - 3.2 A failed sync leaves the cache alone

    /// The regression that would cost the user their offline copy: writing on the failure path, or
    /// writing a partially-populated payload because decryption was incomplete.
    func testSync_transportFailureWithoutCache_writesNothing() async throws {
        mockAPI.syncShouldThrow = URLError(.notConnectedToInternet)

        await XCTAssertThrowsErrorAsync(try await sut.sync(progress: { _ in }))

        XCTAssertEqual(
            mockVaultCache.writeCallCount, 0,
            "A sync that failed must not overwrite the cache with what it did not fetch"
        )
    }

    /// Same rule when the failure happens after a usable cache was found and served.
    func testSync_cacheSourced_doesNotRewriteTheCache() async throws {
        let cached = cachedPayload(cipherCount: 1, writtenAt: Date(timeIntervalSince1970: 1_600_000_000))
        mockVaultCache.stubbedRead     = cached
        mockAPI.syncShouldThrow        = URLError(.notConnectedToInternet)
        mockCrypto.stubbedDecryptList  = [makeVaultItem()]

        _ = try await sut.sync(progress: { _ in })

        XCTAssertEqual(
            mockVaultCache.writeCallCount, 0,
            "Reading the cache must not write it back with a fresh timestamp"
        )
    }

    // MARK: - 4.1.1 Transport failure + cache → populated from the cache

    func testSync_transportFailure_withCache_populatesFromCache() async throws {
        let writtenAt = Date(timeIntervalSince1970: 1_600_000_000)
        mockVaultCache.stubbedRead    = cachedPayload(cipherCount: 1, writtenAt: writtenAt)
        mockAPI.syncShouldThrow       = URLError(.notConnectedToInternet)
        mockCrypto.stubbedDecryptList = [makeVaultItem(id: "cached-1")]

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(result.source, .cache)
        XCTAssertEqual(result.payloadTimestamp, writtenAt, "The result must carry the payload's age, not now")
        XCTAssertEqual(result.totalCiphers, 1)
        XCTAssertEqual(mockVault.populatedItems.map(\.id), ["cached-1"])
    }

    // MARK: - 4.1.2 DNS / refused connection + cache → same

    func testSync_serverUnreachable_withCache_populatesFromCache() async throws {
        mockVaultCache.stubbedRead    = cachedPayload(cipherCount: 0, writtenAt: Date())
        mockAPI.syncShouldThrow       = URLError(.cannotFindHost)
        mockCrypto.stubbedDecryptList = []

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(result.source, .cache)
    }

    // MARK: - 4.1.3 A rejected session is not hidden

    func testSync_unauthorized_withCache_throwsAndServesNothing() async throws {
        mockVaultCache.stubbedRead      = cachedPayload(cipherCount: 1, writtenAt: Date())
        mockAPI.syncShouldThrow         = APIError.httpError(statusCode: 401, body: "")
        mockCrypto.stubbedDecryptList   = [makeVaultItem()]

        await XCTAssertThrowsErrorAsync(try await sut.sync(progress: { _ in })) { error in
            XCTAssertEqual(error as? SyncError, .unauthorized)
        }

        XCTAssertEqual(mockVaultCache.readCallCount, 0, "A rejection must not even look at the cache")
        XCTAssertTrue(mockVault.populatedItems.isEmpty, "Stale data must not mask an expired session")
    }

    // MARK: - 4.1.4 A decryption failure is not masked

    func testSync_decodingFailed_withCache_throwsAndServesNothing() async throws {
        mockVaultCache.stubbedRead    = cachedPayload(cipherCount: 1, writtenAt: Date())
        mockAPI.syncShouldThrow       = APIError.decodingFailed
        mockCrypto.stubbedDecryptList = [makeVaultItem()]

        await XCTAssertThrowsErrorAsync(try await sut.sync(progress: { _ in }))

        XCTAssertEqual(mockVaultCache.readCallCount, 0)
        XCTAssertTrue(mockVault.populatedItems.isEmpty)
    }

    /// A 5xx is the server saying it cannot serve the vault — indistinguishable from an outage to
    /// the user, and therefore the case the cache exists for.
    func testSync_serverError_withCache_fallsBackToCache() async throws {
        mockVaultCache.stubbedRead    = cachedPayload(cipherCount: 0, writtenAt: Date())
        mockAPI.syncShouldThrow       = APIError.httpError(statusCode: 503, body: "")
        mockCrypto.stubbedDecryptList = []

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(result.source, .cache)
    }

    /// A 4xx is the server saying something about *this request*, so the cache is not the answer.
    func testSync_clientError_withCache_throwsAndServesNothing() async throws {
        mockVaultCache.stubbedRead    = cachedPayload(cipherCount: 1, writtenAt: Date())
        mockAPI.syncShouldThrow       = APIError.httpError(statusCode: 403, body: "")
        mockCrypto.stubbedDecryptList = [makeVaultItem()]

        await XCTAssertThrowsErrorAsync(try await sut.sync(progress: { _ in }))

        XCTAssertEqual(mockVaultCache.readCallCount, 0)
    }

    // MARK: - 4.1.5 No cache → the network error, never an empty vault

    /// The highest-stakes test in the change. An unlocked-but-empty vault is indistinguishable from
    /// "all my items are gone", and it invites the user to act on that belief.
    func testSync_transportFailure_withoutCache_throwsAndLeavesVaultEmpty() async throws {
        mockVaultCache.stubbedRead = nil
        mockAPI.syncShouldThrow    = URLError(.notConnectedToInternet)

        await XCTAssertThrowsErrorAsync(try await sut.sync(progress: { _ in })) { error in
            XCTAssertEqual(
                error as? SyncError, .networkUnavailable,
                "The user must be told the server could not be reached"
            )
        }

        XCTAssertEqual(mockVaultCache.readCallCount, 1, "The cache must have been consulted before giving up")
        XCTAssertEqual(mockVault.populateCallCount, 0, "Nothing may be published as the vault's contents")
        XCTAssertTrue(mockVault.populatedItems.isEmpty)
    }

    // MARK: - 4.1.6 Unreadable cache degrades to no cache

    func testSync_transportFailure_withUndecodableCache_throwsTheNetworkError() async throws {
        mockVaultCache.stubbedRead = VaultCachePayload(body: Data("not json".utf8), writtenAt: Date())
        mockAPI.syncShouldThrow    = URLError(.notConnectedToInternet)

        await XCTAssertThrowsErrorAsync(try await sut.sync(progress: { _ in })) { error in
            XCTAssertEqual(
                error as? SyncError, .networkUnavailable,
                "A corrupt cache must not replace the network failure with a decoding failure"
            )
        }

        XCTAssertEqual(mockVault.populateCallCount, 0)
    }

    // MARK: - 4.1.6 A cache from another server is not this account's vault

    func testSync_transportFailure_cacheFromAnotherServer_throws() async throws {
        // The store is what compares the server URL; the mock stands in for "the store said no".
        mockVaultCache.stubbedRead = nil
        mockAPI.baseURL            = URL(string: "https://other.example.com")!
        mockAPI.syncShouldThrow    = URLError(.notConnectedToInternet)

        await XCTAssertThrowsErrorAsync(try await sut.sync(progress: { _ in }))

        XCTAssertEqual(mockVault.populateCallCount, 0)
    }

    // MARK: - 4.2 A refresh failure is a transport failure, not a rejection

    /// The distinction the design calls out as the one a plausible implementation gets wrong: when
    /// the access token has expired and the server cannot be reached to refresh it, the sync must
    /// see "nobody answered" rather than "the server said no", or the cache is refused in exactly
    /// the situation it was built for.
    func testSync_refreshUnreachable_thenCacheIsUsed() async throws {
        let writtenAt = Date(timeIntervalSince1970: 1_600_000_000)
        mockVaultCache.stubbedRead    = cachedPayload(cipherCount: 0, writtenAt: writtenAt)
        // A refresh that could not reach the server surfaces as a transport error; the token is
        // left as it was, and the sync request then fails the same way.
        mockAPI.refreshShouldThrow    = URLError(.notConnectedToInternet)
        mockAPI.syncShouldThrow       = URLError(.notConnectedToInternet)
        mockCrypto.stubbedDecryptList = []

        await XCTAssertThrowsErrorAsync(try await mockAPI.refreshAccessToken(refreshToken: "stale"))

        let result = try await sut.sync(progress: { _ in })

        XCTAssertEqual(
            result.source, .cache,
            "An unreachable refresh must not be collapsed into an unauthorized answer"
        )
    }
}
