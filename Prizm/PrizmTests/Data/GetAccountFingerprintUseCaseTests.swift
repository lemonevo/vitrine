import XCTest
@testable import Prizm

// MARK: - GetAccountFingerprintUseCaseTests

/// The wiring around the phrase, not the phrase itself — `AccountFingerprintPhraseTests` owns that,
/// against the reference's own published vectors.
///
/// What is worth covering here is *which two values reach the function*, because both are looked up
/// rather than passed and both have an equally plausible neighbour: the account carries an email as
/// well as an id, and a public key exists in more than one encoding. Either substitution yields a
/// well-formed phrase that matches nothing else, so nothing fails unless a test says so.
final class GetAccountFingerprintUseCaseTests: XCTestCase {

    private var auth: MockAuthRepository!
    private var keys: AccountKeyCache!
    private var sut:  GetAccountFingerprintUseCaseImpl!

    override func setUp() async throws {
        auth = MockAuthRepository()
        keys = AccountKeyCache()
        sut  = GetAccountFingerprintUseCaseImpl(
            auth: auth, accountKeyCache: keys, wordList: try Self.wordList())
    }

    // MARK: - When there is nothing to show

    func testNoStoredAccount_returnsNil() async throws {
        await keys.store(publicKey: Self.publicKey)
        auth.stubbedStoredAccount = nil

        // XCTest's assertions are autoclosures and cannot contain `await`, so the call is bound
        // first — a constraint worth knowing, since the obvious one-liner does not compile.
        let phrase = try await sut.execute()
        XCTAssertNil(phrase)
    }

    /// The ordinary state of a Settings window opened before the first sync finishes. A `nil` and
    /// not a thrown error, because there is nothing here for the user to fix.
    func testNoPublicKeyYet_returnsNil() async throws {
        auth.stubbedStoredAccount = Self.account()

        let phrase = try await sut.execute()
        XCTAssertNil(phrase)
    }

    // MARK: - Which values reach the phrase

    /// The material is the **user id**, not the email.
    ///
    /// Asserted by way of the pure function rather than a literal phrase, because the pure
    /// function is pinned to the reference's vectors in its own suite — so agreeing with it here is
    /// agreeing with Bitwarden, while pinning the same phrase twice would only mean the two suites
    /// agree with each other.
    func testPhrase_isDerivedFromTheUserIdNotTheEmail() async throws {
        let account = Self.account()
        auth.stubbedStoredAccount = account
        await keys.store(publicKey: Self.publicKey)

        let phrase = try await sut.execute()

        let wordList = try Self.wordList()
        let expected = try AccountFingerprintPhrase.phrase(
            material: account.userId, publicKey: Self.publicKey, wordList: wordList)
        let ifItHadUsedTheEmail = try AccountFingerprintPhrase.phrase(
            material: account.email, publicKey: Self.publicKey, wordList: wordList)

        XCTAssertEqual(phrase, expected)
        XCTAssertNotEqual(phrase, ifItHadUsedTheEmail,
                          "the email would produce a plausible phrase that matches no other client")
    }

    /// The key is used exactly as cached — no re-encoding, no re-derivation. The cache stores the
    /// SPKI form specifically because that is what the reference hashes, and a step here that
    /// re-wrapped it would silently change every phrase.
    func testPhrase_usesTheCachedKeyUnchanged() async throws {
        auth.stubbedStoredAccount = Self.account()
        await keys.store(publicKey: Self.publicKey)

        let phrase = try await sut.execute()
        let expected = try AccountFingerprintPhrase.phrase(
            material: Self.account().userId, publicKey: Self.publicKey, wordList: try Self.wordList())

        XCTAssertEqual(phrase, expected)
    }

    // MARK: - Fixtures

    private static let publicKey = Data(repeating: 0x5A, count: 294)

    private static func account() -> Account {
        Account(
            userId:            "a09726a0-9590-49d1-a5f5-afe300b6a515",
            email:             "someone@example.com",
            name:              nil,
            serverEnvironment: ServerEnvironment(base: URL(string: "https://vault.example.com")!)
        )
    }

        /// The reference word list, read the way production reads it: from the app bundle.
    ///
    /// See the note in `AccountFingerprintPhraseTests` — the source-tree path this replaced made the
    /// suite read a file under `~/Desktop`, a TCC-protected location, and hung there once the bundle
    /// identifier changed.
    private static func wordList() throws -> [String] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "eff-large-wordlist", withExtension: "txt"),
            "Vitrine.app carries no eff-large-wordlist.txt — the resource is not in the build"
        )
        let words = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard words.count == 7776 else { throw FixtureError.unexpectedWordCount(words.count) }
        return words
    }

    private enum FixtureError: Error {
        case unexpectedWordCount(Int)
    }
}
