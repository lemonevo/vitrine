import XCTest
@testable import Prizm

/// `VaultCacheStoreImpl` against a real temporary directory.
///
/// The store's whole contract is about files, so these tests use files. The only thing stubbed is
/// the root: each test gets its own directory, so nothing here can see or damage a real vault.
@MainActor
final class VaultCacheStoreImplTests: XCTestCase {

    private var root: URL!
    private var sut: VaultCacheStoreImpl!

    private let userId = "11111111-2222-3333-4444-555555555555"
    private let otherUserId = "99999999-8888-7777-6666-555555555555"
    private let serverURL = URL(string: "https://vault.example.com")!
    private let otherServerURL = URL(string: "https://other.example.com")!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prizm-cache-tests-\(UUID().uuidString)", isDirectory: true)
        sut = VaultCacheStoreImpl(directory: root)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try await super.tearDown()
    }

    private func identity(_ userId: String? = nil, server: URL? = nil) -> VaultCacheIdentity {
        VaultCacheIdentity(userId: userId ?? self.userId, serverURL: server ?? serverURL)
    }

    private func payload(_ text: String, writtenAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> VaultCachePayload {
        VaultCachePayload(body: Data(text.utf8), writtenAt: writtenAt)
    }

    private func accountDirectory(_ userId: String? = nil) -> URL {
        root.appendingPathComponent(userId ?? self.userId, isDirectory: true)
    }

    // MARK: - 2.1.1 round trip

    func testWriteThenRead_returnsTheSameBytesAndTime() async throws {
        let written = payload(#"{"ciphers":[{"id":"c1"}]}"#)
        await sut.write(identity: identity(), payload: written)

        let read = await sut.read(identity: identity())

        XCTAssertEqual(read, written, "A payload must round-trip unchanged — bytes and timestamp")
    }

    // MARK: - 2.1.2 account isolation

    func testRead_otherUser_doesNotSeeThisUsersCache() async throws {
        await sut.write(identity: identity(), payload: payload(#"{"mine":true}"#))

        let other = await sut.read(identity: identity(otherUserId))

        XCTAssertNil(other, "One account must never be served another account's vault")
    }

    // MARK: - 2.1.3 a body with no metadata is not a cache

    func testRead_bodyWithoutMetadata_isTreatedAsAbsent() async throws {
        await sut.write(identity: identity(), payload: payload(#"{"mine":true}"#))
        // Simulate a write interrupted between the two renames: the body landed, the metadata did not.
        try FileManager.default.removeItem(
            at: accountDirectory().appendingPathComponent("sync.meta.json")
        )

        let read = await sut.read(identity: identity())

        XCTAssertNil(read, "Metadata is the commit record; without it the payload cannot be trusted")
    }

    // MARK: - 2.1.4 unknown schema version

    func testRead_unknownSchemaVersion_isTreatedAsAbsent() async throws {
        await sut.write(identity: identity(), payload: payload(#"{"mine":true}"#))
        let metadataURL = accountDirectory().appendingPathComponent("sync.meta.json")
        let bumped = """
        {"schemaVersion":\(VaultCacheStoreImpl.schemaVersion + 1),"writtenAt":1700000000.0,"serverURL":"\(serverURL.absoluteString)"}
        """
        try Data(bumped.utf8).write(to: metadataURL, options: [.atomic])

        let read = await sut.read(identity: identity())

        XCTAssertNil(read, "A format this reader does not know must read as absent, not be misparsed")
    }

    // MARK: - 2.1.5 corrupt body

    func testRead_corruptBody_isReturnedOnlyAsBytesAndDecidesNothing() async throws {
        await sut.write(identity: identity(), payload: payload("not json at all"))
        let metadataURL = accountDirectory().appendingPathComponent("sync.meta.json")
        let metadata = try XCTUnwrap(try? Data(contentsOf: metadataURL))
        XCTAssertFalse(metadata.isEmpty)

        // The store's job is to hand back what is on disk; whether it decodes is the caller's
        // question, and the caller's answer is "treat it as no cache" (see the sync tests).
        let read = await sut.read(identity: identity())

        XCTAssertEqual(read?.body, Data("not json at all".utf8))
    }

    // MARK: - 2.1.6 delete

    func testDelete_removesBothFilesAndIsIdempotent() async throws {
        await sut.write(identity: identity(), payload: payload(#"{"mine":true}"#))
        let directory = accountDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        await sut.delete(userId: userId)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.path),
            "The signed-out account's cached vault must be gone, not merely unreadable"
        )

        // Idempotent: a second sign-out, or a sign-out with nothing cached, must not fault.
        await sut.delete(userId: userId)
        await sut.delete(userId: otherUserId)
    }

    /// The store refuses user ids that would escape the cache root or address another account.
    /// The id comes from the server, so it is untrusted input used as a path component.
    func testWrite_traversalUserId_isRefused() async throws {
        for bad in ["../escape", "..", ".", "", "a/b", "user id"] {
            await sut.write(identity: identity(bad), payload: payload(#"{"mine":true}"#))
        }

        let escaped = FileManager.default.temporaryDirectory.appendingPathComponent("escape")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertTrue(entries.isEmpty, "No directory may be created for an unusable user id; found \(entries)")
    }

    // MARK: - 2.1.7 a failed write leaves the previous cache intact

    /// A write that cannot happen must leave the last good copy alone, because the alternative is
    /// that a transient disk problem destroys the only offline copy the user has.
    ///
    /// The failure is induced by making the account directory unwritable, so the atomic write's
    /// temporary file cannot be created at all — which is the one failure shape that leaves the
    /// existing files untouched, and the one the two-file ordering is designed around.
    func testWrite_whenDiskRefuses_leavesPreviousCacheReadable() async throws {
        let first = payload(#"{"generation":1}"#, writtenAt: Date(timeIntervalSince1970: 1_600_000_000))
        await sut.write(identity: identity(), payload: first)
        let before = await sut.read(identity: identity())
        XCTAssertEqual(before, first)

        let directory = accountDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        // Must not throw and must not take the previous payload with it.
        await sut.write(identity: identity(), payload: payload(#"{"generation":2}"#))

        let after = await sut.read(identity: identity())
        XCTAssertEqual(
            after, first,
            "A write that could not complete must leave the previous cache as it was"
        )
    }

    // MARK: - 2.1.8 permissions

    func testWrite_restrictsBothFilesToOwner() async throws {
        await sut.write(identity: identity(), payload: payload(#"{"mine":true}"#))

        for name in ["sync.json", "sync.meta.json"] {
            let url = accountDirectory().appendingPathComponent(name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(
                permissions.intValue & 0o777, 0o600,
                "\(name) holds the user's whole vault (as ciphertext) and must be owner-only"
            )
        }
    }

    // MARK: - Server scoping

    /// The same user id on a different server is a different vault.
    func testRead_differentServer_isTreatedAsAbsent() async throws {
        await sut.write(identity: identity(), payload: payload(#"{"mine":true}"#))

        let read = await sut.read(identity: identity(server: otherServerURL))

        XCTAssertNil(read, "A payload written for another server must not be served as this account's")
    }
}
