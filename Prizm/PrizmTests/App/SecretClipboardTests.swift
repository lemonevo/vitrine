import AppKit
import XCTest
@testable import Prizm

/// The quit-time clipboard rule: remove what we put there, and touch nothing else.
///
/// Every instance here is built over its own named `NSPasteboard`. `NSPasteboard.general` is shared by
/// all processes in the login session while the suite runs test classes in parallel processes, so
/// asserting on it would reproduce the cross-process coupling that already bit this project once
/// (`openspec/changes/fix-test-preference-isolation/`).
@MainActor
final class SecretClipboardTests: XCTestCase {

    /// A pasteboard only this process can see.
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.prizm.tests.\(UUID().uuidString)"))
    }

    func test_write_putsTheValueOnThePasteboardAndClaimsIt() {
        let sut = SecretClipboard(pasteboard: makePasteboard())
        sut.write("hunter2")

        XCTAssertTrue(sut.stillHolds("hunter2"))
        XCTAssertEqual(sut.ours, "hunter2")
    }

    func test_clearIfStillOurs_removesOurSecret() {
        let sut = SecretClipboard(pasteboard: makePasteboard())
        sut.write("hunter2")

        XCTAssertTrue(sut.clearIfStillOurs())
        XCTAssertNil(sut.ours, "The claim ends with the value")
        XCTAssertFalse(sut.clearIfStillOurs(), "A second sweep has nothing of ours to remove")
    }

    /// The user copied something else after us — here, another guard over the same pasteboard, which is
    /// the only way to produce a change this instance did not make. Wiping it on our exit would be the
    /// app destroying unrelated data, which is the whole reason the check exists.
    func test_clearIfStillOurs_leavesAReplacedClipboardAlone() {
        let board = makePasteboard()
        let sut        = SecretClipboard(pasteboard: board)
        let someOtherApp = SecretClipboard(pasteboard: board)

        sut.write("hunter2")
        someOtherApp.write("a shipping label the user copied afterwards")

        XCTAssertFalse(sut.clearIfStillOurs())
        XCTAssertTrue(sut.stillHolds("a shipping label the user copied afterwards"),
                      "Their clipboard, their copy")
    }

    /// A newer copy of ours replaces the older claim, so only the newest can ever be cleared.
    func test_write_twice_leavesTheFirstValueUnclaimed() {
        let sut = SecretClipboard(pasteboard: makePasteboard())
        sut.write("older")
        sut.write("newer")

        XCTAssertEqual(sut.ours, "newer")
        XCTAssertFalse(sut.stillHolds("older"))
    }

    func test_clearOnAnInstanceThatNeverWrote_doesNothing() {
        let board = makePasteboard()
        SecretClipboard(pasteboard: board).write("something somebody else put there")

        XCTAssertFalse(SecretClipboard(pasteboard: board).clearIfStillOurs(),
                       "A guard that never copied must not wipe the clipboard on the way out")
        XCTAssertTrue(SecretClipboard(pasteboard: board).stillHolds("something somebody else put there"))
    }
}
