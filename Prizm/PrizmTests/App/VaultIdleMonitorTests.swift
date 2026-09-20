import XCTest
@testable import Prizm

/// Tests for `VaultIdleMonitor`'s decision logic.
///
/// The AppKit wiring — the `NSEvent` local monitor and the repeating timer — is deliberately not
/// exercised here: it is the one part of the feature a unit test cannot drive, and that is exactly
/// why the seam exists. What is tested is the decision the wiring feeds: given a clock, a
/// configuration and a record of activity, does the vault time out?
@MainActor
final class VaultIdleMonitorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// A clock the test moves by hand.
    private final class Clock {
        var now: Date
        init(_ start: Date) { self.now = start }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func makeSUT(interval: VaultTimeoutInterval = .oneMinute,
                         action: VaultTimeoutAction = .lock)
        -> (monitor: VaultIdleMonitor, clock: Clock) {
        let clock = Clock(t0)
        let settings = VaultTimeoutSettings(interval: interval, action: action)
        let monitor = VaultIdleMonitor(settings: { settings }, now: { clock.now })
        return (monitor, clock)
    }

    // MARK: - Threshold

    func test_timeoutAction_isNilBeforeTheInterval() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)
        clock.advance(59)
        XCTAssertNil(monitor.timeoutAction(at: clock.now))
    }

    /// The comparison is `>=`, so the action fires on the boundary rather than one tick later.
    func test_timeoutAction_firesExactlyOnTheBoundary() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)
        clock.advance(60)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .lock)
    }

    func test_timeoutAction_firesAfterTheInterval() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)
        clock.advance(60 * 60)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .lock)
    }

    /// Asking the question must not change the answer for the next caller. If `timeoutAction(at:)`
    /// reset the baseline, a poll that ran twice in a row would never fire.
    func test_timeoutAction_doesNotResetTheBaseline() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)
        clock.advance(120)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .lock)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .lock)
        XCTAssertEqual(monitor.idleSeconds(at: clock.now), 120)
    }

    // MARK: - Activity

    func test_noteActivity_resetsTheBaseline() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)
        clock.advance(59)
        monitor.noteActivity(at: clock.now)

        clock.advance(59)
        XCTAssertNil(monitor.timeoutAction(at: clock.now), "59 s after activity is not yet idle")

        clock.advance(1)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .lock)
    }

    /// Activity is recorded at most once per `activityThrottle` second. Mouse-move events arrive at
    /// display rate, and taking the MainActor for each one would be a hot-path cost for no gain.
    func test_noteActivity_isThrottled() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)

        clock.advance(30)
        monitor.noteActivity(at: clock.now)          // recorded
        XCTAssertEqual(monitor.idleSeconds(at: clock.now), 0)

        clock.advance(0.5)
        monitor.noteActivity(at: clock.now)          // throttled: too soon
        XCTAssertEqual(monitor.idleSeconds(at: clock.now), 0.5,
                       "the baseline must still be the earlier event; 0 would mean this one was recorded")

        clock.advance(1)
        monitor.noteActivity(at: clock.now)          // recorded: past the throttle
        XCTAssertEqual(monitor.idleSeconds(at: clock.now), 0)
    }

    /// The throttle must be far below the shortest configurable interval, or a real keystroke could
    /// be discarded and the vault would lock while the user is typing.
    func test_activityThrottle_isWellBelowTheShortestInterval() {
        let shortest = VaultTimeoutInterval.allCases.compactMap(\.seconds).min() ?? .infinity
        XCTAssertLessThan(VaultIdleMonitor.activityThrottle, shortest / 10)
    }

    // MARK: - Configuration

    func test_timeoutAction_returnsTheConfiguredAction() {
        let (lockMonitor, lockClock) = makeSUT(interval: .oneMinute, action: .lock)
        lockClock.advance(60)
        XCTAssertEqual(lockMonitor.timeoutAction(at: lockClock.now), .lock)

        let (outMonitor, outClock) = makeSUT(interval: .oneMinute, action: .signOut)
        outClock.advance(60)
        XCTAssertEqual(outMonitor.timeoutAction(at: outClock.now), .signOut)
    }

    func test_never_neverFires() {
        let (monitor, clock) = makeSUT(interval: .never)
        clock.advance(60 * 60 * 24 * 30)
        XCTAssertNil(monitor.timeoutAction(at: clock.now))
        XCTAssertEqual(monitor.idleSeconds(at: clock.now), 60 * 60 * 24 * 30,
                       "idle time is still measured; it simply does not trigger anything")
    }

    /// The settings closure is read on every poll rather than captured once, so changing the
    /// preference takes effect without restarting the monitor.
    func test_settingsAreReReadOnEveryCall() {
        let clock = Clock(t0)
        var settings = VaultTimeoutSettings(interval: .never, action: .lock)
        let monitor = VaultIdleMonitor(settings: { settings }, now: { clock.now })

        clock.advance(60 * 60)
        XCTAssertNil(monitor.timeoutAction(at: clock.now))

        settings = VaultTimeoutSettings(interval: .fiveMinutes, action: .signOut)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .signOut)

        settings = VaultTimeoutSettings(interval: .never, action: .signOut)
        XCTAssertNil(monitor.timeoutAction(at: clock.now), "disabling takes effect immediately too")
    }

    // MARK: - Lifecycle

    /// `start()` resets the baseline rather than resuming from the last throttled event, so the
    /// countdown begins when the vault is unlocked.
    func test_start_resetsTheBaseline() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)
        clock.advance(60 * 30)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .lock, "idle before start")

        monitor.start()
        XCTAssertNil(monitor.timeoutAction(at: clock.now), "start() restarts the countdown")
        monitor.stop()
    }

    func test_startAndStop_areIdempotent() {
        let (monitor, clock) = makeSUT(interval: .oneMinute)

        monitor.start()
        monitor.start()
        clock.advance(120)
        XCTAssertEqual(monitor.timeoutAction(at: clock.now), .lock,
                       "a second start() must not have disabled the monitor")

        monitor.stop()
        monitor.stop()
        // Still usable afterwards: stop() releases resources, it does not break the decision.
        monitor.start()
        monitor.stop()
    }

    func test_init_storesTheTimeoutCallback() {
        var received: VaultTimeoutAction?
        let monitor = VaultIdleMonitor(settings: { .default }, now: { self.t0 },
                                       onTimeout: { received = $0 })
        XCTAssertNotNil(monitor.onTimeout)
        monitor.onTimeout?(.signOut)
        XCTAssertEqual(received, .signOut)
    }
}
