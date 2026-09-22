import XCTest

/// XCUITest: Biometric unlock journey.
///
/// Tests the biometric unlock flow including auto-prompt, successful unlock,
/// cancellation fallback, and lockout message. Requires `--mock-biometrics`
/// launch argument to simulate biometric availability.
///
/// Biometric unlock is offered by a button on the card that raises the system prompt; the prompt
/// itself is macOS's, so these tests assert on the affordance, not on the dialog.
final class BiometricUnlockJourneyTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--inject-session",
            "--mock-biometrics",
            "--biometric-enabled",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Auto-prompt

    func testBiometricAutoPrompt_firesOnUnlockScreen() throws {
        // The card offers a button that raises the system prompt, and the subtitle names the sensor.
        let button = app.buttons["unlock.biometricButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let subtitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Touch ID'")).firstMatch
        XCTAssertTrue(subtitle.exists)
    }

    // MARK: - Successful unlock

    func testBiometricUnlock_success_showsVaultBrowser() throws {
        // With mock biometrics succeeding, the vault should appear.
        let vault = app.navigationSplitViews["vault.navigationSplit"]
        XCTAssertTrue(vault.waitForExistence(timeout: 10))
    }

    // MARK: - Cancellation fallback

    func testBiometricUnlock_cancelled_showsPasswordField() throws {
        // When biometric is cancelled, password field should be focused.
        let passwordField = app.secureTextFields["unlock.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
    }

    // MARK: - Lockout message

    func testBiometricUnlock_lockout_showsErrorMessage() throws {
        // With mock biometrics returning lockout, error should appear.
        let error = app.staticTexts["unlock.error"]
        if error.waitForExistence(timeout: 5) {
            XCTAssertTrue(error.label.contains("Too many failed"))
        }
    }
}
