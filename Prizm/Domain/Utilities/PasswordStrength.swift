import Foundation

// MARK: - PasswordStrength

/// How strong a password looks, on the same five-point scale `zxcvbn` uses.
///
/// The scale is borrowed deliberately: a user who has seen Bitwarden's meter, or any site built on
/// `zxcvbn`, already knows what "fair" means, and inventing a different five-point vocabulary would
/// make the number harder to interpret for no gain.
nonisolated enum PasswordStrength: Int, CaseIterable, Comparable, Sendable {

    case veryWeak  = 0
    case weak      = 1
    case fair      = 2
    case strong    = 3
    case veryStrong = 4

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// `zxcvbn`'s thresholds, applied to `log10(guesses)`.
    ///
    /// Stated as the boundaries rather than as a table of ranges so the two places that need the
    /// number — the score and the "is this below strong?" question the weakness naming asks — cannot
    /// disagree about where the boundary is.
    static func forGuessesLog10(_ log10: Double) -> PasswordStrength {
        switch log10 {
        case ..<3:  return .veryWeak
        case ..<6:  return .weak
        case ..<8:  return .fair
        case ..<10: return .strong
        default:    return .veryStrong
        }
    }

    var displayName: String {
        switch self {
        case .veryWeak:   return L("Very weak")
        case .weak:       return L("Weak")
        case .fair:       return L("Fair")
        case .strong:     return L("Strong")
        case .veryStrong: return L("Very strong")
        }
    }
}

// MARK: - StrengthEstimate

/// The result of scoring one password.
///
/// **This is an estimate, and the type says so.** It is not a breach check, it is not a guarantee,
/// and it is not `zxcvbn` — see `PasswordStrengthEstimator` for exactly what it does and does not
/// model.
nonisolated struct StrengthEstimate: Equatable, Sendable {

    /// The five-point score.
    let score: PasswordStrength

    /// `log10` of the modelled guess count. Exposed because the score alone throws away the
    /// difference between "10^3 guesses" and "10^3.9 guesses", which is useful in tests and in a
    /// future "why?" disclosure. Never shown as a raw number to the user: a guess count is a
    /// fiction precise to a factor of a million.
    let guessesLog10: Double

    /// The single pattern contributing most to the weakness, or `nil` when there is nothing to fix.
    ///
    /// `nil` in two distinct cases, both intentional: a password that scores *very strong* has no
    /// actionable weakness to name, and an empty password has no weakness either — it has no
    /// content. Naming "too short" for an empty field would put an error message on a form the user
    /// has not filled in yet.
    let weakness: String?
}

// MARK: - PasswordStrengthEstimator

/// A local, pattern-aware password-strength estimator.
///
/// ## What it does
///
/// It models the cost of guessing a password as a product of the cost of its parts:
///
/// 1. **Dictionary matches.** The longest non-overlapping matches against
///    `PasswordStrengthDictionaries.commonPasswords` and (when supplied) the EFF word list are
///    found first, case-insensitively. A common password costs its rank in the list — `password`
///    is the first entry, so it costs one guess, not `26^8`. A passphrase word costs the word
///    list's size.
/// 2. **Everything else** is split into runs of digits / lowercase / uppercase / symbols, and each
///    run costs `alphabetSize ^ length`, with three patterns scored as what they actually are:
///    a repeated character (`c × length`), a repeating unit (`c^period × repeats`), a keyboard or
///    alphabet sequence (`c × length`), and a four-digit year (`100`).
/// 3. The costs are multiplied and the product's `log10` selects the score. The multiplication is
///    done as a sum of logarithms: the product itself overflows `Double` at roughly 300 characters
///    of mixed content, and a password manager that returns `inf` — and therefore "very strong" —
///    for a long password would be worse than useless.
///
/// The product — rather than the sum — is the part that matters most. A four-word passphrase is
/// four independent draws, so its search space is `7776^4`, not `4 × 7776`; summing would rate
/// `correct-horse-battery-staple` as weaker than a six-character password, which is the opposite of
/// the truth. See the note in `tasks.md` for why the design document's "sum" was not followed.
///
/// ## What it is not
///
/// **This is not `zxcvbn`, and the gap is mostly the dictionaries.** It has 609 common passwords
/// rather than 30,000+, and one word list rather than several. Specifically it does **not** model:
///
/// - **l33t substitutions.** `p@ssw0rd` is not recognised as `password`.
/// - **Multi-word combinations.** Two uncommon words joined score as one long string, so a
///   passphrase made of two dictionary words is over-rated.
/// - **Names, places, and the rest of `zxcvbn`'s match set.** A surname is just letters here.
/// - **Cross-pattern combinations.** Only the single best decomposition is costed.
///
/// It also has one deliberate bias: when it is wrong, it is wrong *low*. A mixed-character password
/// is scored as the product of its runs rather than as `pool^length`, which understates it — an
/// attacker who knows the run boundaries would do better than the estimate implies. Understating is
/// the safe direction for a strength meter; overstating is how a user is talked into a password they
/// should not have used.
///
/// **The leaked-password check is deliberately absent.** It would require sending a hash prefix to a
/// public API. A client whose selling point is self-hosting should not open a connection the user
/// did not configure, so the check is refused rather than offered — and the health report says so,
/// so the absence is visible instead of assumed.
///
/// ## Cost
///
/// `O(n² × longest entry)` in the password's length, with a 16-character ceiling on dictionary
/// entries. It runs on every keystroke of the generator's length slider, which is why it does no
/// allocation beyond a handful of small arrays.
nonisolated struct PasswordStrengthEstimator: Sendable {

    /// One dictionary or pattern match inside a password.
    private struct Match {
        let range: Range<Int>
        let cost: Double
        let isWholePassword: Bool
        let kind: Kind

        enum Kind {
            case commonPassword(rank: Int)
            case dictionaryWord
        }
    }

    /// Lowercased common password → its position in the popularity list (0-based).
    private let commonRank: [String: Int]

    /// Lowercased passphrase words, or `nil` when no word list is available.
    private let wordList: Set<String>?

    /// The longest and shortest dictionary entries, so the matcher does not scan spans that cannot
    /// match. Derived rather than written down: a list edit cannot desynchronise them.
    private let longestEntry: Int
    private let shortestEntry: Int

    /// The shortest entry the estimator will match *inside* a longer password.
    ///
    /// A three-letter entry is a real password but a terrible substring: `neo` and `007` appear by
    /// chance inside unrelated strings, and matching them would hand out a 200× discount for free.
    /// Entries shorter than this still match when they *are* the whole password.
    private static let minimumSubstringMatch = 4

    /// - Parameters:
    ///   - commonPasswords: the popularity list, most-guessed first. Injected so tests can use a
    ///     three-entry list and assert exact costs.
    ///   - wordList: the passphrase word list, or `nil` to score passphrase words as ordinary
    ///     letters. `nil` is the honest default: the EFF list lives in the app bundle, and in a
    ///     command-line test run it is not there. Defaulting to "assume a word list exists" would
    ///     make every test's numbers depend on a resource the tests do not have.
    init(commonPasswords: [String] = PasswordStrengthDictionaries.commonPasswords,
         wordList: Set<String>? = nil) {
        var ranks: [String: Int] = [:]
        for (index, password) in commonPasswords.enumerated() {
            ranks[password.lowercased()] = index
        }
        self.commonRank = ranks

        let normalisedWords = wordList.map { Set($0.map { $0.lowercased() }) }
        self.wordList = normalisedWords

        let lengths = commonPasswords.map(\.count) + (normalisedWords ?? []).map(\.count)
        self.longestEntry = lengths.max() ?? 0
        self.shortestEntry = lengths.min() ?? 0
    }

    // MARK: - The app's estimator

    /// The estimator the app runs: the embedded popularity list, plus the EFF word list when the
    /// bundle can supply it.
    ///
    /// The word list is read from the bundle rather than written down here so a generated
    /// passphrase's words cost their real `7776` instead of being priced as unrelated letters.
    /// Under `swift test` `Bundle.main` is the xctest runner and the resource is absent, so this
    /// degrades to the popularity list alone rather than trapping — the same degradation the
    /// generator itself has, and the reason the `wordList` parameter defaults to `nil`.
    static let application: PasswordStrengthEstimator = {
        let words = PasswordGenerator.effWordList
        return PasswordStrengthEstimator(wordList: words.isEmpty ? nil : Set(words))
    }()

    // MARK: - Scoring

    /// Scores one password. Never makes a network request and never logs the password.
    func estimate(_ password: String) -> StrengthEstimate {
        guard !password.isEmpty else {
            return StrengthEstimate(score: .veryWeak, guessesLog10: 0, weakness: nil)
        }

        let characters = Array(password)
        let matches = dictionaryMatches(in: characters)

        var costs = matches.map(\.cost)

        // Whatever the dictionary did not claim is scored as runs.
        var covered = [Bool](repeating: false, count: characters.count)
        for match in matches {
            for index in match.range { covered[index] = true }
        }
        var start = 0
        while start < characters.count {
            guard !covered[start] else { start += 1; continue }
            var end = start
            while end < characters.count && !covered[end] { end += 1 }
            costs += Self.runCosts(for: Array(characters[start..<end]))
            start = end
        }

        let guessesLog10 = costs.reduce(0.0) { $0 + Foundation.log10($1) }
        let score = PasswordStrength.forGuessesLog10(guessesLog10)

        return StrengthEstimate(
            score: score,
            guessesLog10: guessesLog10,
            weakness: weakness(in: characters, matches: matches, score: score)
        )
    }

    // MARK: - Dictionary matching

    /// Finds the longest non-overlapping dictionary matches, longest spans first.
    ///
    /// Longest-first is what makes `password` win over `pass` and `word`: the estimator wants the
    /// most generous explanation of the password that the dictionaries support, because that is the
    /// one an attacker with the same dictionaries would find.
    private func dictionaryMatches(in characters: [Character]) -> [Match] {
        let count = characters.count
        let lowercase = Self.foldedLowercase(characters)
        var covered = [Bool](repeating: false, count: count)
        var matches: [Match] = []

        let longest = min(count, longestEntry)
        guard longest >= max(shortestEntry, 1) else { return [] }

        for length in stride(from: longest, through: shortestEntry, by: -1) {
            for start in 0...(count - length) {
                let end = start + length
                guard !covered[start..<end].contains(true) else { continue }

                let candidate = lowercase[start..<end].joined()
                let isWhole = length == count

                if let rank = commonRank[candidate], isWhole || length >= Self.minimumSubstringMatch {
                    matches.append(Match(
                        range: start..<end,
                        cost: Double(rank + 1),
                        isWholePassword: isWhole,
                        kind: .commonPassword(rank: rank)
                    ))
                } else if let words = wordList, words.contains(candidate),
                          isWhole || length >= Self.minimumSubstringMatch {
                    matches.append(Match(
                        range: start..<end,
                        cost: Double(PasswordStrengthDictionaries.effWordListSize),
                        isWholePassword: isWhole,
                        kind: .dictionaryWord
                    ))
                } else {
                    continue
                }

                for index in start..<end { covered[index] = true }
            }
        }

        return matches
    }

    /// The characters to match dictionaries against: diacritics folded away, then lowercased.
    ///
    /// `pässwörd` is `password` with a trick on top, and it is one of the first things a real
    /// attacker's ruleset tries. Without the fold it is scored as eight mostly-random letters and
    /// comes out *very strong*, which is the worst kind of wrong for a strength meter.
    ///
    /// Folding is one-for-one for precomposed diacritics, which is the case this exists for. If
    /// some input does not fold one-for-one the character indices would no longer line up with the
    /// original, so the fold is dropped for that password rather than risk attributing a match to
    /// the wrong span.
    private static func foldedLowercase(_ characters: [Character]) -> [String] {
        let original = String(characters)
        let folded = original.folding(options: .diacriticInsensitive, locale: nil)
        let source = folded.count == characters.count ? folded : original
        return source.map { String($0).lowercased() }
    }

    // MARK: - Run scoring

    /// The character classes a password is split into, in the order they are reported.
    private enum CharacterClass {
        case digit, lowercase, uppercase, symbol

        /// How many characters an attacker would have to try at one position of this class.
        ///
        /// The symbol count is the printable ASCII punctuation set, which is what the generator
        /// draws from — so the two features agree about what a symbol is.
        var alphabetSize: Int {
            switch self {
            case .digit:     return 10
            case .lowercase: return 26
            case .uppercase: return 26
            case .symbol:    return 33
            }
        }
    }

    private static func characterClass(of character: Character) -> CharacterClass {
        if character.isNumber { return .digit }
        if character.isLowercase { return .lowercase }
        if character.isUppercase { return .uppercase }
        return .symbol
    }

    /// Splits a span into maximal runs of one character class and costs each.
    private static func runCosts(for characters: [Character]) -> [Double] {
        guard !characters.isEmpty else { return [] }
        var costs: [Double] = []
        var start = 0
        while start < characters.count {
            let thisClass = characterClass(of: characters[start])
            var end = start
            while end < characters.count, characterClass(of: characters[end]) == thisClass { end += 1 }
            costs.append(cost(of: Array(characters[start..<end]), alphabet: thisClass.alphabetSize))
            start = end
        }
        return costs
    }

    /// What one run costs to guess.
    private static func cost(of run: [Character], alphabet: Int) -> Double {
        let length = run.count
        let size = Double(alphabet)

        if length == 1 { return size }

        // `aaaa` is "pick a character, repeat it" — the repeats are not a choice.
        if Set(run).count == 1 { return size * Double(length) }

        // `abab` / `abcabc` is the repeating unit, times how many times it repeats.
        if let period = smallestPeriod(of: run), period < length {
            return pow(size, Double(period)) * Double(length / period)
        }

        // A four-digit year is a hundred options, not ten thousand.
        if isYear(run) { return 100 }

        // `12345` / `qwert` is a start point times a length, not a full-length brute force.
        if isSequence(run) { return size * Double(length) }

        return pow(size, Double(length))
    }

    /// The smallest `p` such that the run is its first `p` characters repeated, or `nil`.
    private static func smallestPeriod(of run: [Character]) -> Int? {
        let length = run.count
        guard length >= 2 else { return nil }
        for period in 1...(length / 2) where length % period == 0 {
            if (0..<length).allSatisfy({ run[$0] == run[$0 % period] }) { return period }
        }
        return nil
    }

    private static func isYear(_ run: [Character]) -> Bool {
        guard run.count == 4, run.allSatisfy(\.isNumber), let year = Int(String(run)) else {
            return false
        }
        return (1900...2099).contains(year)
    }

    /// The runs that are a straight walk through a keyboard row or an alphabet.
    ///
    /// Both directions count: `9876` is as guessable as `6789`.
    private static let sequences: [String] = [
        "abcdefghijklmnopqrstuvwxyz",
        "0123456789",
        "qwertyuiop",
        "asdfghjkl",
        "zxcvbnm",
    ]

    private static func isSequence(_ run: [Character]) -> Bool {
        guard run.count >= 3 else { return false }
        let candidate = String(run).lowercased()
        for sequence in sequences {
            if sequence.contains(candidate) { return true }
            if String(sequence.reversed()).contains(candidate) { return true }
        }
        return false
    }

    // MARK: - Naming the weakness

    /// Names the one pattern worth fixing, in order of how much it matters.
    ///
    /// The order is the whole design. A user who is told "too short" when the real problem is that
    /// the password is `password1` will lengthen it and learn nothing, so the dictionary checks come
    /// before the length check and the length check comes before the vague one.
    private func weakness(in characters: [Character],
                          matches: [Match],
                          score: PasswordStrength) -> String? {

        // Nothing to fix: either it is strong, or there is nothing there yet.
        guard score != .veryStrong, !characters.isEmpty else { return nil }

        if let whole = matches.first(where: \.isWholePassword) {
            switch whole.kind {
            case .commonPassword:  return L("A commonly used password")
            case .dictionaryWord:  return L("A single dictionary word")
            }
        }

        if characters.count >= 4, Self.hasRepeatedRun(characters) {
            return L("Repeated characters")
        }
        if Self.hasSequence(characters) {
            return L("A keyboard or alphabet sequence")
        }
        if Self.containsYear(characters) {
            return L("A year or date")
        }
        if characters.count < 8 {
            return L("Only %d characters", characters.count)
        }
        return L("Limited character variety")
    }

    private static func hasRepeatedRun(_ characters: [Character]) -> Bool {
        var start = 0
        while start < characters.count {
            var end = start
            while end < characters.count, characters[end] == characters[start] { end += 1 }
            if end - start >= 3 { return true }
            start = end
        }
        return false
    }

    private static func hasSequence(_ characters: [Character]) -> Bool {
        let text = Array(String(characters).lowercased())
        guard text.count >= 3 else { return false }

        for sequence in sequences {
            let forward = Array(sequence)
            let backward = Array(sequence.reversed())
            var run = 1
            for index in 1..<text.count {
                let previous = text[index - 1]
                let current = text[index]
                if follows(forward, previous, current) || follows(backward, previous, current) {
                    run += 1
                    if run >= 3 { return true }
                } else {
                    run = 1
                }
            }
        }
        return false
    }

    /// Whether `next` immediately follows `previous` somewhere in `sequence`.
    private static func follows(_ sequence: [Character], _ previous: Character, _ next: Character) -> Bool {
        guard sequence.count >= 2 else { return false }
        for index in 0..<(sequence.count - 1) where sequence[index] == previous {
            if sequence[index + 1] == next { return true }
        }
        return false
    }

    private static func containsYear(_ characters: [Character]) -> Bool {
        let digits = Array(characters)
        guard digits.count >= 4 else { return false }
        for start in 0...(digits.count - 4) {
            let window = Array(digits[start..<(start + 4)])
            if isYear(window) { return true }
        }
        return false
    }
}
