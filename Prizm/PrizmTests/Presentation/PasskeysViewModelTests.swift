import XCTest
@testable import Prizm

// MARK: - PasskeysViewModelTests

/// The lifecycle of the decrypted credentials: when they exist, and when they do not.
///
/// Same shape as `PasswordHistoryViewModelTests`, and the same reason for `clear()` being asserted
/// directly: the spec asks that decrypted passkey fields not be retained, and a view model that held
/// them after the section closed would satisfy every other test while breaking that.
@MainActor
final class PasskeysViewModelTests: XCTestCase {

    private var useCase: StubPasskeysUseCase!
    private var sut: PasskeysViewModel!

    override func setUp() async throws {
        try await super.setUp()
        useCase = StubPasskeysUseCase()
        sut     = PasskeysViewModel(itemId: "item-1", useCase: useCase)
    }

    private func credential(_ rpId: String) -> PasskeyCredential {
        PasskeyCredential(rpId: rpId, rpName: nil, userName: nil,
                          userDisplayName: nil, creationDate: nil)
    }

    func test_initialState_isIdleWithNoCount() {
        guard case .idle = sut.state else {
            return XCTFail("Expected .idle, got \(sut.state)")
        }
        // nil, not 0 — a badge reading "0" describes an item that has not been looked at yet.
        XCTAssertNil(sut.credentialCount)
    }

    func test_load_publishesTheCredentials() async {
        useCase.credentials = [credential("a.example"), credential("b.example")]

        await sut.load()

        guard case .loaded(let credentials) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(credentials.map(\.rpId), ["a.example", "b.example"])
        XCTAssertEqual(sut.credentialCount, 2)
    }

    /// A failure is shown as a message rather than as an empty list. "Could not be read" and "there
    /// are none" are different claims, and only the second one is about the item.
    func test_load_failure_publishesAMessage() async {
        useCase.error = StubPasskeysError.unreadable

        await sut.load()

        guard case .failed(let message) = sut.state else {
            return XCTFail("Expected .failed, got \(sut.state)")
        }
        XCTAssertTrue(message.contains("credentials are unreadable"),
                      "The message should carry the reason, got: \(message)")
        XCTAssertNil(sut.credentialCount)
    }

    /// Collapsing discards what was read, and re-expanding reads again rather than showing what was
    /// left from last time.
    func test_clear_dropsTheCredentialsAndAllowsAReRead() async {
        useCase.credentials = [credential("first.example")]

        await sut.load()
        guard case .loaded = sut.state else { return XCTFail("precondition: should be loaded") }

        sut.clear()
        guard case .idle = sut.state else {
            return XCTFail("Expected .idle after clear, got \(sut.state)")
        }
        XCTAssertNil(sut.credentialCount)

        useCase.credentials = [credential("changed.example")]
        await sut.load()

        guard case .loaded(let credentials) = sut.state else { return XCTFail("Expected .loaded") }
        XCTAssertEqual(credentials.map(\.rpId), ["changed.example"])
        XCTAssertEqual(useCase.callCount, 2)
    }
}

// MARK: - Doubles

private enum StubPasskeysError: LocalizedError {
    case unreadable

    var errorDescription: String? { "credentials are unreadable" }
}

private final class StubPasskeysUseCase: GetPasskeysUseCase, @unchecked Sendable {
    var credentials: [PasskeyCredential] = []
    var error: Error?
    private(set) var callCount = 0

    func execute(itemId: String) async throws -> [PasskeyCredential] {
        callCount += 1
        if let error { throw error }
        return credentials
    }
}
