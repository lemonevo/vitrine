import XCTest
@testable import Prizm

/// The integers `URIMatchType` puts on the wire are Bitwarden's, not this enum's own numbering.
///
/// They used to be: the type was `Int`-backed starting at `domain = 0`, while the wire reserves 0 for
/// "default" and puts "base domain" at 1. Every strategy above the first was written as its neighbour,
/// and `never = 6` had no case at all — so a rule the user set to "never autofill here" left the app as
/// "match by regular expression", and a value read in as 6 decoded to nothing and was erased on the
/// next save.
///
/// Asserted case by case, in both directions, for the same reason `SecureNoteSubtypeTests` does it
/// that way: a mapping that is wrong identically in both directions round-trips perfectly, so a
/// round-trip test alone would have passed the whole time this was broken.
@MainActor
final class URIMatchTypeTests: XCTestCase {

    // MARK: - The wire contract

    func test_wireValuesDecodeToTheStrategyBitwardenMeans() {
        XCTAssertEqual(URIMatchType(rawValue: 0), .defaultMatch)
        XCTAssertEqual(URIMatchType(rawValue: 1), .baseDomain)
        XCTAssertEqual(URIMatchType(rawValue: 2), .host)
        XCTAssertEqual(URIMatchType(rawValue: 3), .startsWith)
        XCTAssertEqual(URIMatchType(rawValue: 4), .exact)
        XCTAssertEqual(URIMatchType(rawValue: 5), .regularExpression)
        XCTAssertEqual(URIMatchType(rawValue: 6), .never)
    }

    func test_strategiesEncodeToTheWireValues() {
        XCTAssertEqual(URIMatchType.defaultMatch.rawValue, 0)
        XCTAssertEqual(URIMatchType.baseDomain.rawValue, 1)
        XCTAssertEqual(URIMatchType.host.rawValue, 2)
        XCTAssertEqual(URIMatchType.startsWith.rawValue, 3)
        XCTAssertEqual(URIMatchType.exact.rawValue, 4)
        XCTAssertEqual(URIMatchType.regularExpression.rawValue, 5)
        XCTAssertEqual(URIMatchType.never.rawValue, 6)
    }

    /// The regression, stated as the one sentence that matters: choosing "Never" must not send a
    /// regular expression.
    func test_neverIsNotRegularExpression() {
        XCTAssertNotEqual(URIMatchType.never.rawValue, 5)
        XCTAssertEqual(URIMatchType(rawValue: URIMatchType.never.rawValue), .never)
    }

    // MARK: - Values this build cannot name

    func test_anUnrecognisedStrategyIsCarriedNotNormalised() {
        let future = URIMatchType(rawValue: 7)
        XCTAssertEqual(future, .unknown(7))
        XCTAssertEqual(future.rawValue, 7, "an unknown strategy must go back out as the number it came in as")
    }

    func test_everyWireValueFromZeroToTheKnownMaximumSurvivesARoundTrip() {
        for raw in 0...6 {
            XCTAssertEqual(URIMatchType(rawValue: raw).rawValue, raw)
        }
        for raw in [-1, 7, 42, 1_000] {
            XCTAssertEqual(URIMatchType(rawValue: raw).rawValue, raw)
        }
    }

    // MARK: - The picker

    /// `.unknown` is what a stored value degrades to, not a choice; `.defaultMatch` is what `nil`
    /// already means in the picker, so offering both would put two entries on the popup that write the
    /// same thing.
    func test_thePickerOffersNamedStrategiesOnly() {
        XCTAssertEqual(URIMatchType.selectable,
                       [.baseDomain, .host, .startsWith, .exact, .regularExpression, .never])
        XCTAssertFalse(URIMatchType.selectable.contains { if case .unknown = $0 { return true }; return false })
    }

    func test_thePickerOrderMatchesBitwardens() {
        XCTAssertEqual(URIMatchType.selectable.map(\.rawValue), [1, 2, 3, 4, 5, 6])
    }
}
