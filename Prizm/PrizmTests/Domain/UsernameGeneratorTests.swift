import XCTest
@testable import Prizm

/// The generator's username mode.
///
/// Unlike the other two modes this value is not a secret — sites treat usernames as public — so what
/// matters is that it is readable, typable, and shaped the way the UI says it is. The entropy
/// arguments that govern `PasswordGenerator` do not apply here, and the tests are about shape rather
/// than strength.
@MainActor
final class UsernameGeneratorTests: XCTestCase {

    private let words = ["abacus", "bucket", "cactus", "dolphin", "ember", "falcon", "gadget", "harbor"]

    private func config(wordCount: Int = 2, includeNumber: Bool = true) -> PasswordGeneratorConfig {
        var c = PasswordGeneratorConfig()
        c.usernameWordCount   = wordCount
        c.usernameIncludeNumber = includeNumber
        return c
    }

    private func makeGenerator() -> UsernameGenerator {
        UsernameGenerator(wordList: words)
    }

    // MARK: - Shape

    func testGenerated_usesWordsFromTheList() throws {
        let value = try makeGenerator().generate(
            config: config(), provider: MockRandomnessProvider()
        )

        let wordPart = words(in: value)
        XCTAssertEqual(wordPart.count, 2, "expected two words; got \(value)")
        for word in wordPart {
            XCTAssertTrue(words.contains(word), "\(word) is not from the word list; got \(value)")
        }
    }

    /// The digits are appended to the final word, not given a separator of their own — so the trailing
    /// run has to be stripped before a component can be compared against the list.
    private func words(in value: String) -> [String] {
        value.split(separator: ".").map { String($0.prefix { !$0.isNumber }) }
    }

    func testGenerated_carriesTheNumberWhenAsked() throws {
        let value = try makeGenerator().generate(
            config: config(includeNumber: true), provider: MockRandomnessProvider()
        )

        XCTAssertTrue(value.last!.isNumber, "expected a trailing number; got \(value)")
    }

    func testGenerated_omitsTheNumberWhenNotAsked() throws {
        let value = try makeGenerator().generate(
            config: config(includeNumber: false), provider: MockRandomnessProvider()
        )

        XCTAssertTrue(value.allSatisfy { !$0.isNumber }, "expected no digits; got \(value)")
    }

    func testGenerated_honoursTheWordCount() throws {
        let value = try makeGenerator().generate(
            config: config(wordCount: 3, includeNumber: false), provider: MockRandomnessProvider()
        )

        XCTAssertEqual(value.split(separator: ".").count, 3, "got \(value)")
    }

    func testGenerated_isDeterministicUnderAStubbedProvider() throws {
        let a = try makeGenerator().generate(config: config(), provider: MockRandomnessProvider())
        let b = try makeGenerator().generate(config: config(), provider: MockRandomnessProvider())

        XCTAssertEqual(a, b, "the same randomness must produce the same username")
    }

    // MARK: - Degenerate inputs

    /// The word list is read from the bundle, and a build without the resource yields an empty list.
    /// A generator that returned "" or crashed would be worse than one that says so.
    func testGenerate_emptyWordList_throws() {
        let generator = UsernameGenerator(wordList: [])

        XCTAssertThrowsError(
            try generator.generate(config: config(), provider: MockRandomnessProvider())
        )
    }

    /// A word count below one would produce a bare number, which is not a username anyone asked for.
    func testGenerated_wordCountIsClampedToAtLeastOne() throws {
        let value = try makeGenerator().generate(
            config: config(wordCount: 0, includeNumber: false), provider: MockRandomnessProvider()
        )

        XCTAssertFalse(value.isEmpty)
        XCTAssertTrue(words.contains(value), "expected a single word; got \(value)")
    }
}

/// The username mode's settings must not be the passphrase's.
@MainActor
final class GeneratorModeIndependenceTests: XCTestCase {

    func testUsernameSettings_areSeparateFromThePassphrase() {
        var config = PasswordGeneratorConfig()
        config.wordCount              = 7
        config.usernameWordCount      = 2

        XCTAssertEqual(config.wordCount, 7, "the passphrase keeps its own word count")
        XCTAssertEqual(config.usernameWordCount, 2)
    }

    func testUsernameSettings_roundTripThroughThePreferenceStore() throws {
        let suiteName = "GeneratorModeIndependenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = PasswordGeneratorConfig()
        config.mode                  = .username
        config.usernameWordCount     = 3
        config.usernameIncludeNumber = false
        config.save(to: defaults)

        let loaded = PasswordGeneratorConfig.load(from: defaults)

        XCTAssertEqual(loaded.mode, .username)
        XCTAssertEqual(loaded.usernameWordCount, 3)
        XCTAssertFalse(loaded.usernameIncludeNumber)
    }
}
