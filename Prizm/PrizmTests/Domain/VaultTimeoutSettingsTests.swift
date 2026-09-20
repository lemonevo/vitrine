import XCTest
@testable import Prizm

/// Tests for the idle-timeout configuration.
///
/// The load-bearing assertion in this file is the `.never` mapping. Representing "never" as a large
/// number of minutes overflows when converted to seconds and silently becomes "lock almost
/// immediately" — a security setting that fails open. `.never` must therefore be `nil`, and `nil`
/// must not be reachable through arithmetic.
final class VaultTimeoutSettingsTests: XCTestCase {

    // MARK: - VaultTimeoutInterval

    func test_seconds_matchesMinutesForEveryFiniteCase() {
        XCTAssertEqual(VaultTimeoutInterval.oneMinute.seconds, 60)
        XCTAssertEqual(VaultTimeoutInterval.fiveMinutes.seconds, 300)
        XCTAssertEqual(VaultTimeoutInterval.fifteenMinutes.seconds, 900)
        XCTAssertEqual(VaultTimeoutInterval.thirtyMinutes.seconds, 1800)
        XCTAssertEqual(VaultTimeoutInterval.oneHour.seconds, 3600)
    }

    func test_never_hasNoSecondCount() {
        XCTAssertNil(VaultTimeoutInterval.never.seconds)
        XCTAssertNil(VaultTimeoutInterval.never.minutes)
    }

    /// Guards the specific failure mode the `nil` representation exists to prevent: every finite
    /// interval must produce a positive, sane number of seconds.
    func test_finiteIntervals_producePositiveSaneSeconds() {
        for interval in VaultTimeoutInterval.allCases where interval != .never {
            guard let seconds = interval.seconds else {
                return XCTFail("\(interval) should have a second count")
            }
            XCTAssertGreaterThan(seconds, 0)
            XCTAssertLessThanOrEqual(seconds, 3600)
        }
    }

    func test_allCases_haveDistinctRawValuesAndNonEmptyLabels() {
        let raws = VaultTimeoutInterval.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)

        let labels = VaultTimeoutInterval.allCases.map(\.displayName)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    // MARK: - VaultTimeoutAction

    func test_action_allCases_haveDistinctRawValuesAndNonEmptyLabels() {
        let raws = VaultTimeoutAction.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)

        let labels = VaultTimeoutAction.allCases.map(\.displayName)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    // MARK: - VaultTimeoutSettings

    func test_default_isFifteenMinutesLock() {
        XCTAssertEqual(VaultTimeoutSettings.default.interval, .fifteenMinutes)
        XCTAssertEqual(VaultTimeoutSettings.default.action, .lock)
        XCTAssertFalse(VaultTimeoutSettings.default.isDisabled)
        XCTAssertEqual(VaultTimeoutSettings.default.seconds, 900)
    }

    func test_isDisabled_trueOnlyForNever() {
        let disabled = VaultTimeoutSettings(interval: .never, action: .lock)
        XCTAssertTrue(disabled.isDisabled)
        XCTAssertNil(disabled.seconds)

        let enabled = VaultTimeoutSettings(interval: .oneMinute, action: .lock)
        XCTAssertFalse(enabled.isDisabled)
    }

    /// The action is independent of the interval — "sign out after 5 minutes" is a legitimate
    /// configuration and must survive a round trip.
    func test_seconds_followsTheIntervalNotTheAction() {
        let signOut = VaultTimeoutSettings(interval: .oneHour, action: .signOut)
        XCTAssertEqual(signOut.seconds, 3600)
    }
}

// MARK: - Persistence

final class VaultTimeoutSettingsPersistenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VaultTimeoutSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_load_returnsDefaultWhenNothingStored() {
        XCTAssertEqual(VaultTimeoutSettings.load(from: defaults), .default)
    }

    func test_saveThenLoad_roundTripsEveryCombination() {
        for interval in VaultTimeoutInterval.allCases {
            for action in VaultTimeoutAction.allCases {
                let settings = VaultTimeoutSettings(interval: interval, action: action)
                settings.save(to: defaults)
                XCTAssertEqual(VaultTimeoutSettings.load(from: defaults), settings)
            }
        }
    }

    /// The two keys are written together but read independently, so each needs its own fallback.
    /// A half-written pair must not resolve to a mixture of stored and default in a surprising way.
    func test_load_fallsBackPerKey() {
        defaults.set(VaultTimeoutInterval.never.rawValue, forKey: VaultTimeoutSettings.intervalKey)
        // No action stored.
        let loaded = VaultTimeoutSettings.load(from: defaults)
        XCTAssertEqual(loaded.interval, .never)
        XCTAssertEqual(loaded.action, VaultTimeoutSettings.default.action)
    }

    func test_load_fallsBackForUnrecognisedValues() {
        defaults.set("twoHours", forKey: VaultTimeoutSettings.intervalKey)
        defaults.set("shred",    forKey: VaultTimeoutSettings.actionKey)
        XCTAssertEqual(VaultTimeoutSettings.load(from: defaults), .default)
    }

    /// A stored value must not be confused with "unset" for the interval that is the enum's first
    /// case. This is why persistence uses `string(forKey:)` rather than an `Int`-backed enum.
    func test_load_distinguishesFirstCaseFromUnset() {
        VaultTimeoutSettings(interval: .oneMinute, action: .lock).save(to: defaults)
        XCTAssertEqual(VaultTimeoutSettings.load(from: defaults).interval, .oneMinute)
    }
}
