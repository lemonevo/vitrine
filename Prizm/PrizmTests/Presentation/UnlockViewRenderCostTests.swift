import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Prizm

/// What one render of the unlock screen asks the repository.
///
/// Every answer here is a round trip outside the process in the real repository:
/// `biometricUnlockAvailable` builds an `LAContext` and evaluates a policy against the system,
/// `pinUnlockAvailable` reads the keychain, and `pinRemainingAttempts` reads it again. The screen
/// re-renders for every character typed into the password field, so a question asked twice inside one
/// render is a question asked twice per keystroke.
///
/// **Why these tests render.** Reading `UnlockView.body` directly measures nothing: `AuthCard { ... }`
/// stores its content as a `@ViewBuilder` closure, and constructing a body never calls it, so every
/// question the view used to ask lived inside a closure that a bare `.body` access leaves unrun — a
/// test written that way reports zero asks against the code it is supposed to be grading. An
/// `NSHostingView` goes through a real update pass, which is the only way to count what a render costs.
@MainActor
final class UnlockViewRenderCostTests: XCTestCase {

    private var sut:       UnlockViewModel!
    private var mockAuth:  MockAuthRepository!
    private var host:      NSHostingView<UnlockView>!

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
        // The strings on this screen are built through `L(...)`, which follows the machine's language in
        // a bare test process; the pinned test run is English.
        ActiveLocalization.languageCode = "en"
        ActiveLocalization.locale       = Locale(identifier: "en")

        mockAuth = MockAuthRepository()
        sut = UnlockViewModel(auth: mockAuth, sync: MockSyncUseCase(), account: stubAccount)
    }

    override func tearDown() {
        host = nil
        sut  = nil
        super.tearDown()
    }

    // MARK: - Harness

    /// Installs the screen and lays it out once, so the first render happens before any counting.
    private func install() {
        host = NSHostingView(rootView: UnlockView(viewModel: sut))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 560)
        host.layoutSubtreeIfNeeded()
    }

    /// Types into the field the way the user does — published state changing, then a layout to flush
    /// the render it invalidates — and reports how many renders actually happened.
    private func type(_ text: String) {
        for character in text {
            sut.password = String(character)
            host.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Tests

    /// One policy evaluation per render, not one per control that names the sensor.
    ///
    /// The subtitle and the biometric button each asked the same question, and the sensor's name and
    /// icon each built their own `LAContext` on top of that.
    func test_eachKeystrokeRenderAsksBiometricAvailabilityOnce() {
        mockAuth.stubbedBiometricUnlockAvailable = true
        install()

        let before = mockAuth.biometricUnlockAvailableAccessCount
        type("abcd")
        let asks = mockAuth.biometricUnlockAvailableAccessCount - before

        XCTAssertEqual(asks, 4, "four keystrokes rendered four times, so the screen should have asked "
                              + "once each — the ask stands for a policy evaluation in the app")
    }

    /// The switch-credential control is drawn once per render, so it should read once per render.
    func test_eachKeystrokeRenderAsksPinAvailabilityOnce() {
        mockAuth.stubbedPinUnlockAvailable = true
        install()

        let before = mockAuth.pinUnlockAvailableAccessCount
        type("abcd")
        let asks = mockAuth.pinUnlockAvailableAccessCount - before

        XCTAssertEqual(asks, 4)
    }

    /// The attempt count belongs to the PIN alone. Reading it beside a master-password field reports a
    /// limit that has nothing to do with what is being typed — and each read is a keychain round trip
    /// taken while the user is typing a password that will never be counted.
    func test_typingAMasterPasswordNeverReadsThePINAttemptCount() {
        mockAuth.stubbedBiometricUnlockAvailable = true
        mockAuth.stubbedPinUnlockAvailable       = true
        mockAuth.stubbedPinUnlockRemainingAttempts = 4
        install()

        let before = mockAuth.pinUnlockRemainingAttemptsAccessCount
        type("hunter2")
        let asks = mockAuth.pinUnlockRemainingAttemptsAccessCount - before

        XCTAssertEqual(asks, 0)
    }

    /// In PIN mode the count is shown, so it is read — twice a render, because the decision to show it
    /// asks the repository for the number and the number is then printed once into the label and once
    /// into the accessibility description. Collapsing that to one read would mean duplicating the "is
    /// this worth showing" rule out of the view model and into the view, which is the worse trade: the
    /// old code read it three times, twice for the same piece of text.
    func test_pinRenderReadsTheAttemptCountTwiceEach() {
        mockAuth.stubbedPinUnlockAvailable         = true
        mockAuth.stubbedPinUnlockRemainingAttempts = 4
        sut.toggleCredentialMethod()
        XCTAssertEqual(sut.credentialMethod, .pin, "the screen has to be asking for a PIN to count this")
        install()

        let before = mockAuth.pinUnlockRemainingAttemptsAccessCount
        type("1234")
        let asks = mockAuth.pinUnlockRemainingAttemptsAccessCount - before

        XCTAssertEqual(asks, 8, "four keystrokes, two reads each — one to decide, one to print")
    }
}
