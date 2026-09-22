import Foundation
import XCTest
@testable import Prizm

/// The detail pane's "Updated …" half of the metadata line.
///
/// Assertions compare against `absoluteDateString` rather than against literal words on purpose: the
/// relative formatter follows the interface language, which is `zh-Hans` on this machine and `en` on
/// the CI runner. "Is this branch producing an age or a date" is the behaviour under test, and that
/// question survives translation.
@MainActor
final class ItemDetailUpdatedLabelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2026-09-22, fixed
    private let day: TimeInterval = 86_400

    private func daysAgo(_ n: TimeInterval) -> Date { now.addingTimeInterval(-n * day) }

    private func assertAge(_ date: Date, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(ItemDetailView.updatedLabel(for: date, now: now),
                          ItemDetailView.absoluteDateString(date),
                          "expected an age, got an absolute date", file: file, line: line)
    }

    private func assertAbsolute(_ date: Date, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ItemDetailView.updatedLabel(for: date, now: now),
                       ItemDetailView.absoluteDateString(date),
                       "expected an absolute date", file: file, line: line)
    }

    // MARK: - Within the window

    func test_revisedToday_isAnAge() { assertAge(daysAgo(0)) }

    func test_revisedFourDaysAgo_isAnAge() { assertAge(daysAgo(4)) }

    /// The boundary itself, because "more than 30 days" and "30 days or more" differ by one day and
    /// nothing else would notice.
    func test_revisedExactlyAtTheLimit_isStillAnAge() {
        assertAge(daysAgo(TimeInterval(ItemDetailView.relativeAgeLimitInDays)))
    }

    // MARK: - Past the window

    func test_revisedTheDayAfterTheLimit_isAnAbsoluteDate() {
        assertAbsolute(daysAgo(TimeInterval(ItemDetailView.relativeAgeLimitInDays) + 1))
    }

    /// The case the rule exists for: "1 year ago" is a *loss* of precision against the date it
    /// replaced, and a year-old credential is exactly when staleness is the question.
    func test_revisedTwoYearsAgo_isAnAbsoluteDate() { assertAbsolute(daysAgo(730)) }

    // MARK: - Clock skew

    /// A revision dated in the future is shown as a date rather than turned into "in 3 days" — the
    /// view has no basis for a claim about the future, and an age counting up from a future date
    /// reads as a bug in the clock, which is what it is.
    func test_futureRevision_isAnAbsoluteDateNotAFutureAge() {
        assertAbsolute(now.addingTimeInterval(3 * day))
    }

    // MARK: - The absolute branch is stable

    func test_absoluteLabel_carriesTheYear() {
        // The year is the point of the absolute form: two items revised in the same month of
        // different years have to be tellable apart.
        let date = daysAgo(400)
        let text = ItemDetailView.absoluteDateString(date)
        XCTAssertTrue(text.contains("2025"), "expected the year in: \(text)")
    }
}
