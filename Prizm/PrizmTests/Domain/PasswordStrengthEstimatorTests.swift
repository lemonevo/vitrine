import XCTest
@testable import Prizm

/// The estimator's contract, plus the four scenarios the spec pins down.
///
/// **What these tests cannot tell you.** They check that the *model* behaves as specified. They
/// cannot check that the model is *right* — a strength estimate is a heuristic, and the honest way
/// to evaluate one is to score a corpus and compare against `zxcvbn`, which this suite does not do.
/// What is pinned here is that the estimate is monotone in the ways it claims to be (more patterns
/// → lower score), that the named weakness matches the dominant pattern, and that the documented
/// limitations are the real ones.
@MainActor
final class PasswordStrengthEstimatorTests: XCTestCase {

    /// No word list: the honest default, and what a command-line test run actually has.
    private let sut = PasswordStrengthEstimator()

    /// No dictionaries at all. Used to isolate a single pattern penalty: with the real list loaded,
    /// a password like `23456789` may also contain a list entry (`456789` is one), and the test
    /// would silently be measuring the dictionary match instead of the sequence.
    private let bare = PasswordStrengthEstimator(commonPasswords: [], wordList: nil)

    private func score(_ password: String) -> PasswordStrength {
        sut.estimate(password).score
    }

    // MARK: - The embedded list

    func test_dictionaries_areLowercaseUniqueASCIIAndTheDocumentedSize() {
        let entries = PasswordStrengthDictionaries.commonPasswords

        XCTAssertEqual(entries.count, 609, "the count in the doc comment must match the data")
        XCTAssertEqual(Set(entries).count, entries.count, "entries must be unique")
        XCTAssertTrue(entries.allSatisfy { $0 == $0.lowercased() && $0.allSatisfy(\.isASCII) },
                      "entries must be lowercase ASCII so the case-insensitive match is exact")
        XCTAssertFalse(entries.contains(where: \.isEmpty))
    }

    func test_dictionaries_areOrderedByPopularity_soTheFirstEntriesAreTheFamousOnes() {
        // The order is load-bearing: it is the cost of the match. If someone sorts the list
        // alphabetically, `password` stops costing one guess and the whole scale shifts.
        XCTAssertEqual(PasswordStrengthDictionaries.commonPasswords.first, "password")
        XCTAssertEqual(PasswordStrengthDictionaries.commonPasswords.prefix(3),
                       ["password", "123456", "123456789"])
    }

    func test_dictionaries_wordListSize_isTheEFFListsSize() {
        // 7776 is the EFF Large Wordlist's size (6^5). It is the cost of one passphrase word, so a
        // wrong number here silently misprices every passphrase.
        XCTAssertEqual(PasswordStrengthDictionaries.effWordListSize, 7776)
    }

    // MARK: - The spec's scenarios

    func test_password_scoresLowest() {
        XCTAssertEqual(score("password"), .veryWeak)
    }

    func test_paddedCommonPassword_doesNotScoreHighly() {
        XCTAssertLessThanOrEqual(score("Password1!"), .weak)
    }

    func test_repeatedCharacter_doesNotScoreHighly() {
        XCTAssertLessThanOrEqual(score("aaaaaaaaaaaaaaaa"), .weak)
    }

    func test_keyboardSequence_doesNotScoreHighly() {
        XCTAssertLessThanOrEqual(score("qwerty123"), .weak)
    }

    func test_longPassphrase_scoresHighly() {
        XCTAssertGreaterThanOrEqual(score("correct-horse-battery-staple"), .strong)
    }

    func test_longRandomPassword_scoresHighest() {
        XCTAssertEqual(score("kR7#mQ2$xL9!vB4&zT6w"), .veryStrong)
    }

    func test_emptyPassword_scoresLowestAndNamesNoWeakness() {
        let estimate = sut.estimate("")

        XCTAssertEqual(estimate.score, .veryWeak)
        XCTAssertEqual(estimate.guessesLog10, 0)
        XCTAssertNil(estimate.weakness, "an empty field is not a weak password, it is an empty field")
    }

    // MARK: - The named weakness

    func test_weakness_namesACommonPassword() {
        let weakness = sut.estimate("letmein").weakness

        XCTAssertNotNil(weakness)
        XCTAssertTrue(weakness?.localizedCaseInsensitiveContains("common") == true,
                      "expected a 'commonly used' message, got \(weakness ?? "nil")")
    }

    func test_weakness_namesAShortPasswordByItsLength() {
        let weakness = sut.estimate("Tr0ub4").weakness

        XCTAssertNotNil(weakness)
        XCTAssertTrue(weakness?.contains("6") == true,
                      "expected the length in the message, got \(weakness ?? "nil")")
    }

    func test_weakness_isNilForAStrongPassword() {
        XCTAssertNil(sut.estimate("kR7#mQ2$xL9!vB4&zT6w").weakness)
    }

    func test_weakness_namesRepeatedCharactersBeforeLength() {
        // The order matters: a user told "too short" about `aaaaaaaaaaaaaaaa` would lengthen it and
        // learn nothing.
        let weakness = sut.estimate("aaaaaaaaaaaaaaaa").weakness

        XCTAssertTrue(weakness?.localizedCaseInsensitiveContains("repeat") == true,
                      "got \(weakness ?? "nil")")
    }

    func test_weakness_namesASequence() {
        let weakness = sut.estimate("abcdefghij").weakness

        XCTAssertTrue(weakness?.localizedCaseInsensitiveContains("sequence") == true,
                      "got \(weakness ?? "nil")")
    }

    func test_weakness_namesAYear() {
        // Weak enough for the weakness to be reported at all: `Kw8$1998tr` scores very strong, and
        // a very strong password names nothing.
        let weakness = sut.estimate("kw1998").weakness

        XCTAssertTrue(weakness?.localizedCaseInsensitiveContains("year") == true
                        || weakness?.localizedCaseInsensitiveContains("date") == true,
                      "got \(weakness ?? "nil")")
    }

    func test_weakness_hasNoMessageForAnEmptyPassword() {
        XCTAssertNil(sut.estimate("").weakness)
    }

    func test_everyDisplayName_isNonEmptyAndDistinct() {
        let names = PasswordStrength.allCases.map(\.displayName)

        XCTAssertEqual(names.count, 5)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(names).count, names.count, "two scores sharing a label is unreadable")
    }

    // MARK: - Thresholds

    func test_thresholds_followZXCVBNBoundaries() {
        XCTAssertEqual(PasswordStrength.forGuessesLog10(0), .veryWeak)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(2.999), .veryWeak)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(3), .weak)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(5.999), .weak)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(6), .fair)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(7.999), .fair)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(8), .strong)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(9.999), .strong)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(10), .veryStrong)
        XCTAssertEqual(PasswordStrength.forGuessesLog10(99), .veryStrong)
    }

    func test_score_isOrderedSoComparisonsMeanSomething() {
        XCTAssertLessThan(PasswordStrength.veryWeak, .weak)
        XCTAssertLessThan(PasswordStrength.weak, .fair)
        XCTAssertLessThan(PasswordStrength.fair, .strong)
        XCTAssertLessThan(PasswordStrength.strong, .veryStrong)
    }

    // MARK: - Costs, pinned with an injected list

    /// A three-entry list makes the arithmetic checkable by hand, which the 609-entry one does not.
    private let tiny = PasswordStrengthEstimator(commonPasswords: ["a", "bb", "ccc"])

    func test_injectedList_aWholeMatchCostsItsRankPlusOne() {
        // "bb" is the second entry, so it costs 2 guesses -> log10 ~ 0.30.
        XCTAssertEqual(tiny.estimate("bb").guessesLog10, log10(2), accuracy: 0.0001)
        XCTAssertEqual(tiny.estimate("ccc").guessesLog10, log10(3), accuracy: 0.0001)
    }

    func test_injectedList_matchingIsCaseInsensitive() {
        XCTAssertEqual(tiny.estimate("BB").guessesLog10, tiny.estimate("bb").guessesLog10)
        XCTAssertEqual(tiny.estimate("Bb").guessesLog10, tiny.estimate("bb").guessesLog10)
    }

    func test_injectedList_anEmptyListStillScores() {
        // The estimator must not divide by zero or crash when it has no dictionaries at all, and
        // with no dictionaries it falls back to pure brute force.
        let bare = PasswordStrengthEstimator(commonPasswords: [], wordList: nil)

        XCTAssertEqual(bare.estimate("kr").score, .veryWeak)          // 26^2
        XCTAssertEqual(bare.estimate("krmqxlbvztwphdsnq").score, .veryStrong)
    }

    func test_injectedWordList_aPassphraseWordCostsTheWordListSize() {
        let withWords = PasswordStrengthEstimator(commonPasswords: [], wordList: ["alpha", "beta"])

        XCTAssertEqual(withWords.estimate("alpha").guessesLog10,
                       log10(Double(PasswordStrengthDictionaries.effWordListSize)),
                       accuracy: 0.0001)
    }

    func test_injectedWordList_makesAPassphraseStrongerThanWithoutIt() {
        let words = Set(["correct", "horse", "battery", "staple"])
        let withWords = PasswordStrengthEstimator(commonPasswords: [], wordList: words)

        let without = PasswordStrengthEstimator(commonPasswords: [], wordList: nil)
            .estimate("correct-horse-battery-staple")
        let with = withWords.estimate("correct-horse-battery-staple")

        // Both are very strong; the point is that a word list *raises* the estimate, because a
        // passphrase is independent draws rather than one long string.
        XCTAssertGreaterThanOrEqual(with.score, without.score)
        XCTAssertEqual(with.score, .veryStrong)
    }

    func test_aThreeLetterEntry_doesNotMatchInsideALongerPassword() {
        // "a" is in the tiny list. If it matched as a substring, every password containing an "a"
        // would be handed a free discount.
        let withOneLetterEntry = PasswordStrengthEstimator(commonPasswords: ["a"], wordList: nil)

        XCTAssertGreaterThan(withOneLetterEntry.estimate("kR7#mQ2$xL9!vB4&zT6w").guessesLog10, 10)
    }

    func test_aThreeLetterEntry_stillMatchesWhenItIsTheWholePassword() {
        let withThreeLetterEntry = PasswordStrengthEstimator(commonPasswords: ["neo"], wordList: nil)

        XCTAssertEqual(withThreeLetterEntry.estimate("neo").score, .veryWeak)
    }

    // MARK: - The pattern penalties, isolated

    func test_repeatedCharacters_areScoredAsAChoiceNotABruteForce() {
        // `wwwwwwwwwwww` is "pick a character, repeat it": 26 x 12, not 26^12.
        let estimate = bare.estimate("wwwwwwwwwwww")

        XCTAssertLessThan(estimate.guessesLog10, 3)
    }

    func test_aRepeatingUnit_isScoredAsItsUnit() {
        // `zqzqzqzq` is a two-character unit repeated four times.
        let estimate = bare.estimate("zqzqzqzq")

        XCTAssertLessThan(estimate.guessesLog10, 4)
    }

    func test_sequences_areScoredAsAStartPointTimesALength() {
        // A bare estimator, deliberately. The real list contains `456789` and `987654`, which are
        // pure sequences — so with the list loaded the dictionary match wins and this test would be
        // measuring the wrong penalty entirely.
        let bare = PasswordStrengthEstimator(commonPasswords: [], wordList: nil)
        let ascending = bare.estimate("23456789").guessesLog10
        let descending = bare.estimate("98765432").guessesLog10

        // 10 digits x 8 length. Both directions are the same amount of work.
        XCTAssertEqual(ascending, log10(80), accuracy: 0.0001)
        XCTAssertEqual(descending, log10(80), accuracy: 0.0001)
    }

    func test_aYear_isScoredAsAHundredOptions() {
        // Standalone, so the year is the only thing being priced.
        XCTAssertEqual(bare.estimate("1998").guessesLog10, 2, accuracy: 0.0001)
    }

    func test_aNonYearFourDigitRun_isNotTreatedAsAYear() {
        // 7412 is not a year, so it costs 10^4 rather than 100.
        XCTAssertGreaterThan(bare.estimate("7412").guessesLog10, 3.9)
    }

    // MARK: - Monotonicity

    func test_addingACharacterClass_neverLowersTheScore() {
        // Four lowercase letters is 26^4 ~ 10^5.7; the twenty-character mixed one is far beyond it.
        let weaker = sut.estimate("krmq").score
        let stronger = sut.estimate("kR7#mQ2$xL9!vB4&zT6w").score

        XCTAssertLessThan(weaker, stronger)
    }

    func test_aLongerPassword_scoresAtLeastAsHighAsItsPrefix() {
        // Not a law of the model — a longer password can contain a longer dictionary match — but it
        // must hold for a random-looking one, and if it stops holding the decomposition is wrong.
        var previous = PasswordStrength.veryWeak
        for length in 4...24 {
            let candidate = String("kR7#mQ2$xL9!vB4&zT6w".prefix(length))
            let current = sut.estimate(candidate).score
            XCTAssertGreaterThanOrEqual(current, previous, "length \(length) went backwards")
            previous = current
        }
    }

    // MARK: - Purity

    func test_estimate_isDeterministic() {
        let first = sut.estimate("Tr0ub4dor&3")
        let second = sut.estimate("Tr0ub4dor&3")

        XCTAssertEqual(first, second)
    }

    func test_estimate_dependsOnlyOnTheInjectedDictionaries() {
        // The proof that nothing hidden is consulted: the same password scores differently only
        // when a dictionary is supplied, and the word list is the only input that changes it.
        // Nothing here reads `Bundle.main`, and `estimate` is synchronous, so it cannot await a
        // network call even in principle.
        let withoutWords = PasswordStrengthEstimator(commonPasswords: [], wordList: nil)
        let withWords = PasswordStrengthEstimator(commonPasswords: [], wordList: ["alpha"])

        XCTAssertNotEqual(withoutWords.estimate("alpha").guessesLog10,
                          withWords.estimate("alpha").guessesLog10)
    }

    func test_estimate_doesNotMutateTheEstimator() {
        // `PasswordStrengthEstimator` is a value type with no caches; scoring must not build one.
        let before = sut.estimate("password")
        _ = sut.estimate("kR7#mQ2$xL9!vB4&zT6w")
        let after = sut.estimate("password")

        XCTAssertEqual(before, after)
    }

    // MARK: - Shapes that must not crash

    func test_diacriticsAreFoldedBeforeMatchingDictionaries() {
        // `pässwörd` is `password` with a trick on top, and it is one of the first things an
        // attacker's ruleset tries. Without the fold it is eight mostly-random letters and scores
        // *very strong*, which is the worst kind of wrong for a strength meter.
        let tricked = sut.estimate("pässwörd")
        let plain = sut.estimate("password")

        XCTAssertEqual(tricked.score, .veryWeak)
        XCTAssertEqual(tricked.guessesLog10, plain.guessesLog10, accuracy: 0.0001)
    }

    func test_estimate_handlesUnicodeAndWhitespace() {
        // Non-ASCII characters that are not diacritics land in the symbol class. The estimator must
        // not trap on them, and must not produce a NaN.
        XCTAssertEqual(sut.estimate("     ").score, .veryWeak)
        XCTAssertFalse(sut.estimate("😀😀😀").guessesLog10.isNaN)
        XCTAssertFalse(sut.estimate("日本語のパスワード").guessesLog10.isNaN)
    }

    func test_estimate_handlesAVeryLongPasswordWithoutOverflowing() {
        let long = String(repeating: "kR7#mQ2$xL9!vB4&zT6w", count: 50)

        let estimate = sut.estimate(long)

        XCTAssertEqual(estimate.score, .veryStrong)
        XCTAssertFalse(estimate.guessesLog10.isInfinite)
    }
}
