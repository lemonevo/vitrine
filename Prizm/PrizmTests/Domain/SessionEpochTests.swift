import XCTest
@testable import Prizm

/// `SessionEpoch` — the token every session-scoped operation carries so that work started in one
/// session cannot write into the next.
///
/// What matters is not that it counts, but that a token is never reissued: a boolean "is locked"
/// would let a sync from session A land in session B, because B is also unlocked.
@MainActor
final class SessionEpochTests: XCTestCase {

    func testFreshEpoch_reportsItsTokenAsCurrent() {
        let sut = SessionEpoch()

        let token = sut.current()

        let isCurrent = sut.isCurrent(token)
        XCTAssertTrue(isCurrent)
    }

    func testAdvance_invalidatesThePreviousToken() {
        let sut = SessionEpoch()
        let first = sut.current()

        sut.advance()

        let isCurrent = sut.isCurrent(first)
        XCTAssertFalse(isCurrent, "the session that issued the token has ended")
    }

    func testAdvance_issuesADistinctToken() {
        let sut = SessionEpoch()
        let first = sut.current()

        sut.advance()

        let second = sut.current()
        XCTAssertNotEqual(first, second)

        let isCurrent = sut.isCurrent(second)
        XCTAssertTrue(isCurrent)
    }

    /// The property that distinguishes a counter from a flag: after two sessions have ended, the
    /// first session's token must not become current again.
    func testTokensAreNeverReissued() {
        let sut = SessionEpoch()
        let first = sut.current()

        sut.advance()
        sut.advance()

        let firstStillCurrent = sut.isCurrent(first)
        XCTAssertFalse(firstStillCurrent)

        let third = sut.current()
        let thirdIsCurrent = sut.isCurrent(third)
        XCTAssertTrue(thirdIsCurrent)
        XCTAssertNotEqual(first, third)
    }

    /// Two epochs are independent — an epoch built for one consumer must not be invalidated by
    /// advancing another. This is what would break if the type were a global or a static.
    func testEpochsAreIndependent() {
        let a = SessionEpoch()
        let b = SessionEpoch()
        let tokenA = a.current()

        b.advance()

        let aStillCurrent = a.isCurrent(tokenA)
        XCTAssertTrue(aStillCurrent)
    }
}
