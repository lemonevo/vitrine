import Combine
import Foundation

// MARK: - TOTPCodeViewModel

/// Derives the code shown by one row of the detail view, and keeps it current.
///
/// **The code is recomputed from the secret, never extrapolated.** HMAC gives no way to advance a
/// code, so "the next one" can only be had by deriving it — and a cached code kept past its step is
/// simply a wrong code. Every refresh therefore goes back to the generator.
///
/// **The clock is injected and the update is exposed as a method.** `refresh(at:)` is the whole
/// behaviour; the timer is only a way of calling it. A countdown tested by sleeping would be slow,
/// flaky, and unable to reach the cases that matter — every one of them is a specific instant.
@MainActor
final class TOTPCodeViewModel: ObservableObject {

    /// The code, grouped for reading (`123 456`). Nil before the first refresh and when the stored
    /// value yields no code.
    @Published private(set) var displayCode: String?

    /// Seconds the code remains valid, in `1...period`. Nil when there is no code.
    @Published private(set) var secondsRemaining: Int?

    /// How much of the step is left, `0...1`, for a bar that shrinks as the code ages.
    ///
    /// The fraction remaining rather than elapsed, because a bar that fills up as a code is about to
    /// expire reads as "almost ready" — the opposite of what it means.
    @Published private(set) var remainingFraction: Double = 0

    /// The stored value is present but produces no code. Distinct from "not refreshed yet": the row
    /// says why instead of showing an empty value, and it must not do that before it has looked.
    @Published private(set) var isUnusable = false

    let itemId: String

    /// The code as it goes on the clipboard — **ungrouped**. The row groups the digits for reading;
    /// a paste target wants the bare ones, and `⌃⌘C` already copies them bare. One value, one
    /// convention.
    var copyValue: String? { code }

    private var code: String?
    private var expiresAt: Date?

    private let secret: String?
    private let generator: any TOTPGenerator
    private let now: () -> Date

    /// `nonisolated(unsafe)` because `deinit` is always nonisolated in Swift 6, and a timer that
    /// outlives its view model keeps deriving codes for an item nobody is looking at.
    nonisolated(unsafe) private var timer: Timer?
    private var isRunning = false

    init(itemId:   String,
         secret:    String?,
         generator: any TOTPGenerator,
         now:       @escaping () -> Date = Date.init) {
        self.itemId    = itemId
        self.secret    = secret
        self.generator = generator
        self.now       = now
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Lifecycle

    /// Starts deriving and keeps the row current until `stop()`.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh(at: now())
        scheduleNextRefresh()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Refresh

    /// Recomputes everything from the stored value at `date`.
    func refresh(at date: Date) {
        guard let window = generator.window(for: secret, at: date) else {
            code             = nil
            displayCode      = nil
            secondsRemaining = nil
            remainingFraction = 0
            expiresAt        = nil
            isUnusable       = true
            return
        }

        isUnusable       = false
        code             = window.value
        displayCode      = Self.grouped(window.value)
        expiresAt        = window.expiresAt
        let remaining    = Self.remainingSeconds(until: window.expiresAt, at: date, period: window.period)
        secondsRemaining = remaining
        remainingFraction = Self.remainingFraction(secondsRemaining: remaining, period: window.period)
    }

    /// Schedules one refresh. Re-scheduled after each fire rather than left repeating, so the delay
    /// can be recomputed — see `delayUntilNextRefresh`.
    private func scheduleNextRefresh() {
        guard isRunning else { return }
        let delay = Self.delayUntilNextRefresh(expiresAt: expiresAt, at: now())
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                // The re-check is the point. A timer fire hands its work to the main actor rather than
                // doing it there, so a `stop()` that lands in between cannot retract this task — without
                // this guard a stopped row derives and publishes one more code, which is harmless while
                // the row is on screen and exactly the wrong thing when the stop was a vault lock.
                guard let self, self.isRunning else { return }
                self.refresh(at: self.now())
                self.scheduleNextRefresh()
            }
        }
    }

    // MARK: - Pure logic

    // `nonisolated` on both: `-default-isolation MainActor` makes a `static let` main-actor
    // isolated too, and the pure functions below are `nonisolated` on purpose so the boundary cases
    // can be tested without a clock or an actor hop.
    nonisolated static let tickInterval: TimeInterval = 1

    /// How long after the boundary the aligned refresh lands. Small enough to be invisible, large
    /// enough that a clock that is a millisecond fast does not read the previous step.
    nonisolated static let boundaryOffset: TimeInterval = 0.05

    /// The delay before the next refresh.
    ///
    /// **The first refresh after a boundary is aligned to it; the rest are one second apart.** A
    /// plain one-second timer keeps whatever phase it was started on, so the code it replaces can be
    /// displayed for up to a second after it expired — the row would be showing a code that no
    /// longer works. Landing just after the boundary removes that window, and because a period is a
    /// whole number of seconds the alignment survives every later step.
    nonisolated static func delayUntilNextRefresh(expiresAt: Date?, at date: Date) -> TimeInterval {
        guard let expiresAt else { return tickInterval }
        let untilBoundary = expiresAt.timeIntervalSince(date)
        guard untilBoundary <= tickInterval else { return tickInterval }
        return max(untilBoundary, 0) + boundaryOffset
    }

    /// Seconds until `expiresAt`, ceiled, clamped to `1...period`.
    ///
    /// Two ways this goes wrong if written naively, both of which look like a broken clock rather
    /// than a broken calculation:
    ///
    /// - **Zero.** A countdown reading 0 invites the user to wait for a code that has already rolled.
    ///   Ceiling makes the final second read 1.
    /// - **One past the end.** A float landing just outside the step yields `period + 1` for a single
    ///   tick, which a progress bar draws as a full bar that then jumps. The clamp keeps it inside.
    nonisolated static func remainingSeconds(until expiresAt: Date, at date: Date, period: TimeInterval) -> Int {
        let remaining = Int(ceil(expiresAt.timeIntervalSince(date)))
        return max(1, min(Int(period), remaining))
    }

    nonisolated static func remainingFraction(secondsRemaining: Int, period: TimeInterval) -> Double {
        guard period > 0 else { return 0 }
        return min(1, max(0, Double(secondsRemaining) / period))
    }

    /// Splits the digits in half for reading: `123 456`, `1234 5678`.
    ///
    /// A display concern only — `copyValue` stays ungrouped. Codes of four digits or fewer are left
    /// alone, since splitting them would add a gap and no help.
    nonisolated static func grouped(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let split = code.index(code.startIndex, offsetBy: (code.count + 1) / 2)
        return "\(code[code.startIndex..<split]) \(code[split...])"
    }
}
