import XCTest
@testable import Prizm

/// Every data-layer error that can reach the interface has to arrive as a sentence.
///
/// **Why this is one test over four enums.** The screens that show these wrap them in their own
/// localised sentence — `AttachmentAddViewModel` writes `L("Upload failed: %@",
/// error.localizedDescription)` and its siblings — so the outer half reads fine and the inner half is
/// a type name plus a case index: 「上传失败：未能完成操作。（Prizm.AttachmentCryptoError错误1。）」.
/// That is the same defect already fixed once on the unlock screen, arriving through a different
/// interpolation, so the guard covers the whole family rather than the one path that was noticed.
///
/// **Asserted by negation on purpose.** The fallback string is produced by the system and translated
/// with the locale, but the *type name* inside it is not, so "must not contain the type name" holds in
/// any language. Asserting the sentences themselves would pin this file to whichever locale the test
/// plan selects.
@MainActor
final class DataErrorWordingTests: XCTestCase {

    private func assertWorded<T: Error & LocalizedError>(_ errors: [(T, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (error, typeName) in errors {
            let text = error.localizedDescription

            XCTAssertFalse(text.isEmpty,
                           "\(typeName) has no wording at all", file: file, line: line)
            XCTAssertFalse(text.contains(typeName),
                           "\(typeName) fell back to the system's rendering of the type and case number",
                           file: file, line: line)
            XCTAssertFalse(text.contains("未能完成操作"),
                           "\(typeName) reached the user as the generic Cocoa failure string",
                           file: file, line: line)
            XCTAssertEqual(text, error.errorDescription,
                           "\(typeName) is not answered by LocalizedError", file: file, line: line)
        }
    }

    func testAttachmentCryptoErrorsAreWorded() {
        assertWorded(AttachmentCryptoError.allCases.map { ($0, "AttachmentCryptoError") })
    }

    func testEncStringErrorsAreWorded() {
        assertWorded(EncStringError.allCases.map { ($0, "EncStringError") })
    }

    func testKeychainErrorsAreWorded() {
        assertWorded([
            (KeychainError.itemNotFound,               "KeychainError"),
            (KeychainError.unexpectedStatus(-25300),    "KeychainError"),
            (KeychainError.invalidData,                 "KeychainError"),
        ])
    }

    func testIdentityTokenErrorsAreWorded() {
        assertWorded([
            (IdentityTokenError.twoFactorRequired(providers: [0, 1]), "IdentityTokenError"),
            (IdentityTokenError.twoFactorCodeInvalid,                 "IdentityTokenError"),
            (IdentityTokenError.invalidCredentials,                   "IdentityTokenError"),
        ])
    }

    /// The status number survives into the message, because it is the only thing a user can quote when
    /// the server-trust store cannot be read.
    func testUnexpectedKeychainStatusNamesTheNumber() {
        XCTAssertTrue(KeychainError.unexpectedStatus(-25300).localizedDescription.contains("-25300"))
    }

    // MARK: - The Chinese table

    /// Every sentence these four enums produce has to exist in `zh-Hans` **and differ from its key**.
    ///
    /// `AGENTS.md` states the failure this guards: a key missing from one table renders as the key
    /// itself, so a Chinese interface silently reads English — and because the key *is* the English
    /// sentence, "the key exists" is not enough. Requiring the value to differ from the key is what
    /// catches a copy-paste of the English column.
    ///
    /// The run is pinned to English by `PrizmTests.xctestplan`, so this reads the other localisation
    /// out of the bundle by name rather than going through `L(...)`.
    func testDataLayerErrorStringsAreTranslatedNotEchoed() throws {
        let english: [String] = {
            var keys: [String] = []
            keys += AttachmentCryptoError.allCases.map { $0.errorDescription ?? "" }
            keys += EncStringError.allCases.map { $0.errorDescription ?? "" }
            keys += [KeychainError.itemNotFound, KeychainError.invalidData].map { $0.errorDescription ?? "" }
            keys += [IdentityTokenError.twoFactorRequired(providers: []),
                     IdentityTokenError.twoFactorCodeInvalid,
                     IdentityTokenError.invalidCredentials].map { $0.errorDescription ?? "" }
            return keys
        }()

        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings",
                             inDirectory: nil, forLocalization: "zh-Hans"),
            "the zh-Hans table is not in the test host — the localisation resources are not being copied"
        )
        let table = try XCTUnwrap(
            NSDictionary(contentsOfFile: path) as? [String: String],
            "the zh-Hans table did not load from \(path)"
        )

        for key in english {
            let value = table[key]
            XCTAssertNotNil(value, "missing from zh-Hans: \(key)")
            if let value {
                XCTAssertNotEqual(value, key, "untranslated in zh-Hans: \(key)")
            }
        }
    }
}

private extension AttachmentCryptoError {
    static var allCases: [AttachmentCryptoError] {
        [.blobTooShort, .macMismatch, .decryptionFailed, .encryptionFailed,
         .keyGenerationFailed, .invalidKeyLength]
    }
}

private extension EncStringError {
    static var allCases: [EncStringError] {
        [.malformedEncString, .unsupportedEncType, .macMismatch, .decryptionFailed, .encryptionFailed]
    }
}
