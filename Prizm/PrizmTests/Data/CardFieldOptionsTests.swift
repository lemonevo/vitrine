import XCTest
@testable import Prizm

/// The card form's option lists, and the rule that a value outside them is kept.
///
/// The card fields round-trip correctly already — `toRawCard` encrypts brand, `expMonth` and `expYear`
/// (`CipherMapper.swift:514-523`). What was missing was a picker, and a picker is exactly the kind of
/// change that can start destroying values it does not recognise.
@MainActor
final class CardFieldOptionsTests: XCTestCase {

    private let keys = CryptoKeys(
        encryptionKey: Data(repeating: 0x33, count: 32),
        macKey:        Data(repeating: 0x44, count: 32)
    )

    private func card(brand: String?, expMonth: String?, expYear: String?) -> VaultItem {
        VaultItem(
            id: "card-1", name: "My Card", isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .card(CardContent(
                cardholderName: "A Person", brand: brand, number: "4111111111111111",
                expMonth: expMonth, expYear: expYear, code: "123",
                notes: nil, customFields: []
            ))
        )
    }

    // MARK: - The option lists

    func testBrands_includeTheCommonOnes() {
        for expected in ["Visa", "Mastercard", "American Express", "Discover"] {
            XCTAssertTrue(
                CardFieldOptions.brands.contains(expected),
                "\(expected) should be offered; got \(CardFieldOptions.brands)"
            )
        }
    }

    /// The picker's job is to stop a user typing "09" or "September".
    func testMonths_areTheTwelveZeroPaddedValues() {
        XCTAssertEqual(CardFieldOptions.months,
                       ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"])
    }

    func testYears_startAtTheCurrentYear() {
        let current = Calendar.current.component(.year, from: Date())
        XCTAssertEqual(CardFieldOptions.years.first, String(current),
                       "a card that expired last year should not be the default for a new one")
        XCTAssertGreaterThan(CardFieldOptions.years.count, 5)
    }

    // MARK: - A value outside the list is kept

    /// The rule the picker must not break: an unfamiliar brand is the user's data, not a typo to fix.
    func testRoundTrip_unknownBrand_isPreserved() throws {
        let mapper = CipherMapper()
        let raw = try mapper.toRawCipher(
            DraftVaultItem(card(brand: "Carte Bancaire", expMonth: "09", expYear: "2031")),
            encryptedWith: keys
        )
        let (back, _) = try mapper.map(raw: raw, keys: keys)

        guard case .card(let c) = back.content else { return XCTFail("Expected a card") }
        XCTAssertEqual(c.brand, "Carte Bancaire")
    }

    func testRoundTrip_outOfRangeExpiry_isPreserved() throws {
        let mapper = CipherMapper()
        let raw = try mapper.toRawCipher(
            DraftVaultItem(card(brand: "Visa", expMonth: "13", expYear: "2099")),
            encryptedWith: keys
        )
        let (back, _) = try mapper.map(raw: raw, keys: keys)

        guard case .card(let c) = back.content else { return XCTFail("Expected a card") }
        XCTAssertEqual(c.expMonth, "13", "a value the picker does not offer must survive anyway")
        XCTAssertEqual(c.expYear, "2099")
    }

    func testRoundTrip_ordinaryCard_isUnchanged() throws {
        let mapper = CipherMapper()
        let raw = try mapper.toRawCipher(
            DraftVaultItem(card(brand: "Visa", expMonth: "04", expYear: "2030")),
            encryptedWith: keys
        )
        let (back, _) = try mapper.map(raw: raw, keys: keys)

        guard case .card(let c) = back.content else { return XCTFail("Expected a card") }
        XCTAssertEqual(c.brand, "Visa")
        XCTAssertEqual(c.expMonth, "04")
        XCTAssertEqual(c.expYear, "2030")
    }
}
