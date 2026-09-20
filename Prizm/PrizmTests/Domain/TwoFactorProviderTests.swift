import XCTest
@testable import Prizm

// MARK: - TwoFactorProviderTests

/// The provider table, the order one is chosen in, and the input rules behind the code field.
///
/// The numbers in these cases come from Vaultwarden's `TwoFactorType`, not from Prizm: a test that
/// asserted Prizm's own constants back at itself would pass no matter how wrong they were.
final class TwoFactorProviderTests: XCTestCase {

    // MARK: - The numbers

    func testRawValues_matchTheServer() {
        XCTAssertEqual(TwoFactorProvider.authenticatorApp.rawValue, 0)
        XCTAssertEqual(TwoFactorProvider.email.rawValue,            1)
        XCTAssertEqual(TwoFactorProvider.duo.rawValue,              2)
        XCTAssertEqual(TwoFactorProvider.yubiKeyOTP.rawValue,       3)
        XCTAssertEqual(TwoFactorProvider.u2f.rawValue,              4)
        XCTAssertEqual(TwoFactorProvider.remember.rawValue,         5)
        XCTAssertEqual(TwoFactorProvider.organizationDuo.rawValue,  6)
        XCTAssertEqual(TwoFactorProvider.webAuthn.rawValue,         7)
        XCTAssertEqual(TwoFactorProvider.recoveryCode.rawValue,     8)
    }

    // MARK: - Selection

    func testAllThreeOffered_authenticatorWins() {
        XCTAssertEqual(TwoFactorProvider.select(from: [0, 3, 1]), .authenticatorApp)
    }

    func testYubiKeyAndEmail_yubiKeyWins() {
        XCTAssertEqual(TwoFactorProvider.select(from: [1, 3]), .yubiKeyOTP)
    }

    func testOrderInTheServerListDoesNotDecide() {
        // The server's order is incidental; the preference order is Prizm's, and a test that only
        // ever passed an already-sorted list would not notice them being conflated.
        XCTAssertEqual(TwoFactorProvider.select(from: [1, 0]), .authenticatorApp)
        XCTAssertEqual(TwoFactorProvider.select(from: [2, 1, 3]), .yubiKeyOTP)
    }

    func testOnlyUnsupportedOffered_selectsNothing() {
        XCTAssertNil(TwoFactorProvider.select(from: [2]))
        XCTAssertNil(TwoFactorProvider.select(from: [7]))
        XCTAssertNil(TwoFactorProvider.select(from: [2, 4, 6, 7]))
    }

    func testRecoveryCodeIsNotCompletable() {
        // Vaultwarden deletes every 2FA method on the account when a recovery code is accepted, so
        // Prizm must not offer it as an ordinary "enter your code" prompt.
        XCTAssertFalse(TwoFactorProvider.recoveryCode.isSupported)
        XCTAssertNil(TwoFactorProvider.select(from: [8]))
    }

    func testRememberIsNotACompletableMethod() {
        // 5 is a device token, not something the user can produce on demand.
        XCTAssertFalse(TwoFactorProvider.remember.isSupported)
    }

    // MARK: - Naming

    func testUnsupportedMethodsAreNamed() {
        XCTAssertEqual(TwoFactorProvider.names(from: [2]),       ["Duo"])
        XCTAssertEqual(TwoFactorProvider.names(from: [7]),       ["WebAuthn"])
        XCTAssertEqual(TwoFactorProvider.names(from: [2, 7]),    ["Duo", "WebAuthn"])
    }

    func testAnUnknownNumberIsReportedAsANumber() {
        let names = TwoFactorProvider.names(from: [99])
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names[0].contains("99"),
                      "an unrecognised number must be reported as one, not guessed at: \(names[0])")
        XCTAssertFalse(names[0].contains("Duo"), "it must not claim to know which method it is")
    }

    // MARK: - The code field

    func testYubiKeyAcceptsLetters() {
        // A Yubico OTP is modhex — all letters. The prompt used to strip anything that was not a
        // digit, which turned a tap into an empty field with no explanation.
        let field = try? XCTUnwrap(TwoFactorProvider.yubiKeyOTP.codeField)
        let otp   = "cbdefghijklnrtuvcbdefghijklnrtuvcbdefghijklnrtuvcbde"
        let kept  = otp.unicodeScalars.filter { field!.allowed.contains($0) }
        XCTAssertEqual(String(String.UnicodeScalarView(kept)), otp)
    }

    func testYubiKeyFieldIsLongEnoughForAFullOTP() {
        let field = try? XCTUnwrap(TwoFactorProvider.yubiKeyOTP.codeField)
        XCTAssertGreaterThanOrEqual(field?.maximumLength ?? 0, 44)
    }

    func testEmailFieldIsNotCappedAtSix() {
        // Vaultwarden's EMAIL_TOKEN_SIZE defaults to 6 but is configurable upwards, so a hard 6
        // would break a server that was set to 8.
        let field = try? XCTUnwrap(TwoFactorProvider.email.codeField)
        XCTAssertGreaterThan(field?.maximumLength ?? 0, 6)
    }

    func testAuthenticatorFieldRejectsLetters() {
        let field = try? XCTUnwrap(TwoFactorProvider.authenticatorApp.codeField)
        let kept  = "12ab34".unicodeScalars.filter { field!.allowed.contains($0) }
        XCTAssertEqual(String(String.UnicodeScalarView(kept)), "1234")
    }

    // MARK: - Resend

    func testResendIsOfferedOnlyForEmail() {
        XCTAssertTrue(TwoFactorProvider.email.offersResend)
        XCTAssertFalse(TwoFactorProvider.authenticatorApp.offersResend)
        XCTAssertFalse(TwoFactorProvider.yubiKeyOTP.offersResend)
    }

    func testEveryCompletableMethodHasTextAndAField() {
        // A method that can be completed but has no instruction would render a prompt that asks
        // for a code without saying which kind.
        for provider in TwoFactorProvider.supportedOrder {
            XCTAssertNotNil(provider.promptText, "\(provider) has no prompt text")
            XCTAssertNotNil(provider.codeField,  "\(provider) has no code field")
        }
    }
}
