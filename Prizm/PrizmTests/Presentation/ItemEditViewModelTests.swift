import XCTest
@testable import Prizm

/// Tests for the strength readout `ItemEditViewModel` hands to the login form.
///
/// Only the strength surface is covered here. Save, discard, validation and the vault-lock
/// observer are exercised through `EditVaultItemUseCaseTests` and the UI tests.
@MainActor
final class ItemEditViewModelTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func makeLogin(password: String?) -> VaultItem {
        VaultItem(
            id: "id-1",
            name: "Example",
            isFavorite: false,
            isDeleted: false,
            creationDate: baseDate,
            revisionDate: baseDate,
            content: .login(LoginContent(
                username: "alice",
                password: password,
                uris: [],
                totp: nil,
                notes: nil,
                customFields: []
            ))
        )
    }

    private func makeSUT(_ item: VaultItem) -> ItemEditViewModel {
        ItemEditViewModel(
            item: item,
            useCase: EditVaultItemUseCaseImpl(repository: MockVaultRepository())
        )
    }

    // MARK: - passwordStrength

    func testPasswordStrength_scoresACommonPasswordAsVeryWeak() {
        let sut = makeSUT(makeLogin(password: "password"))

        XCTAssertEqual(sut.passwordStrength?.score, .veryWeak)
        XCTAssertEqual(sut.passwordStrength?.weakness, L("A commonly used password"))
    }

    /// An empty field has nothing to score. A readout that said "very weak" before the user typed
    /// anything would read as an accusation, and the estimator itself names no weakness for an
    /// empty password.
    func testPasswordStrength_isNilForAnEmptyPassword() {
        XCTAssertNil(makeSUT(makeLogin(password: nil)).passwordStrength)
        XCTAssertNil(makeSUT(makeLogin(password: "")).passwordStrength)
    }

    /// The readout belongs to the login form only; a secure note has no password field to sit under.
    func testPasswordStrength_isNilForANonLoginItem() {
        let note = VaultItem(
            id: "id-2",
            name: "Note",
            isFavorite: false,
            isDeleted: false,
            creationDate: baseDate,
            revisionDate: baseDate,
            content: .secureNote(SecureNoteContent(notes: "hello", customFields: []))
        )

        XCTAssertNil(makeSUT(note).passwordStrength)
    }

    /// `passwordStrength` is computed from the draft rather than stored, so an edit to the draft
    /// has to be visible immediately — that is the whole reason it is not cached.
    func testPasswordStrength_followsEditsToTheDraft() {
        let sut = makeSUT(makeLogin(password: "password"))
        XCTAssertEqual(sut.passwordStrength?.score, .veryWeak)

        guard case .login(var content) = sut.draft.content else {
            return XCTFail("expected a login draft")
        }
        content.password = "correct-horse-battery-staple"
        sut.draft.content = .login(content)

        XCTAssertGreaterThanOrEqual(sut.passwordStrength?.score ?? .veryWeak, .strong)
    }
}
