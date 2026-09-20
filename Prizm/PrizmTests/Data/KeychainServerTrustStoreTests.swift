import XCTest
@testable import Prizm

// MARK: - KeychainServerTrustStoreTests

/// The persistence half of server trust: round trip, and scoping to one host.
///
/// These run against `MockKeychainService`, so they prove what is *stored* and under *which key* —
/// not that the Keychain itself enforces `WhenUnlockedThisDeviceOnly`. That property belongs to
/// `KeychainServiceImpl`, which this suite does not reach; see that file for the guarantee.
@MainActor
final class KeychainServerTrustStoreTests: XCTestCase {

    private var keychain: MockKeychainService!
    private var sut:      KeychainServerTrustStore!

    override func setUp() {
        super.setUp()
        keychain = MockKeychainService()
        sut      = KeychainServerTrustStore(keychain: keychain)
    }

    // MARK: - Round trip

    func testSaveThenRead_returnsWhatWasSaved() async throws {
        var configuration = ServerTrustConfiguration.empty
        configuration.trustedCACertificates = [Data([0x30, 0x01]), Data([0x30, 0x02])]
        configuration.pinnedLeafSHA256      = "abc123"
        configuration.pinningEnabled        = true

        try await sut.save(configuration, forHost: "vault.example.com")
        let read = try await sut.configuration(forHost: "vault.example.com")

        XCTAssertEqual(read, configuration)
    }

    func testNothingRecorded_readsAsEmpty() async throws {
        let read = try await sut.configuration(forHost: "vault.example.com")
        XCTAssertEqual(read, .empty)
        XCTAssertTrue(read.isEmpty)
    }

    // MARK: - Scoping

    func testMaterialDoesNotLeakToAnotherHost() async throws {
        var configuration = ServerTrustConfiguration.empty
        configuration.pinningEnabled   = true
        configuration.pinnedLeafSHA256 = "abc123"
        try await sut.save(configuration, forHost: "vault.example.com")

        let other = try await sut.configuration(forHost: "other.example.com")
        XCTAssertEqual(other, .empty,
                       "pointing the app at a different server must not inherit the previous one's trust")
    }

    func testForgettingOneHostLeavesTheOther() async throws {
        try await sut.save(ServerTrustConfiguration.empty, forHost: "a.example.com")
        try await sut.save(ServerTrustConfiguration.empty, forHost: "b.example.com")

        try await sut.removeConfiguration(forHost: "a.example.com")

        let remaining = try await sut.configuration(forHost: "b.example.com")
        XCTAssertEqual(remaining, .empty)
        // The key for b must still exist in the Keychain even though its value equals .empty —
        // that is what distinguishes "configured" from "never touched".
        XCTAssertTrue(keychain.writtenKeys.contains(where: { $0.contains("b.example.com") }),
                      "removing one host must not delete another's entry")
        XCTAssertFalse(keychain.deletedKeys.contains(where: { $0.contains("b.example.com") }))
    }

    func testTheSameHostUnderADifferentSpellingAddressesOneEntry() async throws {
        var configuration = ServerTrustConfiguration.empty
        configuration.pinningEnabled = true
        try await sut.save(configuration, forHost: "Vault.Example.com")

        let read = try await sut.configuration(forHost: "vault.example.com")
        XCTAssertTrue(read.pinningEnabled,
                      "a pin recorded for one spelling must be found by the other, or it is two entries")
    }

    // MARK: - Removal

    func testRemoveConfiguration_clearsWhatWasSaved() async throws {
        var configuration = ServerTrustConfiguration.empty
        configuration.pinnedLeafSHA256 = "abc123"
        try await sut.save(configuration, forHost: "vault.example.com")

        try await sut.removeConfiguration(forHost: "vault.example.com")

        let read = try await sut.configuration(forHost: "vault.example.com")
        XCTAssertEqual(read, .empty)
    }

    // MARK: - Unreadable values

    func testAValueThatCannotBeDecoded_isReportedRatherThanDowngraded() async throws {
        keychain.seed(key: "serverTrust.vault.example.com", data: Data("not json".utf8))

        do {
            _ = try await sut.configuration(forHost: "vault.example.com")
            XCTFail("An unreadable value must not be reported as nothing configured")
        } catch {
            XCTAssertTrue(error is ServerTrustError,
                          "the caller has to be able to tell this apart from a healthy read")
        }
    }

    func testNothingIsWrittenWhenTheFileIsRejected() async throws {
        // The importer's failure path is what this protects: nothing reaches the store, so a
        // rejected file cannot leave a half-written configuration behind.
        let before = keychain.writtenKeys.count
        try await sut.removeConfiguration(forHost: "vault.example.com")
        XCTAssertEqual(keychain.writtenKeys.count, before)
    }
}
