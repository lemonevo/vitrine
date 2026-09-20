import XCTest
@testable import Prizm

/// Tests for the TOTP seed field the edit form gained.
///
/// The field exists because a seed can only be obtained from the issuing service's own page, so an
/// item imported without one could never be finished inside Prizm. What makes that worth testing is
/// not that a text field accepts text — it is that the value **reaches the wire** and that a value
/// which cannot work says so instead of saving silently.
@MainActor
final class ItemEditViewModelTotpSeedTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A syntactically valid Base32 secret. Nothing here asserts which code it produces — that is
    /// `TOTPGeneratorImpl`'s own suite. This file only asks whether a code is produced at all.
    private static let validSeed   = "JBSWY3DPEHPK3PXP"
    private static let validKeyURI = "otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example"

    // MARK: - Fixtures

    private func makeLogin(totp: String?) -> VaultItem {
        VaultItem(
            id: "id-1",
            name: "Example",
            isFavorite: false,
            isDeleted: false,
            creationDate: baseDate,
            revisionDate: baseDate,
            content: .login(LoginContent(
                username: "alice",
                password: "hunter2",
                uris: [],
                totp: totp,
                notes: nil,
                customFields: []
            ))
        )
    }

    private func makeSUT(_ item: VaultItem) -> (ItemEditViewModel, MockVaultRepository) {
        let repository = MockVaultRepository()
        let sut = ItemEditViewModel(
            item: item,
            useCase: EditVaultItemUseCaseImpl(repository: repository)
        )
        return (sut, repository)
    }

    /// Replaces the seed the way the form does, through the projected binding rather than by
    /// reaching into the draft's stored properties.
    private func setSeed(_ seed: String?, on sut: ItemEditViewModel) {
        guard case .login(var content) = sut.draft.content else {
            return XCTFail("fixture is not a login item")
        }
        content.totp = seed
        sut.draft.content = .login(content)
    }

    // MARK: - totpSeedProducesCode

    func testTotpSeedProducesCode_isNilWhenThereIsNoSeed() {
        let (sut, _) = makeSUT(makeLogin(totp: nil))
        XCTAssertNil(sut.totpSeedProducesCode,
                     "an absent seed is not a broken seed — there is nothing to warn about")
    }

    /// Whitespace-only is treated as absent. A field the user has not typed in must not accuse them
    /// of having entered something unusable.
    func testTotpSeedProducesCode_isNilWhenTheSeedIsBlank() {
        let (sut, _) = makeSUT(makeLogin(totp: "   \n  "))
        XCTAssertNil(sut.totpSeedProducesCode)
    }

    func testTotpSeedProducesCode_isTrueForABase32Secret() {
        let (sut, _) = makeSUT(makeLogin(totp: Self.validSeed))
        XCTAssertEqual(sut.totpSeedProducesCode, true)
    }

    /// The Key URI form has to work too. It is what a site hands out far more often than a bare
    /// secret, and it carries the period and digit count some services change.
    func testTotpSeedProducesCode_isTrueForKeyURI() {
        let (sut, _) = makeSUT(makeLogin(totp: Self.validKeyURI))
        XCTAssertEqual(sut.totpSeedProducesCode, true)
    }

    /// A URL. Pasting the wrong thing out of the setup page is the common mistake, and it is
    /// exactly the case this warning exists for: the field will otherwise save it and the item
    /// will show no code, with nothing pointing at the seed as the cause.
    func testTotpSeedProducesCode_isFalseForAURL() {
        let (sut, _) = makeSUT(makeLogin(totp: "https://example.com/totp-setup"))
        XCTAssertEqual(sut.totpSeedProducesCode, false)
    }

    /// A Key URI whose `secret=` was lost — what a truncated paste or a copied breadcrumb looks
    /// like. It starts with `otpauth://`, so it takes the URI path and then has nothing to read.
    func testTotpSeedProducesCode_isFalseForAKeyURIWithNoSecret() {
        let (sut, _) = makeSUT(makeLogin(totp: "otpauth://totp/Example:alice?issuer=Example"))
        XCTAssertEqual(sut.totpSeedProducesCode, false)
    }

    /// The boundary worth recording, because it is the opposite of what a reader expects: the
    /// Base32 alphabet is A-Z plus 2-7, so a run of ordinary letters **is** a valid secret.
    ///
    /// This is why the warning catches URLs and truncated URIs rather than prose — prose decodes
    /// and produces a code that will not match anything, which no amount of checking here can
    /// detect. Only the issuing service knows whether a secret is the right one.
    func testTotpSeedProducesCode_isTrueForAStringOfPlainLetters() {
        let (sut, _) = makeSUT(makeLogin(totp: "notasecret"))
        XCTAssertEqual(sut.totpSeedProducesCode, true)
    }

    /// The readout belongs to the login form; a secure note has no seed field to sit under.
    func testTotpSeedProducesCode_isNilForANonLoginItem() {
        let note = VaultItem(
            id: "id-2",
            name: "Note",
            isFavorite: false,
            isDeleted: false,
            creationDate: baseDate,
            revisionDate: baseDate,
            content: .secureNote(SecureNoteContent(notes: "hello", customFields: []))
        )
        let (sut, _) = makeSUT(note)
        XCTAssertNil(sut.totpSeedProducesCode)
    }

    // MARK: - What the warning must not do

    /// A seed that cannot produce a code is reported, never refused.
    ///
    /// Bitwarden stores what the user pastes, and a service that emits an unusual shape would
    /// otherwise be impossible to record at all. Blocking the save would turn a warning into a
    /// lockout, which is the failure this whole field exists to remove.
    func testUnusableSeed_doesNotBlockSaving() {
        let (sut, _) = makeSUT(makeLogin(totp: nil))
        setSeed("https://example.com/totp-setup", on: sut)

        XCTAssertEqual(sut.totpSeedProducesCode, false)
        XCTAssertNil(sut.validationError)
        XCTAssertTrue(sut.canSave)
    }

    // MARK: - Reaching the wire

    func testEditingTheSeed_marksTheFormDirty() {
        let (sut, _) = makeSUT(makeLogin(totp: nil))
        XCTAssertFalse(sut.hasChanges)

        setSeed(Self.validSeed, on: sut)

        XCTAssertTrue(sut.hasChanges,
                      "a changed seed has to trigger the discard prompt like any other edit")
    }

    /// The point of the field. A seed that is editable but does not travel with the draft would
    /// look finished and save nothing.
    func testSaving_carriesTheEditedSeed() async throws {
        let (sut, repository) = makeSUT(makeLogin(totp: nil))
        setSeed(Self.validKeyURI, on: sut)

        sut.save()
        try await waitUntil { repository.lastUpdatedDraft != nil }

        guard case .login(let saved)? = repository.lastUpdatedDraft?.content else {
            return XCTFail("the saved draft is not a login item")
        }
        XCTAssertEqual(saved.totp, Self.validKeyURI)
    }

    /// Clearing the field has to clear it on the server too. An item with the seed removed still
    /// showing codes would be worse than one that never had any.
    func testSaving_carriesTheClearedSeed() async throws {
        let (sut, repository) = makeSUT(makeLogin(totp: Self.validSeed))
        setSeed(nil, on: sut)

        sut.save()
        try await waitUntil { repository.lastUpdatedDraft != nil }

        guard case .login(let saved)? = repository.lastUpdatedDraft?.content else {
            return XCTFail("the saved draft is not a login item")
        }
        XCTAssertNil(saved.totp)
    }

    // MARK: - Helpers

    /// `save()` is fire-and-forget, so the assertion has to wait for the write rather than assume
    /// it has happened.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition was not met within \(timeout)")
    }
}
