import XCTest
import Combine
@testable import Prizm

@MainActor
final class UnlockViewModelBiometricTests: XCTestCase {

    private var sut:          UnlockViewModel!
    private var mockAuth:     MockAuthRepository!
    private var mockSync:     MockSyncUseCase!
    private var cancellables: Set<AnyCancellable> = []

    private let stubAccount = Account(
        userId:            "user-001",
        email:             "alice@example.com",
        name:              nil,
        serverEnvironment: ServerEnvironment(
            base:      URL(string: "https://vault.example.com")!,
            overrides: nil
        )
    )

    override func setUp() async throws {
        try await super.setUp()
        mockAuth = MockAuthRepository()
        mockSync = MockSyncUseCase()
        sut      = UnlockViewModel(auth: mockAuth, sync: mockSync, account: stubAccount)
        UserDefaults.standard.removeObject(forKey: "biometricUnlockEnabled")
        UserDefaults.standard.removeObject(forKey: "biometricEnrollmentPromptShown")
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        UserDefaults.standard.removeObject(forKey: "biometricUnlockEnabled")
        UserDefaults.standard.removeObject(forKey: "biometricEnrollmentPromptShown")
        try await super.tearDown()
    }

    // MARK: - biometricUnlockAvailable

    func testBiometricUnlockAvailable_reflectsAuthRepository() {
        mockAuth.stubbedBiometricUnlockAvailable = true
        XCTAssertTrue(sut.biometricUnlockAvailable)
        mockAuth.stubbedBiometricUnlockAvailable = false
        XCTAssertFalse(sut.biometricUnlockAvailable)
    }

    /// Lets the ViewModel's inner `Task` run to completion.
    ///
    /// Awaiting a sleep rather than spinning a `RunLoop`: an `async` test body occupies the main
    /// actor, so continuations queued onto it do not resume while the run loop is turning.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - requestBiometricUnlock: success

    func testRequestBiometricUnlock_success_callsAuth() async {
        mockAuth.stubbedBiometricUnlockAvailable = true

        sut.requestBiometricUnlock()
        await settle()

        XCTAssertTrue(mockAuth.unlockWithBiometricsCalled)
    }

    // MARK: - requestBiometricUnlock: availability

    func testRequestBiometricUnlock_notAvailable_noOp() async {
        mockAuth.stubbedBiometricUnlockAvailable = false

        sut.requestBiometricUnlock()
        await settle()

        XCTAssertFalse(mockAuth.unlockWithBiometricsCalled)
    }

    // MARK: - requestBiometricUnlock: dismissal

    func testRequestBiometricUnlock_cancelled_showsNoError() async {
        mockAuth.stubbedBiometricUnlockAvailable = true
        mockAuth.unlockWithBiometricsError = NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(errSecUserCanceled),
            userInfo: nil
        )

        sut.requestBiometricUnlock()
        await settle()

        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.flowState, .unlock)
    }

    /// Dismissing the prompt must NOT raise another one.
    ///
    /// The old behaviour was "always armed": every cancellation triggered another evaluation. That was
    /// tolerable while the prompt was an icon in this window. It is a modal now, and a modal that
    /// reappears the moment it is dismissed is a loop the user cannot leave — so the retry belongs to
    /// the button, not to the ViewModel.
    func testRequestBiometricUnlock_cancelled_doesNotRePrompt() async {
        mockAuth.stubbedBiometricUnlockAvailable = true
        mockAuth.unlockWithBiometricsError = NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(errSecUserCanceled),
            userInfo: nil
        )

        sut.requestBiometricUnlock()
        await settle()

        XCTAssertEqual(mockAuth.unlockWithBiometricsCallCount, 1)
    }

    /// A second request while the system prompt is still up is dropped.
    ///
    /// Each `evaluatePolicy` raises its own dialog, so two clicks would mean two dialogs to dismiss.
    func testRequestBiometricUnlock_whilePromptIsInFlight_ignoresSecondRequest() async {
        mockAuth.stubbedBiometricUnlockAvailable = true
        mockAuth.unlockWithBiometricsDelay = .milliseconds(200)

        sut.requestBiometricUnlock()
        sut.requestBiometricUnlock()
        sut.requestBiometricUnlock()
        await settle()

        XCTAssertEqual(mockAuth.unlockWithBiometricsCallCount, 1)
    }

    /// The guard has to release once the attempt is over, or the button would answer only once per
    /// launch.
    func testRequestBiometricUnlock_afterAttemptCompletes_canAskAgain() async {
        mockAuth.stubbedBiometricUnlockAvailable = true

        sut.requestBiometricUnlock()
        await settle()
        sut.requestBiometricUnlock()
        await settle()

        XCTAssertEqual(mockAuth.unlockWithBiometricsCallCount, 2)
    }

    // MARK: - requestBiometricUnlock: invalidation

    func testRequestBiometricUnlock_invalidated_showsErrorMessage() async {
        mockAuth.stubbedBiometricUnlockAvailable = true
        mockAuth.unlockWithBiometricsError = AuthError.biometricInvalidated

        sut.requestBiometricUnlock()
        await settle()

        XCTAssertNotNil(sut.errorMessage)
    }

    /// The sentence `openspec/specs/biometric-unlock/spec.md` mandates. It is asserted here rather
    /// than only in `BiometricUnlockJourneyTests` because that UI test is not built into any target
    /// and its assertion is wrapped in `if error.waitForExistence { … }`, so it cannot fail even if it
    /// were run. This one runs.
    func testRequestBiometricUnlock_lockout_showsTheSpecifiedSentence() async {
        mockAuth.stubbedBiometricUnlockAvailable = true
        mockAuth.unlockWithBiometricsError = AuthError.biometricLockout

        sut.requestBiometricUnlock()
        await settle()

        XCTAssertEqual(
            sut.errorMessage,
            "Too many failed Touch ID attempts — enter your master password",
            "The message has to name the cause and the way out, not the framework's error text"
        )
    }

    func testRequestBiometricUnlock_itemNotFound_showsNoError() async {
        mockAuth.stubbedBiometricUnlockAvailable = true
        mockAuth.unlockWithBiometricsError = AuthError.biometricItemNotFound

        sut.requestBiometricUnlock()
        await settle()

        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Enrollment prompt (modal sheet via showEnrollmentPrompt)

    func testDismissEnrollmentPrompt_transitionsToVault() async {
        // Drive enrollment state through the real unlock flow:
        // biometrics capable + not enabled + prompt never shown → showEnrollmentPrompt = true
        mockAuth.stubbedDeviceBiometricCapable = true
        UserDefaults.standard.set(false, forKey: "biometricUnlockEnabled")
        UserDefaults.standard.set(false, forKey: "biometricEnrollmentPromptShown")

        let enrollExp = expectation(description: "enrollment prompt shown")
        sut.$showEnrollmentPrompt
            .filter { $0 == true }
            .first()
            .sink { _ in enrollExp.fulfill() }
            .store(in: &cancellables)

        sut.password = "TestPassword1!"
        sut.unlock()
        await fulfillment(of: [enrollExp], timeout: 3.0)

        let vaultExp = expectation(description: "transitions to vault after dismiss")
        sut.$flowState
            .filter { $0 == .vault }
            .first()
            .sink { _ in vaultExp.fulfill() }
            .store(in: &cancellables)

        sut.dismissEnrollmentPrompt()
        await fulfillment(of: [vaultExp], timeout: 3.0)

        XCTAssertFalse(sut.showEnrollmentPrompt)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricEnrollmentPromptShown"))
    }

    func testConfirmEnrollBiometric_transitionsToVault() async {
        mockAuth.stubbedDeviceBiometricCapable = true
        UserDefaults.standard.set(false, forKey: "biometricUnlockEnabled")
        UserDefaults.standard.set(false, forKey: "biometricEnrollmentPromptShown")

        let enrollExp = expectation(description: "enrollment prompt shown")
        sut.$showEnrollmentPrompt
            .filter { $0 == true }
            .first()
            .sink { _ in enrollExp.fulfill() }
            .store(in: &cancellables)

        sut.password = "TestPassword1!"
        sut.unlock()
        await fulfillment(of: [enrollExp], timeout: 3.0)

        let vaultExp = expectation(description: "transitions to vault after confirm")
        sut.$flowState
            .filter { $0 == .vault }
            .first()
            .sink { _ in vaultExp.fulfill() }
            .store(in: &cancellables)

        sut.confirmEnrollBiometric()
        await fulfillment(of: [vaultExp], timeout: 3.0)

        XCTAssertFalse(sut.showEnrollmentPrompt)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "biometricEnrollmentPromptShown"))
    }

    func testEnrollmentPrompt_reason_isFirstTime_onInitialUnlock() async {
        mockAuth.stubbedDeviceBiometricCapable = true
        UserDefaults.standard.set(false, forKey: "biometricUnlockEnabled")
        UserDefaults.standard.set(false, forKey: "biometricEnrollmentPromptShown")

        let exp = expectation(description: "enrollment prompt shown with .firstTime reason")
        sut.$showEnrollmentPrompt
            .filter { $0 == true }
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.password = "TestPassword1!"
        sut.unlock()
        await fulfillment(of: [exp], timeout: 3.0)

        XCTAssertEqual(sut.enrollmentReason, .firstTime)
    }
}
