import AppKit
import Foundation

// MARK: - VaultIdleMonitoring

/// Starts and stops idle-timeout observation, and reports when the timeout elapses.
///
/// A protocol so `RootViewModel` can be tested without installing a real `NSEvent` monitor: the
/// monitor's AppKit wiring is the part that cannot be exercised in a unit test, and it is exactly
/// the part this seam removes from the ViewModel's tests.
@MainActor
protocol VaultIdleMonitoring: AnyObject {

    /// Called when the configured idle interval has elapsed. The owner sets this.
    var onTimeout: ((VaultTimeoutAction) -> Void)? { get set }

    /// Begins observing input. Idempotent.
    func start()

    /// Stops observing input and releases the timer. Idempotent.
    func stop()
}

// MARK: - VaultIdleMonitor

/// Watches for user input and reports when the vault has been idle for longer than the configured
/// timeout.
///
/// **Why a local event monitor.** `NSEvent.addLocalMonitorForEvents(matching:)` is the only
/// supported way to observe input without an accessibility entitlement. A *local* monitor sees only
/// events delivered to this application, which is exactly the semantics an idle timeout wants: if
/// the user is working in another application, Prizm is idle and should lock.
///
/// The monitor returns every event unchanged. It is an observer, never a filter — swallowing input
/// in order to implement a lock timer would be a serious defect.
///
/// **Testability.** The clock is injected and the decision is exposed as
/// `noteActivity(at:)` / `timeoutAction(at:)`. The AppKit wiring — the event monitor and the
/// repeating timer — lives entirely in `start()`/`stop()` and is never exercised by tests. What the
/// tests drive is the decision itself. Without that split, testing a 15-minute timeout would mean
/// waiting 15 minutes.
@MainActor
final class VaultIdleMonitor: VaultIdleMonitoring {

    /// How often the idle condition is evaluated.
    ///
    /// Polling rather than rescheduling on every event: one repeating timer is easier to reason
    /// about than a timer invalidated and recreated on each keystroke, and the worst-case overshoot
    /// is this interval measured against a minimum timeout of 60 seconds.
    static let pollInterval: TimeInterval = 5

    /// Mouse-move events arrive at display rate. Activity is recorded at most once per this many
    /// seconds, which is far finer than the poll interval and keeps the monitor off the hot path.
    static let activityThrottle: TimeInterval = 1

    /// The events that count as activity.
    ///
    /// Mouse movement is included because users reasonably expect moving the pointer to postpone a
    /// lock. Note that this only observes movement *over this application's windows* — moving the
    /// mouse over another app is not activity, which is the intended behaviour.
    private static let activityMask: NSEvent.EventTypeMask = [
        .keyDown, .flagsChanged,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .scrollWheel,
        .mouseMoved
    ]

    var onTimeout: ((VaultTimeoutAction) -> Void)?

    /// Read on every poll rather than captured once, so changing the setting takes effect
    /// immediately without restarting the monitor.
    private let settings: () -> VaultTimeoutSettings
    private let now: () -> Date

    private var lastActivity: Date
    private var lastRecordedActivity: Date

    // nonisolated(unsafe) because `deinit` is always nonisolated in Swift 6 and neither `Timer` nor
    // the monitor token is Sendable. Both are only ever mutated on MainActor.
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var eventMonitor: Any?

    init(settings: @escaping () -> VaultTimeoutSettings,
         now: @escaping () -> Date = Date.init,
         onTimeout: ((VaultTimeoutAction) -> Void)? = nil) {
        self.settings  = settings
        self.now       = now
        self.onTimeout = onTimeout
        let start = now()
        self.lastActivity         = start
        self.lastRecordedActivity = start
    }

    deinit {
        timer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    // MARK: - Lifecycle

    func start() {
        guard eventMonitor == nil, timer == nil else { return }

        // Reset the baseline rather than going through the throttle, so the countdown starts when
        // monitoring starts instead of whenever the last throttled event happened.
        resetBaseline(to: now())

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.activityMask) { [weak self] event in
            // Local monitor handlers run on the main thread. `assumeIsolated` states that rather
            // than hopping through a Task, which would allocate one Task per mouse-move event.
            MainActor.assumeIsolated { self?.noteActivity() }
            return event
        }

        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollAndAct() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - Activity

    /// Records that the user did something at `date`.
    ///
    /// Throttled so mouse-move events do not each take the MainActor. The throttle is far below the
    /// poll interval, so it cannot delay a reset that matters.
    func noteActivity(at date: Date) {
        guard date.timeIntervalSince(lastRecordedActivity) >= Self.activityThrottle else { return }
        lastRecordedActivity = date
        lastActivity = date
    }

    func noteActivity() { noteActivity(at: now()) }

    /// Seconds elapsed since the most recent recorded activity.
    func idleSeconds(at date: Date) -> TimeInterval {
        date.timeIntervalSince(lastActivity)
    }

    /// The action that should be taken at `date`, or `nil` when the vault is not idle enough yet or
    /// the timeout is disabled.
    ///
    /// Deliberately does not reset the baseline — asking the question must not change the answer for
    /// the next caller. `pollAndAct()` resets explicitly once it has decided to act.
    func timeoutAction(at date: Date) -> VaultTimeoutAction? {
        let current = settings()
        guard let seconds = current.seconds else { return nil }   // .never
        guard idleSeconds(at: date) >= seconds else { return nil }
        return current.action
    }

    func timeoutAction() -> VaultTimeoutAction? { timeoutAction(at: now()) }

    // MARK: - Private

    private func pollAndAct() {
        guard let action = timeoutAction() else { return }
        // Reset before acting: the vault is about to lock, and a poll that lands while the teardown
        // is still running must not fire a second time.
        resetBaseline(to: now())
        onTimeout?(action)
    }

    private func resetBaseline(to date: Date) {
        lastActivity = date
        lastRecordedActivity = date
    }
}
