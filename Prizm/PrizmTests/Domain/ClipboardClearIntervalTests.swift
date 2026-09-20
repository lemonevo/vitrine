import XCTest
@testable import Prizm

/// Tests for the configurable clipboard clear interval.
final class ClipboardClearIntervalTests: XCTestCase {

    func test_seconds_forEveryFiniteCase() {
        XCTAssertEqual(ClipboardClearInterval.tenSeconds.seconds, 10)
        XCTAssertEqual(ClipboardClearInterval.twentySeconds.seconds, 20)
        XCTAssertEqual(ClipboardClearInterval.thirtySeconds.seconds, 30)
        XCTAssertEqual(ClipboardClearInterval.oneMinute.seconds, 60)
        XCTAssertEqual(ClipboardClearInterval.twoMinutes.seconds, 120)
    }

    /// `.never` must schedule nothing at all — not a very long timer, which would still depend on
    /// the process outliving it.
    func test_never_hasNoSecondCount() {
        XCTAssertNil(ClipboardClearInterval.never.seconds)
    }

    /// The default must match the behaviour that was hardcoded before the setting existed, so that
    /// upgrading does not silently change how long a password sits on the clipboard.
    func test_default_isThirtySeconds() {
        XCTAssertEqual(ClipboardClearInterval.default, .thirtySeconds)
        XCTAssertEqual(ClipboardClearInterval.default.seconds, 30)
    }

    func test_allCases_haveDistinctRawValuesAndNonEmptyLabels() {
        let raws = ClipboardClearInterval.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)

        let labels = ClipboardClearInterval.allCases.map(\.displayName)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func test_finiteIntervals_areOrderedAscending() {
        let finite = ClipboardClearInterval.allCases.compactMap(\.seconds)
        XCTAssertEqual(finite, finite.sorted(), "the picker order should match the duration order")
    }
}

// MARK: - Persistence

final class ClipboardClearIntervalPersistenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClipboardClearIntervalTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_load_returnsDefaultWhenNothingStored() {
        XCTAssertEqual(ClipboardClearInterval.load(from: defaults), .default)
    }

    func test_saveThenLoad_roundTripsEveryCase() {
        for interval in ClipboardClearInterval.allCases {
            ClipboardClearInterval.save(interval, to: defaults)
            XCTAssertEqual(ClipboardClearInterval.load(from: defaults), interval)
        }
    }

    func test_load_fallsBackForUnrecognisedValue() {
        defaults.set("fiveMinutes", forKey: ClipboardClearInterval.key)
        XCTAssertEqual(ClipboardClearInterval.load(from: defaults), .default)
    }

    /// `.tenSeconds` is the first case, so a `UserDefaults.bool`-style read would confuse it with
    /// "unset". This is why the value is stored as a string.
    func test_load_distinguishesFirstCaseFromUnset() {
        ClipboardClearInterval.save(.tenSeconds, to: defaults)
        XCTAssertEqual(ClipboardClearInterval.load(from: defaults), .tenSeconds)
    }

    func test_load_distinguishesNeverFromUnset() {
        ClipboardClearInterval.save(.never, to: defaults)
        XCTAssertEqual(ClipboardClearInterval.load(from: defaults), .never)
        XCTAssertNil(ClipboardClearInterval.load(from: defaults).seconds)
    }
}
