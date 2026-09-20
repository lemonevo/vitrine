import XCTest
@testable import Prizm

/// Covers the re-prompt gate: `RootViewModel`'s grants and `VaultBrowserViewModel`'s sheet.
///
/// The grant and the sheet are two objects, so the property under test is really the seam between
/// them — that the browser can *ask* and cannot *issue*. Several cases here exist to pin that
/// direction down.
///
/// **What is not covered.** The password check itself: `MockVerifyMasterPasswordUseCase` decides
/// the answer, so these tests say nothing about whether a password is correct. That is
/// `AuthRepositoryVerifyMasterPasswordTests`.
@MainActor
final class RepromptGateTests: XCTestCase {

    private var deps: MockRootDependencies!
    private var sut:  RootViewModel!
    private var browser: VaultBrowserViewModel { sut.vaultBrowserVM }

    override func setUp() async throws {
        try await super.setUp()
        deps = MockRootDependencies(auth: MockAuthRepository(), vault: MockVaultRepository())
        sut  = RootViewModel(container: deps)
    }

    // MARK: - Fixtures

    private func makeItem(id: String, reprompt: Int) -> VaultItem {
        VaultItem(
            id: id, name: "Item \(id)", isFavorite: false, isDeleted: false,
            creationDate: Date(timeIntervalSince1970: 0),
            revisionDate: Date(timeIntervalSince1970: 0),
            content: .login(LoginContent(username: "user", password: "secret", uris: [],
                                         totp: nil, notes: nil, customFields: [])),
            reprompt: reprompt
        )
    }

    /// Polls until `condition` holds. The gate resolves in a detached `Task`, so a single yield is
    /// not enough — and a fixed sleep would be either flaky or slow.
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Who is asked

    func testProtectedItem_asksBeforeRunning() {
        let item = makeItem(id: "a", reprompt: 1)
        browser.itemSelection = item
        var ran = false

        browser.performGated(itemId: item.id) { ran = true }

        XCTAssertNotNil(browser.pendingReprompt, "a protected item must not run its action yet")
        XCTAssertFalse(ran)
    }

    func testUnprotectedItem_neverAsks() {
        let item = makeItem(id: "b", reprompt: 0)
        browser.itemSelection = item
        var ran = false

        browser.performGated(itemId: item.id) { ran = true }

        XCTAssertNil(browser.pendingReprompt, "an item without the flag must never prompt")
        XCTAssertTrue(ran)
    }

    // MARK: - The grant

    func testCorrectPassword_grantsAndReveals() async {
        let item = makeItem(id: "c", reprompt: 1)
        browser.itemSelection = item

        browser.requestReveal(itemId: item.id)
        XCTAssertFalse(browser.isRevealed(item.id),
                       "nothing may be revealed before the password has checked out")

        browser.submitReprompt(Data("correct".utf8))
        await waitUntil { browser.isRevealed(item.id) }

        XCTAssertNil(browser.pendingReprompt, "the sheet must close on a correct answer")
        XCTAssertTrue(sut.repromptGrants.contains(item.id))
    }

    /// The reason the *action* is deferred rather than its result: it is the only way a gated copy
    /// happens after the grant and not before it.
    func testGatedActionRunsOnlyAfterTheGrant() async {
        let item = makeItem(id: "c2", reprompt: 1)
        browser.itemSelection = item
        var copies = 0

        browser.performGated(itemId: item.id) { copies += 1 }
        XCTAssertEqual(copies, 0, "the action must not run while the password is outstanding")

        browser.submitReprompt(Data("correct".utf8))
        await waitUntil { copies == 1 }

        XCTAssertEqual(copies, 1, "and it must run exactly once, not once per render")
    }

    /// A wrong password is an answer, not a fault: no grant, nothing revealed, the sheet stays open
    /// and says why. Closing instead would be indistinguishable from a cancel.
    func testWrongPassword_doesNotGrant() async {
        deps.verifyMasterPasswordUseCase.stubbedResult = false
        let item = makeItem(id: "d", reprompt: 1)
        browser.itemSelection = item
        var ran = false

        browser.performGated(itemId: item.id) { ran = true }
        browser.submitReprompt(Data("wrong".utf8))
        await waitUntil { browser.repromptError != nil }

        XCTAssertFalse(ran)
        XCTAssertFalse(browser.isRevealed(item.id))
        XCTAssertFalse(sut.repromptGrants.contains(item.id))
        XCTAssertNotNil(browser.pendingReprompt, "the sheet must stay open")
        XCTAssertNotNil(browser.repromptError)
    }

    /// "Could not check" must not be flattened into "wrong password" — the two need different
    /// handling, and a Bool cannot carry both.
    func testCouldNotCheck_surfacesTheError() async {
        deps.verifyMasterPasswordUseCase.stubbedError = AuthError.noStoredSession
        let item = makeItem(id: "e", reprompt: 1)
        browser.itemSelection = item
        var ran = false

        browser.performGated(itemId: item.id) { ran = true }
        browser.submitReprompt(Data("anything".utf8))
        await waitUntil { browser.repromptError != nil }

        XCTAssertFalse(ran)
        XCTAssertNotNil(browser.pendingReprompt)
    }

    func testCancel_grantsNothing() {
        let item = makeItem(id: "f", reprompt: 1)
        browser.itemSelection = item
        var ran = false

        browser.performGated(itemId: item.id) { ran = true }
        browser.cancelReprompt()

        XCTAssertFalse(ran)
        XCTAssertFalse(browser.isRevealed(item.id))
        XCTAssertFalse(sut.repromptGrants.contains(item.id))
        XCTAssertNil(browser.pendingReprompt)
    }

    /// The grant is per item, which is the property that makes "this item was unlocked" a statement
    /// the user can reason about.
    func testGrantIsPerItem() async {
        let a = makeItem(id: "g", reprompt: 1)
        let b = makeItem(id: "h", reprompt: 1)
        browser.itemSelection = a

        browser.performGated(itemId: a.id) { }
        browser.submitReprompt(Data("correct".utf8))
        await waitUntil { sut.repromptGrants.contains(a.id) }

        browser.itemSelection = b
        var ranForB = false
        browser.performGated(itemId: b.id) { ranForB = true }

        XCTAssertNotNil(browser.pendingReprompt, "item B must still be asked")
        XCTAssertFalse(ranForB)
    }

    /// Once granted, further disclosures in the same session do not ask again.
    func testGrantCoversTheRestOfTheSession() async {
        let item = makeItem(id: "i", reprompt: 1)
        browser.itemSelection = item

        browser.performGated(itemId: item.id) { }
        browser.submitReprompt(Data("correct".utf8))
        await waitUntil { sut.repromptGrants.contains(item.id) }

        var second = false
        var third  = false
        browser.performGated(itemId: item.id) { second = true }
        browser.performGated(itemId: item.id) { third = true }

        XCTAssertNil(browser.pendingReprompt)
        XCTAssertTrue(second)
        XCTAssertTrue(third)
        XCTAssertEqual(deps.verifyMasterPasswordUseCase.callCount, 1,
                       "the master password must be asked for once per item per session")
    }

    // MARK: - Teardown

    func testLockClearsGrants() async {
        let item = makeItem(id: "j", reprompt: 1)
        browser.itemSelection = item
        browser.performGated(itemId: item.id) { }
        browser.submitReprompt(Data("correct".utf8))
        await waitUntil { sut.repromptGrants.contains(item.id) }

        // Set here rather than in `setUp`: the login-flow subscription fires on subscription and
        // moves `screen` off `.vault`, and `lockVault()` is a no-op unless the vault reads as
        // unlocked — which would make this pass for the wrong reason.
        sut.screen = .vault
        XCTAssertTrue(sut.isVaultUnlocked, "precondition: the lock path does nothing otherwise")

        sut.lockVault()
        await waitUntil { sut.repromptGrants.isEmpty }

        XCTAssertTrue(sut.repromptGrants.isEmpty)
        XCTAssertFalse(browser.isRevealed(item.id), "the reveal must go with the grant")
    }

    func testSignOutClearsGrants() async {
        let item = makeItem(id: "k", reprompt: 1)
        browser.itemSelection = item
        browser.performGated(itemId: item.id) { }
        browser.submitReprompt(Data("correct".utf8))
        await waitUntil { sut.repromptGrants.contains(item.id) }

        sut.signOut()
        await waitUntil { sut.repromptGrants.isEmpty }

        XCTAssertTrue(sut.repromptGrants.isEmpty)
    }

    // MARK: - What is gated

    /// The username is the exclusion that matters: the copy-username command exists precisely
    /// because it is the safe half, so gating it would remove its reason to exist.
    func testCopyableField_onlySecretsAreGated() {
        XCTAssertFalse(RootViewModel.CopyableField.username.isGated)
        XCTAssertFalse(RootViewModel.CopyableField.website.isGated)
        XCTAssertTrue(RootViewModel.CopyableField.password.isGated)
        XCTAssertTrue(RootViewModel.CopyableField.totp.isGated)
    }

    /// Changing the selection must not carry a reveal over to a different item.
    func testChangingSelectionClearsReveals() {
        let a = makeItem(id: "l", reprompt: 0)
        let b = makeItem(id: "m", reprompt: 0)
        browser.itemSelection = a
        browser.requestReveal(itemId: a.id)
        XCTAssertTrue(browser.isRevealed(a.id))

        browser.itemSelection = b

        XCTAssertFalse(browser.isRevealed(a.id))
    }
}
