import XCTest
@testable import Prizm

/// The master-password gate in front of every SSH signature.
///
/// Most of these assert on the **negative** side: a request that is never answered must not sign,
/// a wrong password must not grant, and a grant must not outlive the session that issued it. Those
/// are the failures that produce no error anywhere — a signature that should not have happened
/// looks exactly like one that should.
@MainActor
final class SSHAgentAuthorizerTests: XCTestCase {

    private var verify: MockVerifyMasterPasswordUseCase!
    private var sut:    SSHAgentAuthorizer!

    private let deployKey  = SSHAgentIdentity(itemId: "key-1", blob: Data([1]), comment: "Deploy Key")
    private let backupKey  = SSHAgentIdentity(itemId: "key-2", blob: Data([2]), comment: "Backup Key")

    override func setUp() {
        super.setUp()
        verify = MockVerifyMasterPasswordUseCase()
        sut    = SSHAgentAuthorizer(verifyMasterPassword: verify)
    }

    /// Polls rather than sleeping a fixed amount: the gate's transitions happen on the main actor
    /// between awaits, and a fixed sleep is either slower than it needs to be or flaky.
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    // MARK: - Asking

    func testFirstRequest_asksBeforeAnythingIsSigned() async {
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }

        await waitUntil { self.sut.pending != nil }

        XCTAssertEqual(sut.pending?.itemId, "key-1")
        XCTAssertEqual(sut.pending?.itemName, "Deploy Key")
        XCTAssertEqual(sut.pending?.process, "git")
        XCTAssertFalse(sut.isVerifying)
        // Nothing has been decided, so nothing may be answered.
        XCTAssertFalse(request.isCancelled)
        request.cancel()
    }

    func testCorrectPassword_grantsAndAnswersTheRequest() async {
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        sut.submit(Data("right".utf8))
        let allowed = await request.value

        XCTAssertTrue(allowed)
        XCTAssertNil(sut.pending)
        XCTAssertNil(sut.error)
        XCTAssertFalse(sut.needsAuthorization(for: "key-1"))
        XCTAssertEqual(verify.submitted, [Data("right".utf8)])
    }

    /// A wrong password keeps the sheet open and grants nothing. Closing on a wrong answer would be
    /// indistinguishable from a cancel, and the user would not know which happened.
    func testWrongPassword_grantsNothingAndKeepsTheSheetOpen() async {
        verify.stubbedResult = false
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        sut.submit(Data("wrong".utf8))
        await waitUntil { self.sut.error != nil }

        XCTAssertNotNil(sut.pending, "the sheet must stay open for a retry")
        XCTAssertTrue(sut.needsAuthorization(for: "key-1"))
        XCTAssertFalse(sut.isVerifying)

        // The retry works, which is the point of staying open.
        verify.stubbedResult = true
        sut.submit(Data("right".utf8))
        let allowed = await request.value
        XCTAssertTrue(allowed)
    }

    /// "Could not check" is shown rather than swallowed: a sheet that stays open with no message is
    /// indistinguishable from one that is broken.
    func testCheckThatThrows_showsTheReasonAndGrantsNothing() async {
        struct Broken: LocalizedError {
            var errorDescription: String? { "the key derivation failed" }
        }
        verify.stubbedError = Broken()
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        sut.submit(Data("anything".utf8))
        await waitUntil { self.sut.error != nil }

        XCTAssertEqual(sut.error, "the key derivation failed")
        XCTAssertTrue(sut.needsAuthorization(for: "key-1"))
        request.cancel()
    }

    func testCancel_answersFalseAndGrantsNothing() async {
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        sut.cancel()
        let allowed = await request.value

        XCTAssertFalse(allowed)
        XCTAssertNil(sut.pending)
        XCTAssertTrue(sut.needsAuthorization(for: "key-1"))
        XCTAssertEqual(verify.callCount, 0, "a cancel must not even check a password")
    }

    // MARK: - The grant is per key, per session

    func testSecondRequestForTheSameKey_doesNotAskAgain() async {
        let first = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }
        sut.submit(Data("right".utf8))
        _ = await first.value

        let second = Task { await sut.authorize(deployKey, requestedBy: "ssh") }
        let allowed = await second.value

        XCTAssertTrue(allowed)
        XCTAssertNil(sut.pending, "the second request must not have queued a prompt")
        XCTAssertEqual(verify.callCount, 1)
    }

    func testADifferentKey_asksAgain() async {
        let first = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }
        sut.submit(Data("right".utf8))
        _ = await first.value

        let second = Task { await sut.authorize(backupKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        XCTAssertEqual(sut.pending?.itemId, "key-2")
        sut.submit(Data("right".utf8))
        let secondAllowed = await second.value
        XCTAssertTrue(secondAllowed)
        XCTAssertEqual(verify.callCount, 2)
    }

    /// Two clients can ask for the same key before either is answered. Making the user answer twice
    /// for one key would be a prompt they cannot tell apart from a bug.
    func testTwoRequestsForTheSameKey_areAnsweredByOnePassword() async {
        let first  = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }
        let second = Task { await sut.authorize(deployKey, requestedBy: "ssh") }
        await waitUntil { self.sut.waitingCount == 2 }

        sut.submit(Data("right".utf8))

        let firstAllowed = await first.value
        XCTAssertTrue(firstAllowed)
        let secondAllowed = await second.value
        XCTAssertTrue(secondAllowed)
        XCTAssertEqual(verify.callCount, 1)
    }

    /// Two different keys are asked one at a time, in the order they arrived — never two sheets at
    /// once, which on macOS would be a second sheet replacing the first with no way to answer it.
    func testTwoDifferentKeys_areAskedOneAtATime() async {
        let first  = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }
        let second = Task { await sut.authorize(backupKey, requestedBy: "ssh") }
        await waitUntil { self.sut.waitingCount == 2 }

        XCTAssertEqual(sut.pending?.itemId, "key-1")

        sut.submit(Data("right".utf8))
        await waitUntil { self.sut.pending?.itemId == "key-2" }
        XCTAssertEqual(sut.pending?.itemId, "key-2")

        sut.submit(Data("right".utf8))
        let firstAllowed = await first.value
        XCTAssertTrue(firstAllowed)
        let secondAllowed = await second.value
        XCTAssertTrue(secondAllowed)
    }

    // MARK: - Revocation

    /// The teardown path. A grant is permission to use key material, so it must not outlive the
    /// caches that hold it — and a request left suspended would be a socket thread blocked forever
    /// on a prompt that can never be answered.
    func testRevokeAll_answersEverythingWaitingFalseAndForgetsTheGrants() async {
        let first = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }
        sut.submit(Data("right".utf8))
        let firstAllowed = await first.value
        XCTAssertTrue(firstAllowed)
        XCTAssertFalse(sut.needsAuthorization(for: "key-1"))

        let waiting = Task { await sut.authorize(backupKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        sut.revokeAll()

        let waitingAllowed = await waiting.value
        XCTAssertFalse(waitingAllowed)
        XCTAssertNil(sut.pending)
        XCTAssertTrue(sut.needsAuthorization(for: "key-1"), "a grant must not survive a lock")
        XCTAssertTrue(sut.needsAuthorization(for: "key-2"))
    }

    /// The interleaving that matters: the password checks out, but the vault locked while it was
    /// being checked. Granting then would hand out permission the lock had already taken back.
    ///
    /// The assertion that matters is the one made **after** the in-flight check finishes. Asserting
    /// only right after `revokeAll()` would pass whether or not the guard existed, because the
    /// grant set has just been emptied either way — a test that cannot fail is not evidence.
    func testRevokeAll_whileThePasswordIsBeingChecked_doesNotGrant() async {
        verify.stubbedDelay = 0.25
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        sut.submit(Data("right".utf8))
        await waitUntil { self.sut.isVerifying }
        // Revoked mid-check: the vault locked between the submission and the answer.
        sut.revokeAll()

        // Past the stubbed delay, so the check has returned `true` and had its chance to grant.
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(verify.callCount, 1, "the check must actually have run for this to prove anything")
        let requestAllowed = await request.value
        XCTAssertFalse(requestAllowed)
        XCTAssertTrue(sut.needsAuthorization(for: "key-1"),
                      "a check that finished after the lock must not grant anything")
    }

    /// Revoking twice must not resume a continuation twice, which would trap.
    func testRevokeAll_isSafeToCallWhenNothingIsWaiting() {
        sut.revokeAll()
        sut.revokeAll()
        XCTAssertNil(sut.pending)
    }

    func testCancel_isSafeToCallWhenNothingIsPending() {
        sut.cancel()
        XCTAssertNil(sut.pending)
        XCTAssertEqual(verify.callCount, 0)
    }

    // MARK: - The answer window

    /// An ignored prompt used to park the agent's connection thread indefinitely: the responder was
    /// suspended on this continuation and `SSHAgentServer.awaitResponse(to:)` was suspended on the
    /// responder, so the `git` that asked hung until the app quit.
    func testUnansweredPrompt_isRefusedWhenTheWindowCloses() async throws {
        sut = SSHAgentAuthorizer(verifyMasterPassword: verify, answerWindow: 0.15)
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }

        let allowed = await request.value

        XCTAssertFalse(allowed, "an expired request signs nothing")
        XCTAssertNil(sut.pending)
        XCTAssertEqual(verify.callCount, 0, "nothing was ever typed, so nothing should be checked")
    }

    /// A request queued behind the one on screen has not been shown, so its clock has not started.
    /// Timing from arrival would let the app refuse a prompt nobody has seen yet.
    func testQueuedRequest_isNotRefusedBeforeItIsShown() async {
        sut = SSHAgentAuthorizer(verifyMasterPassword: verify, answerWindow: 0.4)
        let first  = Task { await sut.authorize(deployKey, requestedBy: "git") }
        let second = Task { await sut.authorize(backupKey, requestedBy: "ssh") }
        await waitUntil { self.sut.waitingCount == 2 }

        // Past the first window and into the second's: key-1 has expired, key-2 is only now on screen.
        try? await Task.sleep(nanoseconds: 600_000_000)
        let firstAnswer = await first.value
        XCTAssertFalse(firstAnswer)
        XCTAssertEqual(sut.pending?.itemId, "key-2",
                       "the second request gets its own window rather than the remainder of the first")

        let secondAnswer = await second.value
        XCTAssertFalse(secondAnswer)
    }

    /// The deadline is a backstop for an ignored prompt, not a race the user has to win.
    func testAnsweredRequest_outlivesItsOwnDeadline() async {
        sut = SSHAgentAuthorizer(verifyMasterPassword: verify, answerWindow: 0.2)
        let request = Task { await sut.authorize(deployKey, requestedBy: "git") }
        await waitUntil { self.sut.pending != nil }
        sut.submit(Data("right".utf8))
        let answered = await request.value
        XCTAssertTrue(answered)

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(sut.needsAuthorization(for: "key-1"),
                       "a grant must not be revoked by the deadline armed before it was answered")
    }
}
