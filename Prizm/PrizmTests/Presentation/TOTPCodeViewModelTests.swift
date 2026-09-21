import XCTest
@testable import Prizm

/// Tests for `TOTPCodeViewModel`.
///
/// **The clock is injected and the update is a method**, so every case below is a specific instant
/// rather than a sleep. A countdown tested by waiting is slow, flaky, and — the part that matters —
/// unable to reach the boundaries: "one second before the step rolls", "exactly on the boundary",
/// "a millisecond past it". Those are the cases the display gets wrong.
///
/// The one test that does let real time pass is the timer's, and it is labelled as such.
@MainActor
final class TOTPCodeViewModelTests: XCTestCase {

    /// A generator whose code is a function of the step number, so a test can tell one step from the
    /// next without knowing a secret — and so a step roll is observable as a change of value.
    private struct StepCodeGenerator: TOTPGenerator {
        let period: TimeInterval

        func window(for secret: String?, at date: Date) -> TOTPWindow? {
            guard let secret, !secret.isEmpty else { return nil }
            let step    = max(1, period)
            let counter = floor(date.timeIntervalSince1970 / step)
            return TOTPWindow(value:     String(format: "%06d", Int(counter) % 1_000_000),
                              expiresAt: Date(timeIntervalSince1970: (counter + 1) * step),
                              period:    step)
        }
    }

    private let seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    private func date(_ unixTime: TimeInterval) -> Date { Date(timeIntervalSince1970: unixTime) }

    /// Lets the run loop run for `seconds`, so a `Timer` scheduled on it actually fires.
    ///
    /// Not a sleep: `Task.sleep` would suspend the test without guaranteeing the run loop is being
    /// pumped, and a timer that never fires would look like a view model that never refreshed.
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Before the first refresh

    func test_beforeAnyRefresh_nothingIsClaimed() {
        // `isUnusable` must mean "looked, and it yields nothing" — not "has not looked yet". The row
        // says why in the first case and shows bullets in the second.
        let sut = TOTPCodeViewModel(itemId: "item", secret: seed, generator: TOTPGeneratorImpl())
        XCTAssertNil(sut.displayCode)
        XCTAssertNil(sut.secondsRemaining)
        XCTAssertNil(sut.copyValue)
        XCTAssertEqual(sut.remainingFraction, 0)
        XCTAssertFalse(sut.isUnusable)
    }

    // MARK: - Refresh

    func test_refresh_derivesTheCodeAndItsRemainingTime() {
        let sut = TOTPCodeViewModel(itemId: "item", secret: seed, generator: TOTPGeneratorImpl())
        sut.refresh(at: date(59))

        // 6-digit SHA-1 at t=59 — the same vector `TOTPGeneratorTests` pins, grouped for reading.
        XCTAssertEqual(sut.displayCode, "287 082")
        XCTAssertEqual(sut.copyValue, "287082")
        XCTAssertEqual(sut.secondsRemaining, 1)
        XCTAssertFalse(sut.isUnusable)
    }

    func test_refresh_atTheStartOfAStep_reportsTheWholeStepRemaining() {
        let sut = TOTPCodeViewModel(itemId: "item", secret: seed, generator: TOTPGeneratorImpl())
        sut.refresh(at: date(30))
        XCTAssertEqual(sut.secondsRemaining, 30)
        XCTAssertEqual(sut.remainingFraction, 1.0, accuracy: 0.0001)
    }

    func test_refresh_followsTheStep() {
        let sut = TOTPCodeViewModel(itemId: "item", secret: seed, generator: TOTPGeneratorImpl())
        sut.refresh(at: date(59))
        let before = sut.displayCode
        sut.refresh(at: date(60))
        XCTAssertNotEqual(sut.displayCode, before, "the code must follow the time step")
    }

    func test_refresh_recomputesFromTheSecret_ratherThanExtrapolating() {
        // HMAC gives no way to advance a code, so a refresh that did not go back to the generator
        // would return the previous step's code — which is simply the wrong code.
        let sut = TOTPCodeViewModel(itemId: "item", secret: seed, generator: StepCodeGenerator(period: 30))
        sut.refresh(at: date(0))
        XCTAssertEqual(sut.copyValue, "000000")
        sut.refresh(at: date(30))
        XCTAssertEqual(sut.copyValue, "000001")
        sut.refresh(at: date(60))
        XCTAssertEqual(sut.copyValue, "000002")
    }

    func test_refresh_withAnUnusableSecret_reportsItInsteadOfShowingNothing() {
        let sut = TOTPCodeViewModel(itemId: "item", secret: "not-base32!", generator: TOTPGeneratorImpl())
        sut.refresh(at: date(59))

        XCTAssertTrue(sut.isUnusable)
        XCTAssertNil(sut.displayCode, "no code, and not an empty string either")
        XCTAssertNil(sut.secondsRemaining, "nothing to count down")
        XCTAssertNil(sut.copyValue, "nothing to copy")
        XCTAssertEqual(sut.remainingFraction, 0)
    }

    func test_refresh_recoversWhenTheSecretStopsBeingUnusable() {
        // The row is rebuilt for each item, but a refresh that left `isUnusable` stuck would make a
        // later valid secret look broken.
        let sut = TOTPCodeViewModel(itemId: "item", secret: nil, generator: TOTPGeneratorImpl())
        sut.refresh(at: date(59))
        XCTAssertTrue(sut.isUnusable)
        sut.refresh(at: date(59))
        XCTAssertTrue(sut.isUnusable)
    }

    // MARK: - The stored value never leaves

    func test_copyValue_isTheCodeAndNeverTheSeed() {
        // The §2.1 regression, through the new path: `Item ▸ Copy Code` used to put this seed on the
        // clipboard, and a seed on the clipboard is a permanent second factor.
        let sut = TOTPCodeViewModel(itemId: "item", secret: seed, generator: TOTPGeneratorImpl())
        sut.refresh(at: date(59))

        XCTAssertEqual(sut.copyValue, "287082")
        XCTAssertNotEqual(sut.copyValue, seed)
        XCTAssertFalse(sut.copyValue?.contains(seed) ?? false)
    }

    func test_copyValue_isUngroupedWhileTheDisplayIsGrouped() {
        // A paste target wants the bare digits, and `⌃⌘C` already copies them bare — one value, one
        // convention.
        let sut = TOTPCodeViewModel(itemId: "item", secret: seed, generator: TOTPGeneratorImpl())
        sut.refresh(at: date(59))
        XCTAssertEqual(sut.displayCode, "287 082")
        XCTAssertEqual(sut.copyValue, "287082")
        XCTAssertFalse(sut.copyValue?.contains(" ") ?? true)
    }

    // MARK: - Remaining seconds

    func test_remainingSeconds_isCeiledSoTheLastSecondReadsOne() {
        // 0 invites the user to wait for a code that has already rolled.
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(59.001), period: 30), 1)
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(59.999), period: 30), 1)
    }

    func test_remainingSeconds_neverReadsZero_insideTheStep() {
        for offset in stride(from: 0.0, through: 30.0, by: 0.25) {
            let instant = date(30 + offset)
            let remaining = TOTPCodeViewModel.remainingSeconds(until: date(60), at: instant, period: 30)
            XCTAssertGreaterThanOrEqual(remaining, 1, "at t=30+\(offset)")
        }
    }

    func test_remainingSeconds_neverExceedsTheStep() {
        // A float landing just outside the step would yield period + 1 for one tick, which a bar
        // draws as a full bar that then jumps.
        for offset in stride(from: -1.0, through: 31.0, by: 0.25) {
            let instant = date(60 + offset)
            let remaining = TOTPCodeViewModel.remainingSeconds(until: date(60), at: instant, period: 30)
            XCTAssertGreaterThanOrEqual(remaining, 1, "at t=60+\(offset)")
            XCTAssertLessThanOrEqual(remaining, 30, "at t=60+\(offset)")
        }
    }

    func test_remainingSeconds_onTheBoundaryReadsOne() {
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(60), period: 30), 1)
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(60.5), period: 30), 1)
    }

    func test_remainingSeconds_midStepIsTheRoundedUpDistance() {
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(30), period: 30), 30)
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(45), period: 30), 15)
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(45.5), period: 30), 15)
        XCTAssertEqual(TOTPCodeViewModel.remainingSeconds(until: date(60), at: date(44.5), period: 30), 16)
    }

    // MARK: - Fraction

    func test_remainingFraction_isTheShareOfTheStepLeft() {
        XCTAssertEqual(TOTPCodeViewModel.remainingFraction(secondsRemaining: 30, period: 30), 1.0, accuracy: 0.0001)
        XCTAssertEqual(TOTPCodeViewModel.remainingFraction(secondsRemaining: 15, period: 30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TOTPCodeViewModel.remainingFraction(secondsRemaining: 1,  period: 30), 1.0 / 30, accuracy: 0.0001)
    }

    func test_remainingFraction_survivesAZeroPeriod() {
        // Not reachable through the generator, which refuses a period of zero — but a division by
        // zero here would be a crash rather than a wrong bar, so it is handled.
        XCTAssertEqual(TOTPCodeViewModel.remainingFraction(secondsRemaining: 5, period: 0), 0)
    }

    // MARK: - Refresh scheduling

    func test_delayUntilNextRefresh_isATickWhenTheBoundaryIsFarOff() {
        XCTAssertEqual(TOTPCodeViewModel.delayUntilNextRefresh(expiresAt: date(60), at: date(30)),
                       TOTPCodeViewModel.tickInterval)
        XCTAssertEqual(TOTPCodeViewModel.delayUntilNextRefresh(expiresAt: nil, at: date(30)),
                       TOTPCodeViewModel.tickInterval)
    }

    func test_delayUntilNextRefresh_alignsToTheBoundary() {
        // Landing just after the boundary is what stops the row displaying a code for up to a second
        // after it stopped working.
        XCTAssertEqual(TOTPCodeViewModel.delayUntilNextRefresh(expiresAt: date(60), at: date(59)),
                       1.0 + TOTPCodeViewModel.boundaryOffset,
                       accuracy: 0.0001)
        XCTAssertEqual(TOTPCodeViewModel.delayUntilNextRefresh(expiresAt: date(60), at: date(59.6)),
                       0.4 + TOTPCodeViewModel.boundaryOffset,
                       accuracy: 0.0001)
    }

    func test_delayUntilNextRefresh_pastTheBoundaryStillSchedules() {
        // A zero or negative delay would be a timer that never fires again.
        XCTAssertGreaterThan(TOTPCodeViewModel.delayUntilNextRefresh(expiresAt: date(60), at: date(60.5)), 0)
        XCTAssertEqual(TOTPCodeViewModel.delayUntilNextRefresh(expiresAt: date(60), at: date(60.5)),
                       TOTPCodeViewModel.boundaryOffset,
                       accuracy: 0.0001)
    }

    // MARK: - Grouping

    func test_grouped_splitsSixSevenAndEightDigits() {
        XCTAssertEqual(TOTPCodeViewModel.grouped("123456"), "123 456")
        XCTAssertEqual(TOTPCodeViewModel.grouped("1234567"), "1234 567")
        XCTAssertEqual(TOTPCodeViewModel.grouped("12345678"), "1234 5678")
    }

    func test_grouped_leavesShortCodesAlone() {
        // A gap in four digits or fewer adds a space and no help.
        XCTAssertEqual(TOTPCodeViewModel.grouped("1234"), "1234")
        XCTAssertEqual(TOTPCodeViewModel.grouped("123"), "123")
        XCTAssertEqual(TOTPCodeViewModel.grouped(""), "")
    }

    // MARK: - The timer

    /// The only test here that lets real time pass.
    ///
    /// Everything above drives `refresh(at:)` directly, which is the point of injecting the clock —
    /// but it leaves the timer itself untested, and the timer is what makes the row live. A
    /// one-second step keeps the wait short.
    func test_timer_keepsTheCodeCurrentAndStopsWhenAsked() {
        let sut = TOTPCodeViewModel(itemId: "item",
                                    secret: "GEZDGNBV",
                                    generator: StepCodeGenerator(period: 1))

        sut.start()
        let first = sut.displayCode
        XCTAssertNotNil(first, "start() derives at once rather than waiting for the first tick")

        spin(1.4)
        XCTAssertNotEqual(sut.displayCode, first, "the timer should have rolled the code over")

        sut.stop()
        let atStop = sut.displayCode
        spin(1.4)
        XCTAssertEqual(sut.displayCode, atStop, "a stopped row must not keep deriving codes")
    }

    func test_start_isIdempotent() {
        // A second `start()` must not leave a second timer running: two timers double the work and
        // only one of them is ever invalidated.
        let sut = TOTPCodeViewModel(itemId: "item",
                                    secret: "GEZDGNBV",
                                    generator: StepCodeGenerator(period: 1))
        sut.start()
        sut.start()
        let first = sut.displayCode

        spin(1.4)
        XCTAssertNotEqual(sut.displayCode, first)
        sut.stop()
    }
}
