import XCTest
import Security
@testable import Prizm

/// Tests for KeychainServiceImpl exercising the real macOS Keychain (integration-level).
///
/// These tests hit the actual Keychain, which makes them the authoritative verification
/// that `kSecUseDataProtectionKeychain` is wired correctly — unit tests using
/// MockKeychainService cannot exercise real Security.framework attributes.
///
/// They run against a dedicated service name (`com.prizm.tests`) rather than
/// `com.prizm`: `KeychainServiceImpl` stores every key in one shared item, so sharing a
/// service with the app would let a test run rewrite the live session.
@MainActor
final class KeychainServiceTests: XCTestCase {

    private var sut: KeychainService!
    private let testService = "com.prizm.tests"
    private let testKey = "bw.macos.test:key"

    override func setUp() async throws {
        try await super.setUp()
        sut = KeychainServiceImpl(service: testService, useDataProtectionKeychain: false)
        // Start from a clean service so item-count assertions are hermetic.
        purgeService()
    }

    override func tearDown() async throws {
        purgeService()
        try await super.tearDown()
    }

    // MARK: - Write + Read

    func testWriteAndReadRoundTrip() throws {
        let data = Data("hello keychain".utf8)
        try sut.write(data: data, key: testKey)
        let result = try sut.read(key: testKey)
        XCTAssertEqual(result, data)
    }

    func testOverwriteReplacesValue() throws {
        try sut.write(data: Data("first".utf8), key: testKey)
        try sut.write(data: Data("second".utf8), key: testKey)
        let result = try sut.read(key: testKey)
        XCTAssertEqual(result, Data("second".utf8))
    }

    /// Keys must be independent of one another: writing one must not disturb another.
    func testKeysAreIndependentWithinTheSharedStore() throws {
        try sut.write(data: Data("one".utf8), key: "bw.macos.test:one")
        try sut.write(data: Data("two".utf8), key: "bw.macos.test:two")

        XCTAssertEqual(try sut.read(key: "bw.macos.test:one"), Data("one".utf8))
        XCTAssertEqual(try sut.read(key: "bw.macos.test:two"), Data("two".utf8))

        try sut.delete(key: "bw.macos.test:one")
        XCTAssertEqual(try sut.read(key: "bw.macos.test:two"), Data("two".utf8))
    }

    /// Values that are not valid UTF-8 (e.g. an encrypted key blob) must survive a round trip.
    func testBinaryValueRoundTrip() throws {
        let data = Data([0x00, 0xFF, 0x10, 0x80, 0x7F])
        try sut.write(data: data, key: testKey)
        XCTAssertEqual(try sut.read(key: testKey), data)
    }

    // MARK: - Delete

    func testDeleteRemovesItem() throws {
        try sut.write(data: Data("value".utf8), key: testKey)
        try sut.delete(key: testKey)
        XCTAssertThrowsError(try sut.read(key: testKey)) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func testDeleteNonExistentItemDoesNotThrow() {
        XCTAssertNoThrow(try sut.delete(key: "bw.macos.test:nonexistent"))
    }

    /// Deleting the last key must remove the backing item entirely, leaving nothing
    /// behind in the keychain after a sign-out.
    func testDeletingLastKeyRemovesBackingItem() throws {
        try sut.write(data: Data("value".utf8), key: testKey)
        try sut.delete(key: testKey)
        XCTAssertEqual(try itemCount(), 0)
    }

    // MARK: - Not found

    func testReadMissingKeyThrowsNotFound() {
        XCTAssertThrowsError(try sut.read(key: "bw.macos.test:missing")) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    // MARK: - Single-item layout

    /// The whole point of the shared store: N logical keys must occupy exactly one
    /// keychain item, because the legacy login keychain prompts once per item.
    func testAllKeysShareExactlyOneItem() throws {
        try sut.write(data: Data("one".utf8), key: "bw.macos.test:one")
        try sut.write(data: Data("two".utf8), key: "bw.macos.test:two")

        XCTAssertEqual(try itemCount(), 1, "expected one keychain item for all keys")
        XCTAssertEqual(
            try storedAccounts(),
            [KeychainServiceImpl.storeAccount],
            "the only item must be the store"
        )
    }

    // MARK: - Entitlement probe (#60)

    /// Regression test for the unsigned-build fallback (#60): an instance created with
    /// the auto-probe must be able to complete a write immediately after init — this is
    /// the operation that gates sign-in (device identifier storage).
    ///
    /// On runners without the `keychain-access-groups` entitlement (CI, Homebrew,
    /// teamless local builds) the probe must select the legacy login keychain; on
    /// entitled builds the data protection keychain is used directly. Either way the
    /// write must succeed. A read-based probe fails this test on unsigned runners:
    /// as of macOS 26.5 `SecItemCopyMatching` returns `errSecItemNotFound` without
    /// the entitlement, while `SecItemAdd` still fails with -34018.
    func testProbedInitCanWriteRegardlessOfEntitlement() throws {
        let probed = KeychainServiceImpl(service: testService)
        let key = "bw.macos.test:probed-write"
        defer { try? probed.delete(key: key) }

        try probed.write(data: Data("probe".utf8), key: key)
        XCTAssertEqual(try probed.read(key: key), Data("probe".utf8))
    }

    // MARK: - Keychain inspection helpers

    /// Deletes every item owned by `testService`, leaving the service untouched.
    private func purgeService() {
        for account in (try? storedAccounts()) ?? [] {
            let query: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: testService,
                kSecAttrAccount: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Number of generic-password items this test service owns.
    ///
    /// Attribute-only queries (`kSecReturnAttributes`, no `kSecReturnData`) never prompt,
    /// which is why this can be called freely.
    private func itemCount() throws -> Int {
        try storedAccounts().count
    }

    /// Account names of every item owned by `testService`.
    private func storedAccounts() throws -> [String] {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      testService,
            kSecMatchLimit:       kSecMatchLimitAll,
            kSecReturnAttributes: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let items = result as? [[CFString: Any]] ?? []
            return items.compactMap { $0[kSecAttrAccount] as? String }.sorted()
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
