import XCTest
@testable import Prizm

/// Tests for `TOTPGeneratorImpl`.
///
/// The RFC 6238 vectors below are the published ones from Appendix B; the expected codes were
/// independently reproduced with a reference HMAC implementation before being written here.
///
/// This is the security-critical half of FEATURE-GAP-ANALYSIS.md §2.1: `Item ▸ Copy Code` used to
/// copy the stored *seed*, which is a permanent second factor. These tests pin the generator that
/// replaced it.
@MainActor
final class TOTPGeneratorTests: XCTestCase {

    private var sut: TOTPGeneratorImpl!

    /// RFC 6238 Appendix B seed lengths: 20 bytes for SHA-1, 32 for SHA-256, 64 for SHA-512.
    private enum Seed {
        static let sha1   = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        static let sha256 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"
        static let sha512 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
                          + "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA"
    }

    override func setUp() async throws {
        try await super.setUp()
        sut = TOTPGeneratorImpl()
    }

    private func date(_ unixTime: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }

    private func uri(secret: String, algorithm: String? = nil,
                     digits: Int? = nil, period: Int? = nil) -> String {
        var query = "secret=\(secret)"
        if let algorithm { query += "&algorithm=\(algorithm)" }
        if let digits    { query += "&digits=\(digits)" }
        if let period    { query += "&period=\(period)" }
        return "otpauth://totp/Example:alice@example.com?\(query)"
    }

    // MARK: - RFC 6238 Appendix B vectors

    func test_rfc6238_sha1Vectors() {
        let expected: [(Int, String)] = [
            (59,          "94287082"),
            (1111111109,  "07081804"),
            (1111111111,  "14050471"),
            (1234567890,  "89005924"),
            (2000000000,  "69279037"),
            (20000000000, "65353130"),
        ]
        for (time, code) in expected {
            XCTAssertEqual(
                sut.code(for: uri(secret: Seed.sha1, algorithm: "SHA1", digits: 8), at: date(time)),
                code,
                "SHA-1 vector at t=\(time)"
            )
        }
    }

    func test_rfc6238_sha256Vectors() {
        let expected: [(Int, String)] = [
            (59,          "46119246"),
            (1111111109,  "68084774"),
            (1111111111,  "67062674"),
            (1234567890,  "91819424"),
            (2000000000,  "90698825"),
            (20000000000, "77737706"),
        ]
        for (time, code) in expected {
            XCTAssertEqual(
                sut.code(for: uri(secret: Seed.sha256, algorithm: "SHA256", digits: 8), at: date(time)),
                code,
                "SHA-256 vector at t=\(time)"
            )
        }
    }

    func test_rfc6238_sha512Vectors() {
        let expected: [(Int, String)] = [
            (59,          "90693936"),
            (1111111109,  "25091201"),
            (1111111111,  "99943326"),
            (1234567890,  "93441116"),
            (2000000000,  "38618901"),
            (20000000000, "47863826"),
        ]
        for (time, code) in expected {
            XCTAssertEqual(
                sut.code(for: uri(secret: Seed.sha512, algorithm: "SHA512", digits: 8), at: date(time)),
                code,
                "SHA-512 vector at t=\(time)"
            )
        }
    }

    // MARK: - Defaults

    func test_bareSecret_usesSha1SixDigitsThirtySeconds() {
        // 6-digit SHA-1 at t=59 is the same vector truncated to its last six digits.
        XCTAssertEqual(sut.code(for: Seed.sha1, at: date(59)), "287082")
        XCTAssertEqual(sut.code(for: Seed.sha1, at: date(1111111109)), "081804")
        XCTAssertEqual(sut.code(for: Seed.sha1, at: date(1234567890)), "005924")
    }

    func test_bareSecret_isZeroPaddedToSixDigits() {
        // t=1234567890 produces 005924 — the leading zeros must survive.
        let code = sut.code(for: Seed.sha1, at: date(1234567890))
        XCTAssertEqual(code?.count, 6)
        XCTAssertEqual(code?.hasPrefix("00"), true)
    }

    func test_uriWithoutParameters_usesDefaults() {
        XCTAssertEqual(
            sut.code(for: uri(secret: Seed.sha1), at: date(59)),
            "287082"
        )
    }

    func test_uriOverridesPeriodAndDigits() {
        // Period 60 folds t=59 into the same time step as t=0, so the code must differ from the
        // 30-second one.
        let sixtySecondCode = sut.code(
            for: uri(secret: Seed.sha256, algorithm: "SHA256", digits: 8, period: 60),
            at: date(59)
        )
        let thirtySecondCode = sut.code(
            for: uri(secret: Seed.sha256, algorithm: "SHA256", digits: 8),
            at: date(59)
        )
        XCTAssertEqual(sixtySecondCode, "18920136")
        XCTAssertNotEqual(sixtySecondCode, thirtySecondCode)
    }

    func test_uriParameterNamesAreCaseInsensitive() {
        let upper = "otpauth://totp/Example?SECRET=\(Seed.sha1)&DIGITS=8&ALGORITHM=SHA1"
        XCTAssertEqual(sut.code(for: upper, at: date(59)), "94287082")
    }

    // MARK: - Base32 normalisation

    func test_secretIsCaseInsensitive() {
        XCTAssertEqual(
            sut.code(for: Seed.sha1.lowercased(), at: date(59)),
            sut.code(for: Seed.sha1, at: date(59))
        )
    }

    func test_secretIgnoresPaddingAndWhitespace() {
        // Secrets are routinely pasted grouped in fours, and with or without `=`.
        let grouped = "GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ"
        XCTAssertEqual(sut.code(for: grouped, at: date(59)), "287082")

        let padded = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ===="
        XCTAssertEqual(sut.code(for: padded, at: date(59)), "287082")
    }

    // MARK: - Rejections

    func test_nilSecret_returnsNil() {
        XCTAssertNil(sut.code(for: nil, at: date(59)))
    }

    func test_emptySecret_returnsNil() {
        XCTAssertNil(sut.code(for: "", at: date(59)))
        XCTAssertNil(sut.code(for: "   \n ", at: date(59)))
    }

    func test_nonBase32Secret_returnsNil() {
        XCTAssertNil(sut.code(for: "not-base32!", at: date(59)))
        // 0, 1, 8 and 9 are not in the Base32 alphabet.
        XCTAssertNil(sut.code(for: "0189", at: date(59)))
    }

    func test_uriWithoutSecret_returnsNil() {
        XCTAssertNil(sut.code(for: "otpauth://totp/Example?issuer=ACME", at: date(59)))
    }

    func test_unsupportedAlgorithm_returnsNil() {
        XCTAssertNil(sut.code(for: uri(secret: Seed.sha1, algorithm: "MD5"), at: date(59)))
    }

    func test_outOfRangeDigits_returnsNil() {
        // RFC 4226 §4.1 defines 6–8 digits; a larger value would be silently truncated by the
        // modulus and produce codes that never validate.
        XCTAssertNil(sut.code(for: uri(secret: Seed.sha1, digits: 4), at: date(59)))
        XCTAssertNil(sut.code(for: uri(secret: Seed.sha1, digits: 12), at: date(59)))
    }

    func test_nonPositivePeriod_returnsNil() {
        XCTAssertNil(sut.code(for: uri(secret: Seed.sha1, period: 0), at: date(59)))
        XCTAssertNil(sut.code(for: uri(secret: Seed.sha1, period: -30), at: date(59)))
    }

    // MARK: - Time behaviour

    func test_codeChangesAcrossPeriodBoundary() {
        let lastSecondOfStep  = sut.code(for: Seed.sha1, at: date(29))
        let firstSecondOfNext = sut.code(for: Seed.sha1, at: date(30))
        XCTAssertNotNil(lastSecondOfStep)
        XCTAssertNotNil(firstSecondOfNext)
        XCTAssertNotEqual(lastSecondOfStep, firstSecondOfNext)
    }

    func test_codeIsStableWithinPeriod() {
        XCTAssertEqual(
            sut.code(for: Seed.sha1, at: date(30)),
            sut.code(for: Seed.sha1, at: date(59))
        )
    }

    // MARK: - Secret never leaks

    func test_generatedCodeIsNeverTheSecret() {
        // Guards the §2.1 regression directly: whatever the generator returns must be a 6-digit
        // code, not the seed that was passed in.
        let code = sut.code(for: Seed.sha1, at: date(59))
        XCTAssertNotEqual(code, Seed.sha1)
        XCTAssertEqual(code?.count, 6)
        XCTAssertTrue(code?.allSatisfy(\.isNumber) == true)
    }
}
