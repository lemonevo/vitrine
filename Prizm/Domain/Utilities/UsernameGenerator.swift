import Foundation

/// Generates a username from a word list.
///
/// **Why this is not `PasswordGenerator`.** That type's design is dominated by entropy: character
/// pools, ambiguous-character filtering, a documented modulo-bias trade-off. None of it applies here.
/// A username is displayed in plain sight, printed on receipts and said out loud, and sites treat it
/// as public — so the only things that matter are that it is readable and that it is not the same as
/// everybody else's. Reusing the password machinery would have imported a security argument that is
/// not being made.
///
/// The shape is `<word>.<word>[<digits>]`. Words come from the same list the passphrase mode uses.
struct UsernameGenerator {

    /// Injected rather than read from the bundle so a test can supply a known list, the same seam
    /// `PasswordGenerator` uses for randomness.
    private let wordList: [String]

    init(wordList: [String] = PasswordGenerator.effWordList) {
        self.wordList = wordList
    }

    /// How many digits trail the words when `includeNumber` is set.
    ///
    /// Small on purpose: four digits distinguish two people who picked the same two words, which is
    /// the entire job. A longer run would look like a secret and be treated like one.
    static let digitCount = 4

    enum GenerationError: Error, LocalizedError {
        /// The word list is empty — in practice a build whose word-list resource is missing.
        /// Thrown rather than returning an empty username, which would look like a generator bug to
        /// the user and be silently accepted by whatever field it was pasted into.
        case wordListUnavailable

        var errorDescription: String? {
            switch self {
            case .wordListUnavailable:
                return L("The word list is unavailable, so no username could be generated.")
            }
        }
    }

    func generate(config: PasswordGeneratorConfig, provider: RandomnessProvider) throws -> String {
        guard !wordList.isEmpty else { throw GenerationError.wordListUnavailable }

        // At least one word: a bare number is not a username anyone asked for.
        let count = max(1, config.usernameWordCount)
        var words: [String] = []
        words.reserveCapacity(count)
        for _ in 0..<count {
            words.append(try pick(from: wordList, provider: provider))
        }

        var value = words.joined(separator: ".")
        if config.usernameIncludeNumber {
            value += try digits(provider: provider)
        }
        return value
    }

    // MARK: - Private

    private func pick(from list: [String], provider: RandomnessProvider) throws -> String {
        // One byte, re-drawn on a miss rather than taken modulo: unlike the password generator, the
        // pool here is small enough that `% count` would visibly favour the first entries, and the
        // cost of re-drawing is a single byte.
        let limit = UInt8(clamping: list.count)
        guard let byte = try provider.randomBytes(count: 1).first else {
            return list[0]
        }
        return list[Int(byte % limit)]
    }

    private func digits(provider: RandomnessProvider) throws -> String {
        let bytes = try provider.randomBytes(count: Self.digitCount)
        return bytes.map { String($0 % 10) }.joined()
    }
}
