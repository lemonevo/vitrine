import XCTest
@testable import Prizm

/// The decision half of `BackgroundSyncMonitor`.
///
/// The clock is a value the test moves by hand, so a five-minute interval costs no test five
/// minutes. The AppKit wiring — the `Timer` and the two notification observers — lives entirely in
/// `start()`/`stop()` and is deliberately not exercised here; that is the part the seam exists to
/// keep out of these tests.
@MainActor
final class BackgroundSyncMonitorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var now: Date!

    /// The clock is read through the closure, so moving `now` moves the monitor's.
    private func makeMonitor() -> BackgroundSyncMonitor {
        BackgroundSyncMonitor(now: { self.now })
    }

    override func setUp() async throws {
        try await super.setUp()
        now = t0
    }

    // MARK: - 1.1.1 / 1.1.2 the interval, measured from the last success

    func testShouldSync_intervalElapsed_isTrue() {
        now = t0 + BackgroundSyncMonitor.interval + 1

        XCTAssertTrue(makeMonitor().shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ))
    }

    func testShouldSync_intervalNotElapsed_isFalse() {
        now = t0 + BackgroundSyncMonitor.interval - 1

        XCTAssertFalse(makeMonitor().shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ))
    }

    /// Nothing has ever synced, so there is no baseline to measure an interval from. A refresh is
    /// allowed, and the timer's own cadence is what bounds it — refusing here would mean a vault
    /// entered from the offline cache never refreshes itself once the network comes back.
    func testShouldSync_neverSynced_isTrue() {
        XCTAssertTrue(makeMonitor().shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: nil
        ))
    }

    // MARK: - 1.1.3 locked means no refresh

    func testShouldSync_locked_isFalse() {
        now = t0 + BackgroundSyncMonitor.interval * 10

        XCTAssertFalse(makeMonitor().shouldSync(
            trigger: .timer, isUnlocked: false, isBusy: false, lastSuccessfulSyncAt: t0
        ))
    }

    // MARK: - 1.1.4 / 1.1.5 reactivation is throttled twice over

    /// Switching windows must not produce a sync per switch. The first activation after a long
    /// absence may sync; the next one a moment later may not.
    func testShouldSync_reactivationBeforeTheThrottle_isFalse() {
        let sut = makeMonitor()
        now = t0 + BackgroundSyncMonitor.interval + 1

        // The first activation is evaluated, and rests the throttle on `now`.
        XCTAssertTrue(sut.shouldSync(
            trigger: .reactivation, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ))

        now = now + BackgroundSyncMonitor.reactivationThrottle - 1
        XCTAssertFalse(sut.shouldSync(
            trigger: .reactivation, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ), "a second activation inside the throttle must not sync")
    }

    /// Past the throttle but with a recent success, the interval still decides. The throttle is a
    /// burst guard, not a licence to sync more often than the interval allows.
    func testShouldSync_reactivationPastTheThrottle_butRecentSuccess_isFalse() {
        now = t0 + BackgroundSyncMonitor.reactivationThrottle + 1

        XCTAssertFalse(makeMonitor().shouldSync(
            trigger: .reactivation, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ))
    }

    /// The throttle belongs to the reactivation trigger, not to syncing: a timer tick is not
    /// suppressed by a recent activation.
    func testShouldSync_timerTick_isNotThrottledByReactivation() {
        let sut = makeMonitor()
        _ = sut.shouldSync(trigger: .reactivation, isUnlocked: true, isBusy: false,
                           lastSuccessfulSyncAt: t0)

        now = t0 + BackgroundSyncMonitor.interval + 1
        XCTAssertTrue(sut.shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ))
    }

    // MARK: - 1.1.6 / 1.1.7 a busy session is not refreshed

    func testShouldSync_editSheetOpen_isFalse() {
        now = t0 + BackgroundSyncMonitor.interval * 10

        XCTAssertFalse(makeMonitor().shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: true, lastSuccessfulSyncAt: t0
        ), "a refresh would replace the selected item under the open draft")
    }

    func testShouldSync_mutationInFlight_isFalse() {
        now = t0 + BackgroundSyncMonitor.interval * 10

        XCTAssertFalse(makeMonitor().shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: true, lastSuccessfulSyncAt: t0
        ), "a refresh landing between a write and the store's update makes the list disagree")
    }

    /// Busy outranks an elapsed interval, on both triggers. A long-open sheet must not "bank" the
    /// elapsed time and fire the moment it closes — the next tick picks the work up instead.
    func testShouldSync_busyOutranksAnElapsedInterval_onReactivationToo() {
        now = t0 + BackgroundSyncMonitor.interval * 10

        XCTAssertFalse(makeMonitor().shouldSync(
            trigger: .reactivation, isUnlocked: true, isBusy: true, lastSuccessfulSyncAt: t0
        ))
    }

    // MARK: - 1.1.8 a failure cannot shorten the interval

    /// The interval is measured from the last **successful** sync, and there is deliberately no
    /// "last attempt" input for a failed attempt to reset. A run of failures therefore cannot
    /// produce a retry storm: the tick after a failure is admitted on exactly the same terms as the
    /// one that failed, and the timer's cadence is the only thing driving them.
    func testShouldSync_onlySuccessMovesTheBaseline() {
        let sut = makeMonitor()

        // A tick that fires and then fails changes nothing about the baseline…
        now = t0 + BackgroundSyncMonitor.interval + 1
        XCTAssertTrue(sut.shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ))

        // …so the decision afterwards is governed by the same baseline, which is the property the
        // absent "last attempt" input makes true by construction.
        now = t0 + BackgroundSyncMonitor.interval + 2
        XCTAssertTrue(sut.shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: false, lastSuccessfulSyncAt: t0
        ))

        // A success is what makes the next tick wait a full interval again.
        now = t0 + BackgroundSyncMonitor.interval + 3
        XCTAssertFalse(sut.shouldSync(
            trigger: .timer, isUnlocked: true, isBusy: false,
            lastSuccessfulSyncAt: t0 + BackgroundSyncMonitor.interval + 3
        ))
    }

    // MARK: - 2.1 / 2.2 start and stop

    /// The `Timer` and the observer tokens are AppKit's and are not observable from here, which is
    /// the whole reason the seam exists. What *is* observable is the installed state, and the
    /// property that matters is that start and stop agree about it.
    func testStartAndStop_areIdempotent() {
        let sut = makeMonitor()

        sut.start()
        sut.start()
        XCTAssertTrue(sut.isRunning)

        sut.stop()
        sut.stop()
        XCTAssertFalse(sut.isRunning)

        sut.start()
        XCTAssertTrue(sut.isRunning, "a stopped monitor must be startable again")
    }
}
