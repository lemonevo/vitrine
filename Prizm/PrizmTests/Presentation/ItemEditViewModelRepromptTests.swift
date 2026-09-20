import XCTest
@testable import Prizm

/// Covers the master-password re-prompt setting in the edit form.
///
/// These are view-model tests rather than UI tests, so they prove the setting's *state*, not that
/// a toggle is on screen — the form is shared by every item type and the placement is described in
/// the commit that added it. What matters here is the two properties the spec states:
///
/// - the setting round-trips through the form as a Bool while staying an `Int` on the wire;
/// - changing it counts as an edit, so the discard confirmation still fires.
@MainActor
final class ItemEditViewModelRepromptTests: XCTestCase {

    // MARK: - Fixtures

    private func makeItem(reprompt: Int, content: ItemContent) -> VaultItem {
        VaultItem(
            id: "item-1",
            name: "Example",
            isFavorite: false,
            isDeleted: false,
            creationDate: Date(timeIntervalSince1970: 0),
            revisionDate: Date(timeIntervalSince1970: 0),
            content: content,
            reprompt: reprompt
        )
    }

    private func makeViewModel(reprompt: Int, content: ItemContent) -> ItemEditViewModel {
        ItemEditViewModel(
            item: makeItem(reprompt: reprompt, content: content),
            useCase: EditVaultItemUseCaseImpl(repository: MockVaultRepository())
        )
    }

    private var loginContent: ItemContent {
        .login(LoginContent(
            username: nil, password: nil, uris: [], totp: nil, notes: nil, customFields: []
        ))
    }

    // MARK: - Reading the setting

    func testItemWithoutReprompt_readsAsOff() {
        let sut = makeViewModel(reprompt: 0, content: loginContent)

        XCTAssertFalse(sut.repromptEnabled)
    }

    func testItemWithReprompt_readsAsOn() {
        let sut = makeViewModel(reprompt: 1, content: loginContent)

        XCTAssertTrue(sut.repromptEnabled)
    }

    // MARK: - Writing the setting

    /// The form binds a Bool; the wire and the domain model carry an Int. Both directions of that
    /// conversion have to hold or the setting silently stops reaching the server.
    func testSettingTheToggle_writesTheWireInteger() {
        let sut = makeViewModel(reprompt: 0, content: loginContent)

        sut.repromptEnabled = true
        XCTAssertEqual(sut.draft.reprompt, 1)

        sut.repromptEnabled = false
        XCTAssertEqual(sut.draft.reprompt, 0)
    }

    /// The spec's "survives an unrelated edit" scenario. Re-prompt is part of the draft, so an
    /// edit elsewhere must not reset it — which is what would happen if the toggle were a separate
    /// `@Published` flag rather than a projection of `draft.reprompt`.
    func testChangingTheName_leavesRepromptEnabled() {
        let sut = makeViewModel(reprompt: 1, content: loginContent)

        sut.draft.name = "Renamed"

        XCTAssertEqual(sut.draft.name, "Renamed")
        XCTAssertTrue(sut.repromptEnabled)
        XCTAssertEqual(sut.draft.reprompt, 1)
    }

    // MARK: - Dirty tracking

    /// Toggling is an edit, so Discard has to ask. A setting the user can lose without being
    /// prompted is the failure this guards against.
    func testTogglingMarksTheFormDirty() {
        let sut = makeViewModel(reprompt: 0, content: loginContent)
        XCTAssertFalse(sut.hasChanges)

        sut.repromptEnabled = true

        XCTAssertTrue(sut.hasChanges)
    }

    /// Toggling is not available for one item type only — the form is shared, and cards,
    /// identities and SSH keys hold secrets worth the same gate.
    func testSettingIsAvailableForANonLoginItem() {
        let sut = makeViewModel(
            reprompt: 1,
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        )

        XCTAssertTrue(sut.repromptEnabled)

        sut.repromptEnabled = false
        XCTAssertEqual(sut.draft.reprompt, 0)
    }
}
