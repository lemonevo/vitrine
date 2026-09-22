import Combine
import XCTest
@testable import Prizm

/// The unlock screen asks for one credential at a time, and everything that reads as "which one" has
/// to agree: the subtitle, the field, the switch, the attempt count, and what a submission sends.
///
/// Before this, the screen drew a master-password box and a PIN box at the same weight and put the
/// PIN's remaining-attempts line under both — so a wrong *password* was answered with a count of PIN
/// tries. These tests are the reason that cannot come back.
@MainActor
final class UnlockViewModelCredentialTests: XCTestCase {

    private var mockAuth: MockAuthRepository!
    private var mockSync: MockSyncUseCase!

    private let account = Account(
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
        mockAuth.stubbedLoginResult = .success(account)
    }

    private func makeVM(preference: UnlockCredentialPreference = UnlockCredentialPreference(),
                        pin: Bool = true,
                        pinAttemptsLeft: Int = 5) -> UnlockViewModel {
        mockAuth.stubbedPinUnlockAvailable = pin
        mockAuth.stubbedPinUnlockRemainingAttempts = pinAttemptsLeft
        return UnlockViewModel(auth: mockAuth,
                               sync: mockSync,
                               account: account,
                               credentialPreference: preference)
    }

    /// Waits for an async unlock's `Task` to reach the given state.
    ///
    /// Polling rather than a Combine subscription because several tests need to observe the *same*
    /// transition from a value that may already have moved on by the time the sink attaches.
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool,
                           _ what: String,
                           file: StaticString = #filePath,
                           line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for \(what)", file: file, line: line)
    }

    // MARK: - Which credential the screen starts on

    func testDefault_isTheMasterPasswordEvenWhenAPinExists() {
        XCTAssertEqual(makeVM().credentialMethod, .masterPassword,
                       "A PIN must not become the default just because it exists")
    }

    func testDefault_followsAPinThatActuallyWorked() async {
        let preference = UnlockCredentialPreference()
        let first = makeVM(preference: preference)
        first.toggleCredentialMethod()
        first.pin = "4712"
        first.submit()
        await waitUntil({ first.flowState == .vault }, "the PIN unlock to finish")
        XCTAssertEqual(mockAuth.lastAttemptedPIN, "4712",
                       "The wait must be for the PIN path, not for an unrelated message")

        // The next lock builds a fresh view model; the preference is what carries across.
        XCTAssertEqual(makeVM(preference: preference).credentialMethod, .pin,
                       "A shortcut the user proved on this launch should be what the next lock asks for")
    }

    func testDefault_isNotMovedByAFailedPin() async {
        let preference = UnlockCredentialPreference()
        mockAuth.unlockWithPINError = PinUnlockError.incorrectPin(remainingAttempts: 4)
        let first = makeVM(preference: preference)
        first.toggleCredentialMethod()
        first.pin = "0000"
        first.submit()
        await waitUntil({ first.errorMessage != nil }, "the PIN rejection")
        XCTAssertEqual(mockAuth.lastAttemptedPIN, "0000",
                       "The rejection has to be the PIN's, not an empty-field complaint from the other path")

        XCTAssertEqual(makeVM(preference: preference).credentialMethod, .masterPassword,
                       "The credential that just failed must not become the default")
    }

    func testDefault_fallsBackWhenThePinStopsExisting() {
        let preference = UnlockCredentialPreference()
        preference.recordSuccess(of: .pin, for: account.email)
        XCTAssertEqual(makeVM(preference: preference, pin: false).credentialMethod, .masterPassword,
                       "A PIN removed after five wrong tries must not stay what the screen asks for")
    }

    /// The bug this file's own change introduced: one process-wide flag let the account that had just
    /// unlocked with a PIN hand that default to whoever signed in next.
    func testDefault_isNotSharedBetweenAccountsOnTheSameLaunch() async {
        let preference = UnlockCredentialPreference()
        let first = makeVM(preference: preference)
        first.toggleCredentialMethod()
        first.pin = "4712"
        first.submit()
        await waitUntil({ first.flowState == .vault }, "the first account's PIN unlock")

        let other = Account(
            userId:            "user-002",
            email:             "bob@example.com",
            name:              nil,
            serverEnvironment: account.serverEnvironment
        )
        let secondVM = UnlockViewModel(auth: mockAuth,
                                       sync: mockSync,
                                       account: other,
                                       credentialPreference: preference)
        XCTAssertEqual(secondVM.credentialMethod, .masterPassword,
                       "Another account's shortcut is not this account's to inherit")
    }

    // MARK: - Submitting

    func testSubmit_withNoPassword_saysSoAndSendsNothing() {
        let sut = makeVM()
        sut.submit()
        XCTAssertEqual(sut.errorMessage, "Enter your master password to unlock.")
        XCTAssertFalse(mockAuth.unlockWithPasswordCalled,
                       "An empty credential must never reach the key derivation")
    }

    func testSubmit_withNoPIN_saysSoAndSendsNothing() {
        let sut = makeVM()
        sut.toggleCredentialMethod()
        sut.submit()
        XCTAssertEqual(sut.errorMessage, "Enter your PIN to unlock.")
        XCTAssertEqual(mockAuth.unlockWithPINCallCount, 0)
    }

    func testSubmit_sendsWhicheverCredentialIsAskedFor() async {
        let passwordVM = makeVM()
        passwordVM.password = "correct horse"
        passwordVM.submit()
        await waitUntil({ passwordVM.flowState == .vault }, "the password unlock")
        XCTAssertTrue(mockAuth.unlockWithPasswordCalled)
        XCTAssertEqual(mockAuth.unlockWithPINCallCount, 0)

        let pinVM = makeVM()
        pinVM.toggleCredentialMethod()
        pinVM.pin = "4712"
        pinVM.submit()
        await waitUntil({ pinVM.flowState == .vault }, "the PIN unlock")
        XCTAssertEqual(mockAuth.lastAttemptedPIN, "4712",
                       "The PIN must go down the PIN path — the password path would reject it as a wrong master password")
    }

    func testToggle_carriesNothingBetweenTheFields() {
        let sut = makeVM()
        sut.password = "typed while on the password field"
        sut.toggleCredentialMethod()
        XCTAssertTrue(sut.pin.isEmpty,
                      "Text typed for one credential must not be submitted as the other")
    }

    func testToggle_doesNothingWhenThereIsNoPINToSwitchTo() {
        let sut = makeVM(pin: false)
        sut.toggleCredentialMethod()
        XCTAssertEqual(sut.credentialMethod, .masterPassword)
    }

    // MARK: - What the screen says

    /// The line this whole change is about: the count belongs to the PIN, so it may only appear while
    /// the PIN is what is being asked for.
    func testAttemptCount_isHiddenBesideTheMasterPassword() {
        let sut = makeVM(pinAttemptsLeft: 1)
        XCTAssertFalse(sut.shouldShowRemainingAttempts,
                       "A spent PIN attempt must not be reported beside a master-password field")
        sut.toggleCredentialMethod()
        XCTAssertTrue(sut.shouldShowRemainingAttempts,
                      "The same count must appear as soon as the PIN is what the screen wants")
    }

    func testInstructionText_namesTheCredentialBeingAskedFor() {
        let sut = makeVM()
        XCTAssertEqual(sut.unlockInstructionText(biometricName: nil),
                       "Enter the password for alice@example.com to unlock.")
        sut.toggleCredentialMethod()
        XCTAssertEqual(sut.unlockInstructionText(biometricName: nil),
                       "Enter the PIN for alice@example.com to unlock.")
        XCTAssertEqual(sut.unlockInstructionText(biometricName: "Touch ID"),
                       "Touch ID or enter the PIN for alice@example.com to unlock.")
    }

    /// The field label, the heading and the switch all answer from this one value, so a screen cannot
    /// say "PIN" above the box and "Master password" on it.
    func testFieldLabelAndSwitch_nameOppositeCredentials() {
        let sut = makeVM()
        XCTAssertEqual(sut.credentialFieldLabel, "Master password")
        XCTAssertEqual(sut.switchCredentialTitle, "Use PIN instead")

        sut.toggleCredentialMethod()
        XCTAssertEqual(sut.credentialFieldLabel, "PIN")
        XCTAssertEqual(sut.switchCredentialTitle, "Use master password instead")
    }
}
