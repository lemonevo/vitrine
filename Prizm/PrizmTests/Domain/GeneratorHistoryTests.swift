import XCTest
@testable import Prizm

/// Unit tests for `GeneratorHistory` — the session's bounded, memory-only record of the values the
/// user generated and then actually used.
@MainActor
final class GeneratorHistoryTests: XCTestCase {

    // MARK: - Order

    func testAppend_keepsNewestFirst() {
        let history = GeneratorHistory()
        history.append("first")
        history.append("second")
        history.append("third")

        XCTAssertEqual(history.entries.map(\.value), ["third", "second", "first"])
    }

    func testAppend_recordsTheGenerationTime() {
        let history = GeneratorHistory()
        let when = Date(timeIntervalSince1970: 1_700_000_000)

        history.append("value", at: when)

        XCTAssertEqual(history.entries.first?.generatedAt, when)
    }

    // MARK: - Bounds

    func testAppend_isBoundedAtCapacity() {
        let history = GeneratorHistory()
        for index in 1...25 { history.append("value-\(index)") }

        XCTAssertEqual(history.entries.count, GeneratorHistory.capacity)
        XCTAssertEqual(history.entries.first?.value, "value-25")
        XCTAssertEqual(history.entries.last?.value, "value-6")
        XCTAssertFalse(history.entries.contains { $0.value == "value-5" })
    }

    /// The cap is part of the spec, so changing it should fail a test rather than only a review.
    func testCapacity_isTwenty() {
        XCTAssertEqual(GeneratorHistory.capacity, 20)
    }

    // MARK: - Empty values

    /// An empty value is what a failed generation leaves behind, and there is nothing for the user
    /// to copy back from it.
    func testAppend_ignoresEmptyValues() {
        let history = GeneratorHistory()
        history.append("")
        history.append("real")
        history.append("")

        XCTAssertEqual(history.entries.map(\.value), ["real"])
    }

    // MARK: - Clearing

    func testClear_removesEverything() {
        let history = GeneratorHistory()
        history.append("a")
        history.append("b")

        history.clear()

        XCTAssertTrue(history.entries.isEmpty)
    }

    func testClear_onAnEmptyHistoryIsHarmless() {
        let history = GeneratorHistory()

        history.clear()

        XCTAssertTrue(history.entries.isEmpty)
    }

    // MARK: - Identity

    /// Two generations can legitimately produce the same string. A value-keyed list would collapse
    /// them into one row and silently lose a generation.
    func testEntriesWithTheSameValue_stayDistinct() {
        let history = GeneratorHistory()
        history.append("same")
        history.append("same")

        XCTAssertEqual(history.entries.count, 2)
        XCTAssertNotEqual(history.entries[0].id, history.entries[1].id)
    }
}
