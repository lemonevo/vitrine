import XCTest
@testable import Prizm

/// Guards the two things that make the interface localise at all: the strings files must be **in the
/// built bundle**, and every key must exist **in every language**.
///
/// Both fail silently, which is the whole reason this file exists.
///
/// - A missing `.lproj` in the bundle makes `L("解锁")` fall back to the key, so a Chinese user reads
///   English and nothing logs. This happened for real: the app target's file-system-synchronised group
///   covers `Prizm/Prizm` (assets, `Info.plist`), not `Prizm/Resources`, so `Localizable.strings` was
///   registered as nothing at all and only `build-app.sh`'s hand-rolled copy step put the translations
///   in the bundle. See `openspec/changes/xcode-localisation-resources/`.
/// - A key added to `en` but not `zh-Hans` fails the same quiet way, one string at a time.
@MainActor
final class LocalizationResourcesTests: XCTestCase {

    /// Every region the project declares in `knownRegions` except `Base`, which is not a language.
    private let regions = ["en", "zh-Hans"]

    private func stringsBundle(for region: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: region, ofType: "lproj"),
            "Prizm.app carries no \(region).lproj — Localizable.strings is not in the build"
        )
        return try XCTUnwrap(Bundle(path: path), "\(region).lproj is not a loadable bundle")
    }

    func test_everyRegionIsPresentInTheBuiltBundle() throws {
        for region in regions {
            let bundle = try stringsBundle(for: region)
            // Any real key will do as a probe; this one is on the unlock screen every user sees.
            let value = bundle.localizedString(forKey: "Prizm Is Locked", value: "§missing§", table: nil)
            XCTAssertNotEqual(value, "§missing§", "\(region).lproj has no Localizable.strings entry")
            XCTAssertFalse(value.isEmpty, "\(region).lproj translated a heading to nothing")
        }
    }

    /// The English file is the source of truth — every `L("…")` call site writes its key in English —
    /// so the check is one-directional in meaning but reported both ways so a stray translation is
    /// named rather than hidden.
    func test_everyEnglishKeyHasATranslation() throws {
        let english = try entries(in: "en").reduce(into: [:]) { $0[$1.key] = $1.value }
        let chinese = Set(try entries(in: "zh-Hans").map(\.key))

        XCTAssertFalse(english.isEmpty, "parsed no keys out of en.lproj, so this test proves nothing")

        let missing = english.keys.filter { !chinese.contains($0) }.sorted()
        XCTAssertTrue(missing.isEmpty, """
        \(missing.count) key(s) exist in English with no zh-Hans entry, so they render as English \
        text in a Chinese interface: \(missing.prefix(15))
        """)

        let orphaned = chinese.subtracting(english.keys).sorted()
        XCTAssertTrue(orphaned.isEmpty,
                      "\(orphaned.count) zh-Hans key(s) no English source uses: \(orphaned.prefix(15))")
    }

    /// A key **is** the English sentence, so the English table's value must be that same sentence.
    ///
    /// Nine PIN strings were pasted into `en.lproj` with their Chinese values, which meant the English
    /// interface showed nine lines of Chinese — and showed them only once the tables were actually in
    /// the bundle, because until then every lookup returned the key and the mistake was invisible.
    func test_englishValuesAreTheKeysThemselves() throws {
        let drifted = try entries(in: "en").filter { $0.key != $0.value }

        XCTAssertTrue(drifted.isEmpty, """
        \(drifted.count) en.lproj value(s) differ from their key, so an English interface renders \
        whatever was pasted there instead: \(drifted.prefix(15).map { "\"\($0.key)\"" })
        """)
    }

    /// `"<key>" = "<value>";` lines, as shipped.
    ///
    /// Comment lines start with `/*` or `//` and are skipped by the leading-quote test; no key in
    /// either table contains the `" = ` sequence, which is what the split relies on.
    private func entries(in region: String) throws -> [(key: String, value: String)] {
        let bundle = try stringsBundle(for: region)
        let url = try XCTUnwrap(
            bundle.url(forResource: "Localizable", withExtension: "strings"),
            "no Localizable.strings inside \(region).lproj"
        )
        let source = try readLocally(url)

        var entries: [(key: String, value: String)] = []
        for line in source.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let separator = trimmed.range(of: "\" = ") else { continue }
            guard trimmed.hasSuffix(";") else { continue }

            let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<separator.lowerBound])
            var value = String(trimmed[separator.upperBound...])
            value.removeLast()                                  // the trailing `;`
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            entries.append((key, value))
        }
        return entries
    }

    /// Xcode rewrites copied `.strings` as UTF-16 with a byte-order mark; the files in the checkout are
    /// UTF-8. Decoding by BOM covers both, because pinning either one fails the other silently — an
    /// undecoded file parses to zero keys, which is the shape of a passing test that checks nothing.
    private func readLocally(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encoding: String.Encoding = data.starts(with: [0xFF, 0xFE]) ? .utf16 : .utf8
        return try String(contentsOf: url, encoding: encoding)
    }
}
