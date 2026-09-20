import XCTest
@testable import Prizm

// MARK: - PasswordHistoryViewModelTests

/// Tests for the lifecycle of the decrypted history: when it exists, and when it does not.
///
/// The property that matters is the second one. `clear()` is what makes "the plaintext is never
/// retained" a statement about the code rather than an intention, so it is asserted directly
/// instead of being assumed from the fact that a section was collapsed.
@MainActor
final class PasswordHistoryViewModelTests: XCTestCase {

    private var useCase: StubPasswordHistoryUseCase!
    private var sut: PasswordHistoryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        useCase = StubPasswordHistoryUseCase()
        sut     = PasswordHistoryViewModel(itemId: "item-1", useCase: useCase)
    }

    func test_initialState_isIdleWithNoCount() {
        guard case .idle = sut.state else {
            return XCTFail("Expected .idle, got \(sut.state)")
        }
        // nil, not 0: a badge reading "0" before the section has ever been opened is a claim about
        // the item that has not been checked yet.
        XCTAssertNil(sut.entryCount)
    }

    func test_load_publishesTheEntries() async {
        useCase.entries = [
            PasswordHistoryEntry(password: "newer", lastUsedDate: nil),
            PasswordHistoryEntry(password: "older", lastUsedDate: nil)
        ]

        await sut.load()

        guard case .loaded(let entries) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(entries.map(\.password), ["newer", "older"])
        XCTAssertEqual(sut.entryCount, 2)
    }

    /// The order is the server's and is preserved, not recomputed — see the use case for why.
    func test_load_preservesServerOrder() async {
        useCase.entries = [
            PasswordHistoryEntry(password: "first",  lastUsedDate: nil),
            PasswordHistoryEntry(password: "second", lastUsedDate: nil)
        ]

        await sut.load()

        guard case .loaded(let entries) = sut.state else { return XCTFail("Expected .loaded") }
        XCTAssertEqual(entries.first?.password, "first")
    }

    func test_load_failure_publishesAMessage() async {
        useCase.error = StubHistoryError.unreadable

        await sut.load()

        guard case .failed(let message) = sut.state else {
            return XCTFail("Expected .failed, got \(sut.state)")
        }
        XCTAssertTrue(message.contains("history is unreadable"),
                      "The message should carry the reason, got: \(message)")
        XCTAssertNil(sut.entryCount)
    }

    /// Collapsing discards the plaintext, and re-expanding reads it again rather than showing what
    /// was left over from last time.
    func test_clear_dropsTheEntriesAndAllowsAReRead() async {
        useCase.entries = [PasswordHistoryEntry(password: "old", lastUsedDate: nil)]

        await sut.load()
        guard case .loaded = sut.state else { return XCTFail("precondition: should be loaded") }

        sut.clear()
        guard case .idle = sut.state else {
            return XCTFail("Expected .idle after clear, got \(sut.state)")
        }
        XCTAssertNil(sut.entryCount)

        useCase.entries = [PasswordHistoryEntry(password: "changed", lastUsedDate: nil)]
        await sut.load()

        guard case .loaded(let entries) = sut.state else { return XCTFail("Expected .loaded") }
        XCTAssertEqual(entries.map(\.password), ["changed"])
        XCTAssertEqual(useCase.callCount, 2)
    }

    /// A load already in flight or already done is not repeated. The section's onChange is the only
    /// caller, and it can fire more than once for a single expand.
    func test_load_isIdempotentWhileLoaded() async {
        await sut.load()
        await sut.load()

        XCTAssertEqual(useCase.callCount, 1)
    }
}

// MARK: - Doubles

private enum StubHistoryError: LocalizedError {
    case unreadable

    var errorDescription: String? { "history is unreadable" }
}

private final class StubPasswordHistoryUseCase: GetPasswordHistoryUseCase, @unchecked Sendable {
    var entries: [PasswordHistoryEntry] = []
    var error: Error?
    private(set) var callCount = 0

    func execute(itemId: String) async throws -> [PasswordHistoryEntry] {
        callCount += 1
        if let error { throw error }
        return entries
    }
}
