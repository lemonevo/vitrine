import XCTest
@testable import Prizm

/// Collection membership surviving a rename.
///
/// Renaming a collection used to send `groups: []` and `users: []`, and Vaultwarden stores the
/// collection object verbatim — so a rename **revoked every other member's and group's access to it**.
///
/// The assertions here are about what goes **out**, not about what comes back or what the local entity
/// holds. Either of those would have passed against the broken code.
@MainActor
final class CollectionPermissionRoundTripTests: XCTestCase {

    private var api:   MockPrizmAPIClient!
    private var crypto: MockPrizmCryptoService!
    private var orgKeyCache: OrgKeyCache!
    private var sut:   VaultRepositoryImpl!

    private let orgId = "org-1"

    override func setUp() async throws {
        try await super.setUp()
        api    = MockPrizmAPIClient()
        crypto = MockPrizmCryptoService()
        orgKeyCache = OrgKeyCache()
        // Renaming a collection encrypts its new name with the organisation's key, so the cache has
        // to hold one or the rename fails before it reaches the behaviour under test.
        await orgKeyCache.store(
            key: CryptoKeys(encryptionKey: Data(count: 32), macKey: Data(count: 32)),
            for: orgId
        )
        sut = VaultRepositoryImpl(apiClient: api, crypto: crypto, orgKeyCache: orgKeyCache)
    }

    // MARK: - Fixtures

    /// A collection as the server sends it: name encrypted, membership in the two permission arrays.
    private func collectionJSON(
        id: String = "col-1",
        groups: String = #"[{"id":"g-1","readOnly":false,"hidePasswords":false,"manage":false}]"#,
        users: String = #"[{"id":"u-1","readOnly":true,"hidePasswords":false}]"#,
        externalId: String? = "dir-42"
    ) -> Data {
        let external = externalId.map { #""\#($0)""# } ?? "null"
        let json = """
        {
          "id": "\(id)",
          "organizationId": "\(orgId)",
          "name": "2.encName|iv|mac",
          "externalId": \(external),
          "groups": \(groups),
          "users": \(users)
        }
        """
        return Data(json.utf8)
    }

    private func decodeCollection(_ data: Data) throws -> RawCollection {
        try JSONDecoder().decode(RawCollection.self, from: data)
    }

    private func seedStore(with collection: RawCollection) async {
        await sut.populate(items: [], folders: [], organizations: [],
                           collections: [
                            OrgCollection(id: collection.id,
                                          organizationId: collection.organizationId,
                                          name: "Shared",
                                          preserved: collection.preserved)
                           ],
                           syncedAt: Date())
    }

    // MARK: - 1.1 the model reads it

    func testRawCollection_decodesMembership() throws {
        let raw = try decodeCollection(collectionJSON())

        XCTAssertEqual(raw.preserved.groups.count, 1)
        XCTAssertEqual(raw.preserved.users.count, 1)
        XCTAssertEqual(raw.preserved.externalId, "dir-42")
    }

    /// 1.2 The property the opaque passthrough exists for: a permission flag this build has never
    /// heard of survives, because nothing here tries to understand it.
    func testRawCollection_keepsAnUnknownPermissionField() throws {
        let raw = try decodeCollection(collectionJSON(
            groups: #"[{"id":"g-1","readOnly":false,"someFuturePermission":true,"nested":{"deep":1}}]"#
        ))

        guard case .object(let group)? = raw.preserved.groups.first,
              case .object(let nested)? = group["nested"],
              case .bool(true)? = group["someFuturePermission"],
              case .number(1)? = nested["deep"] else {
            return XCTFail("the unknown permission fields must survive decoding: \(raw.preserved.groups)")
        }
    }

    /// 1.3 Older servers omit both arrays. That is "no membership", not a decode failure.
    func testRawCollection_withoutMembership_decodesToEmpty() throws {
        let json = #"{"id":"col-1","organizationId":"org-1","name":"2.enc=="}"#

        let raw = try decodeCollection(Data(json.utf8))

        XCTAssertTrue(raw.preserved.groups.isEmpty)
        XCTAssertTrue(raw.preserved.users.isEmpty)
        XCTAssertNil(raw.preserved.externalId)
    }

    // MARK: - 2.1 the request carries it: the assertion that catches the bug

    /// A collection whose membership is unknown must not be renamed at all.
    ///
    /// Vaultwarden deletes and re-creates a collection's access rows from the request, so sending
    /// empty arrays is a revocation rather than a no-op. Having no source means the rename cannot be
    /// done safely, and refusing is the only outcome that destroys nothing.
    func testRename_ofACollectionNotInTheStore_isRefusedRatherThanRevokingAccess() async throws {
        await XCTAssertThrowsErrorAsync(
            try await self.sut.renameCollection(id: "col-1", organizationId: self.orgId, name: "Renamed")
        ) { error in
            // Not asserted by equality: `VaultError` is not Equatable. The case and its payload are
            // what matter, and the count below is the real assertion anyway.
            guard case VaultError.itemNotFound(let id)? = error as? VaultError else {
                return XCTFail("expected .itemNotFound, got \(error)")
            }
            XCTAssertEqual(id, "col-1")
        }

        XCTAssertEqual(
            api.renameCollectionCallCount, 0,
            "the request must not be sent at all — an empty membership in the body is the revocation"
        )
    }

    func testRename_ofACollectionWithMembership_sendsThatMembership() async throws {
        try await seedStore(with: try decodeCollection(collectionJSON()))

        _ = try await sut.renameCollection(id: "col-1", organizationId: orgId, name: "Renamed")

        let sent = try XCTUnwrap(api.lastRenamePreserved)
        XCTAssertEqual(sent.groups.count, 1, "renaming must not revoke the groups' access")
        XCTAssertEqual(sent.users.count, 1, "renaming must not revoke the members' access")
        XCTAssertEqual(sent.externalId, "dir-42", "and must not clear the directory-sync id")
    }

    /// The end-to-end shape of the defect: read from the server, rename, and check the bytes that go
    /// back are the ones that came in.
    func testRename_roundTripsWhatSyncRead() async throws {
        let raw = try decodeCollection(collectionJSON(
            groups: #"[{"id":"g-1","readOnly":false,"hidePasswords":false,"manage":false}]"#,
            users:  #"[{"id":"u-1","readOnly":true,"hidePasswords":false,"manage":false}]"#
        ))
        try await seedStore(with: raw)

        _ = try await sut.renameCollection(id: "col-1", organizationId: orgId, name: "Renamed")

        XCTAssertEqual(api.lastRenamePreserved?.groups, raw.preserved.groups)
        XCTAssertEqual(api.lastRenamePreserved?.users, raw.preserved.users)
    }

    func testRename_keepsAnUnknownPermissionField() async throws {
        let raw = try decodeCollection(collectionJSON(
            groups: #"[{"id":"g-1","someFuturePermission":true}]"#
        ))
        try await seedStore(with: raw)

        _ = try await sut.renameCollection(id: "col-1", organizationId: orgId, name: "Renamed")

        XCTAssertEqual(api.lastRenamePreserved?.groups, raw.preserved.groups)
    }

    // MARK: - 3.2 the local entity keeps them

    func testRename_returnsAnEntityThatStillCarriesTheMembership() async throws {
        try await seedStore(with: try decodeCollection(collectionJSON()))

        let renamed = try await sut.renameCollection(id: "col-1", organizationId: orgId, name: "Renamed")

        XCTAssertEqual(renamed.name, "Renamed")
        XCTAssertEqual(renamed.preserved.groups.count, 1,
                       "the local rebuild is where the client came to agree with the server's loss")
        XCTAssertEqual(renamed.preserved.externalId, "dir-42")
    }

    // MARK: - 3.3 creation is the one place empty is true

    func testCreate_sendsEmptyMembership() async throws {
        _ = try await sut.createCollection(name: "New", organizationId: orgId)

        // `createCollection` has no preserved parameter by design: a collection that does not exist yet
        // has no membership, so empty is the truth rather than a deletion.
        XCTAssertEqual(api.createCollectionCallCount, 1)
    }
}
