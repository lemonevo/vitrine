import LocalAuthentication
import XCTest
@testable import Prizm

/// Tests for `BiometricKeychainServiceImpl`.
///
/// Biometric Keychain operations in `.systemEnforced` mode require a
/// `.biometryCurrentSet` access control, which cannot be exercised here (no enrolled
/// biometrics, and no `keychain-access-groups` entitlement on an ad-hoc signed build).
/// These tests therefore run in `.appEnforced` mode with a no-op policy evaluator,
/// which exercises every SecItem code path without the biometric gate.
@MainActor
final class BiometricKeychainServiceTests: XCTestCase {

    private var sut: BiometricKeychainServiceImpl!
    private var evaluator: NoopBiometricPolicyEvaluator!
    private let testKey = "bw.macos.test:biometricKey"

    override func setUp() async throws {
        try await super.setUp()
        evaluator = NoopBiometricPolicyEvaluator()
        sut = BiometricKeychainServiceImpl(mode: .appEnforced, evaluator: evaluator)
        try? sut.deleteBiometric(key: testKey)
    }

    override func tearDown() async throws {
        try? sut.deleteBiometric(key: testKey)
        try await super.tearDown()
    }

    // MARK: - Mode

    /// The mode has to be observable: Settings reports which layer enforces the gate.
    func testModeIsReported() {
        XCTAssertFalse(sut.isSystemEnforced, "constructed with .appEnforced")
        let strong = BiometricKeychainServiceImpl(mode: .systemEnforced, evaluator: evaluator)
        XCTAssertTrue(strong.isSystemEnforced)
    }

    /// `preferred()` must never pick a mode the build cannot use. On this machine the
    /// probe answers for real, so the assertion is written against the probe itself.
    func testPreferredModeMatchesCapabilityProbe() {
        XCTAssertEqual(
            BiometricKeychainServiceImpl.preferred().isSystemEnforced,
            BiometricKeychainServiceImpl.systemEnforcementAvailable
        )
    }

    // MARK: - Gate

    /// Every read must go through the policy evaluator — that evaluation *is* the gate
    /// in `.appEnforced` mode.
    func testReadEvaluatesPolicy() async throws {
        try sut.writeBiometric(data: Data(count: 64), key: testKey)
        _ = try await sut.readBiometric(key: testKey)
        XCTAssertEqual(evaluator.evaluateCallCount, 1)
        // The prompt is the system's own and appears over whatever app the user was in, so the line
        // has to say who is asking.
        XCTAssertNotNil(evaluator.lastReason?.range(of: "Prizm"))
    }

    /// The prompt line names the sensor, so the button on the unlock card and the dialog agree about
    /// what is being offered. Which sensor exists is the machine's business, so only the shape is
    /// asserted here.
    func testPromptReasonNamesASensor() {
        let reason = BiometricKeychainServiceImpl.promptReason
        XCTAssertTrue(reason.hasPrefix("Open your Prizm vault with "), reason)
        XCTAssertFalse(reason.hasSuffix(" "), "\(reason) names no sensor")
    }

    /// A refused evaluation must surface, not fall through to the stored bytes.
    func testReadSurfacesEvaluationFailure() async throws {
        try sut.writeBiometric(data: Data(count: 64), key: testKey)
        evaluator.error = LAError(.userCancel)
        do {
            _ = try await sut.readBiometric(key: testKey)
            XCTFail("Expected the evaluation failure to propagate")
        } catch {
            XCTAssertEqual((error as? LAError)?.code, .userCancel)
        }
    }

    // MARK: - Write + Read

    func testWriteAndReadRoundTrip() async throws {
        let data = Data(repeating: 0xAB, count: 64)
        try sut.writeBiometric(data: data, key: testKey)
        let result = try await sut.readBiometric(key: testKey)
        XCTAssertEqual(result, data)
    }

    func testOverwriteReplacesValue() async throws {
        let first = Data(repeating: 0x01, count: 64)
        let second = Data(repeating: 0x02, count: 64)
        try sut.writeBiometric(data: first, key: testKey)
        try sut.writeBiometric(data: second, key: testKey)
        let result = try await sut.readBiometric(key: testKey)
        XCTAssertEqual(result, second)
    }

    // MARK: - Delete

    func testDeleteRemovesItem() async throws {
        try sut.writeBiometric(data: Data(count: 64), key: testKey)
        try sut.deleteBiometric(key: testKey)
        do {
            _ = try await sut.readBiometric(key: testKey)
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func testDeleteNonExistentItemDoesNotThrow() {
        XCTAssertNoThrow(try sut.deleteBiometric(key: "bw.macos.test:nonexistent"))
    }

    // MARK: - Not found

    func testReadMissingKeyThrowsNotFound() async {
        do {
            _ = try await sut.readBiometric(key: "bw.macos.test:missing")
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }
}
