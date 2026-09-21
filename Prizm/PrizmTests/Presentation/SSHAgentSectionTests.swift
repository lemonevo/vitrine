import XCTest
@testable import Prizm

// MARK: - SSHAgentSectionTests

/// What the SSH agent pane says, and the shell line it hands out.
///
/// Both are pure derivations, and that is why they are values rather than `if`s inside the view:
/// the *ordering* between the states is the part that can be wrong, and a wrong order here is a
/// pane that reports an agent as healthy when it never bound a socket. `ssh` reports that failure
/// as "the agent refused" and nothing else, so this pane is the only place the cause can surface.
@MainActor
final class SSHAgentSectionTests: XCTestCase {

    // MARK: - Status

    func testOff_whenDisabled() {
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: false, isRunning: false, failure: nil), .off)
    }

    /// The state a user is most likely to misread: the switch is on and the pane agrees, but
    /// nothing is listening until the vault opens. It is neither `off` nor `listening`, and
    /// collapsing it into either one would misdescribe what the user is about to see in a terminal.
    func testWaitingForUnlock_whenEnabledAndNotRunning() {
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: true, isRunning: false, failure: nil),
                       .waitingForUnlock)
    }

    func testListening_whenEnabledAndRunning() {
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: true, isRunning: true, failure: nil),
                       .listening)
    }

    func testFailed_whenEnabledAndAStartWasRecorded() {
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: true, isRunning: false, failure: "boom"),
                       .failed(reason: "boom"))
    }

    /// A recorded failure outranks a running socket.
    ///
    /// `isRunning` can still be true from an earlier successful start while a later attempt failed,
    /// so reading the two in the other order would print "Listening" over the top of a failure the
    /// user needs to see. This is the one ordering the pane must not get wrong.
    func testAFailureOutranksRunning() {
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: true, isRunning: true, failure: "boom"),
                       .failed(reason: "boom"))
    }

    /// And it outranks "waiting", so a failed start is never presented as merely not-yet-unlocked.
    /// The two ask completely different things of the user — unlock, versus go fix the path.
    func testAFailureOutranksWaiting() {
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: true, isRunning: false, failure: "boom"),
                       .failed(reason: "boom"))
    }

    /// Switched off wins over everything, including a leftover failure.
    ///
    /// `setEnabled(false)` clears the coordinator's `failure`, so this cannot arise today. It is
    /// asserted anyway because the derivation should not depend on that: a red error sitting under
    /// a switch the user has turned off reads as a broken control.
    func testOff_outranksEverything() {
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: false, isRunning: true, failure: nil), .off)
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: false, isRunning: false, failure: "boom"), .off)
    }

    /// The reason is carried through verbatim rather than summarised. The coordinator records a
    /// sentence naming the cause; replacing it with "unavailable" would put the user back at the
    /// terminal message this pane exists to explain.
    func testTheReasonIsCarriedThroughUnchanged() {
        let reason = "The socket path is too long for this filesystem — pick a shorter one."
        XCTAssertEqual(SSHAgentStatus.of(isEnabled: true, isRunning: false, failure: reason),
                       .failed(reason: reason))
    }

    // MARK: - Shell setup

    /// The quotes are load-bearing. The default socket lives under
    /// `~/Library/Application Support/Prizm/…`; unquoted, that space splits the assignment,
    /// `SSH_AUTH_SOCK` ends up empty, and `ssh` silently falls back to `~/.ssh` — which looks
    /// exactly like the agent being broken.
    func testTheExportLineQuotesAPathWithSpaces() {
        let path = "/Users/someone/Library/Application Support/Prizm/ssh-agent/agent.sock"
        XCTAssertEqual(SSHAgentShellSetup.exportLine(socketPath: path),
                       "export SSH_AUTH_SOCK=\"/Users/someone/Library/Application Support/Prizm/ssh-agent/agent.sock\"")
    }

    /// Quoted even when there is nothing to quote, so the line has one shape rather than two.
    func testTheExportLineQuotesEvenWhenThereIsNothingToQuote() {
        XCTAssertEqual(SSHAgentShellSetup.exportLine(socketPath: "/tmp/a.sock"),
                       "export SSH_AUTH_SOCK=\"/tmp/a.sock\"")
    }

    /// One line, one assignment, exactly two quotes, no backslashes. The line is meant to be pasted
    /// into a profile or `eval`ed, and either of those breaks on a stray newline or escape.
    func testTheExportLineIsASingleAssignment() {
        let line = SSHAgentShellSetup.exportLine(socketPath: "/tmp/prizm/agent.sock")
        XCTAssertEqual(line.split(separator: "\n").count, 1)
        XCTAssertEqual(line.filter { $0 == "\"" }.count, 2)
        XCTAssertFalse(line.contains("\\"))
        XCTAssertTrue(line.hasPrefix("export SSH_AUTH_SOCK="))
    }

    /// The path reaches the line unmodified — no `~`, no percent-encoding, no trimming. `ssh`
    /// resolves it as a literal path, so a "prettier" form here would point at nothing.
    func testThePathIsNotRewritten() {
        let path = "/tmp/prizm-ssh-agent-tests/agent.sock"
        XCTAssertTrue(SSHAgentShellSetup.exportLine(socketPath: path).contains(path))
    }

    // MARK: - Identifiers

    /// The pane's identifiers are prefixed apart from the signature-request sheet's, and the two can
    /// be on screen at once. An identifier matching two controls is worse than none — the test that
    /// queries it would pass against the wrong one.
    func testThePanesIdentifiersCannotCollideWithTheSheets() {
        let pane: [String] = [
            AccessibilityID.SSHAgent.settingsToggle,
            AccessibilityID.SSHAgent.status,
            AccessibilityID.SSHAgent.socketPath,
            AccessibilityID.SSHAgent.copySocket,
            AccessibilityID.SSHAgent.exportLine,
            AccessibilityID.SSHAgent.copyExportLine,
            AccessibilityID.SSHAgent.noKeys,
            AccessibilityID.SSHAgent.usableKey,
            AccessibilityID.SSHAgent.unusableKey,
        ]
        let sheet: [String] = [
            AccessibilityID.SSHAgent.requestDescription,
            AccessibilityID.SSHAgent.passwordField,
            AccessibilityID.SSHAgent.error,
            AccessibilityID.SSHAgent.cancelButton,
            AccessibilityID.SSHAgent.confirmButton,
        ]

        for id in pane  { XCTAssertTrue(id.hasPrefix("sshAgent.settings."), id) }
        for id in sheet { XCTAssertFalse(id.hasPrefix("sshAgent.settings."), id) }
        XCTAssertEqual(Set(pane + sheet).count, pane.count + sheet.count)
    }
}
