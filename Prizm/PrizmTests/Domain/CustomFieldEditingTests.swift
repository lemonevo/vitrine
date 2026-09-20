import XCTest
@testable import Prizm

/// Tests for `DraftCustomField` — the mutable mirror that makes custom fields editable.
///
/// The edit sheet supports the full lifecycle (add, rename, retype, reorder, delete), and the row
/// identity is the part that is easy to get wrong: identifying rows by array index makes SwiftUI
/// reuse the view state of whichever row used to sit at that index.
final class DraftCustomFieldTests: XCTestCase {

    // MARK: - Conversion

    func test_initFromCustomField_copiesEveryField() {
        let source = CustomField(name: "env", value: "prod", type: .linked, linkedId: .loginUsername)
        let draft  = DraftCustomField(source)

        XCTAssertEqual(draft.name, "env")
        XCTAssertEqual(draft.value, "prod")
        XCTAssertEqual(draft.type, .linked)
        XCTAssertEqual(draft.linkedId, .loginUsername)
    }

    /// Two drafts of the same field are distinct rows. If they shared an id, `ForEach` would render
    /// only one of them.
    func test_twoDraftsOfTheSameFieldHaveDifferentIds() {
        let source = CustomField(name: "env", value: "prod", type: .text, linkedId: nil)
        XCTAssertNotEqual(DraftCustomField(source).id, DraftCustomField(source).id)
    }

    func test_idSurvivesMutation() {
        var draft = DraftCustomField(name: "a")
        let id = draft.id

        draft.name = "b"
        draft.type = .boolean
        draft.value = "true"

        XCTAssertEqual(draft.id, id, "the row identity must not change when the field is edited")
    }

    // MARK: - Equality

    /// `id` is excluded from equality so that "the draft still matches what was loaded" is a
    /// content question, not an identity one.
    func test_equality_ignoresIdButComparesContent() {
        let a = DraftCustomField(name: "env", value: "prod", type: .text, linkedId: nil)
        var b = DraftCustomField(name: "env", value: "prod", type: .text, linkedId: nil)
        XCTAssertEqual(a, b)

        b.name = "other"
        XCTAssertNotEqual(a, b)

        b = DraftCustomField(name: "env", value: "prod", type: .text, linkedId: nil)
        b.value = "dev"
        XCTAssertNotEqual(a, b)

        b = DraftCustomField(name: "env", value: "prod", type: .text, linkedId: nil)
        b.type = .hidden
        XCTAssertNotEqual(a, b)

        b = DraftCustomField(name: "env", value: "prod", type: .linked, linkedId: .loginPassword)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Blank names

    func test_hasBlankName() {
        XCTAssertTrue(DraftCustomField().hasBlankName)
        XCTAssertTrue(DraftCustomField(name: "").hasBlankName)
        XCTAssertTrue(DraftCustomField(name: "   ").hasBlankName)
        XCTAssertTrue(DraftCustomField(name: "\n\t ").hasBlankName)
        XCTAssertFalse(DraftCustomField(name: "env").hasBlankName)
        XCTAssertFalse(DraftCustomField(name: " env ").hasBlankName)
    }

    // MARK: - Defaults

    func test_defaultInit_isAnEmptyTextField() {
        let draft = DraftCustomField()
        XCTAssertEqual(draft.name, "")
        XCTAssertNil(draft.value)
        XCTAssertEqual(draft.type, .text)
        XCTAssertNil(draft.linkedId)
    }
}

// MARK: - Lifecycle through DraftVaultItem

final class CustomFieldEditingTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeItem(customFields: [CustomField] = []) -> VaultItem {
        VaultItem(
            id: "id-1", name: "GitHub", isFavorite: false, isDeleted: false,
            creationDate: baseDate, revisionDate: baseDate,
            content: .login(LoginContent(
                username: "octocat", password: "p", uris: [],
                totp: nil, notes: nil, customFields: customFields
            ))
        )
    }

    private func loginContent(of item: VaultItem) -> LoginContent? {
        guard case .login(let content) = item.content else { return nil }
        return content
    }

    private func loginContent(of draft: DraftVaultItem) -> DraftLoginContent? {
        guard case .login(let content) = draft.content else { return nil }
        return content
    }

    private func mutateLoginFields(of draft: inout DraftVaultItem,
                                   _ body: (inout [DraftCustomField]) -> Void) {
        guard case .login(var content) = draft.content else {
            return XCTFail("expected a login draft")
        }
        body(&content.customFields)
        draft.content = .login(content)
    }

    // MARK: - Add

    func test_add_roundTripsToTheSavedItem() {
        var draft = DraftVaultItem(makeItem())
        mutateLoginFields(of: &draft) {
            $0.append(DraftCustomField(name: "env", value: "prod", type: .text))
        }

        let fields = loginContent(of: VaultItem(draft))?.customFields ?? []
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields.first?.name, "env")
        XCTAssertEqual(fields.first?.value, "prod")
        XCTAssertEqual(fields.first?.type, .text)
    }

    func test_add_keepsExistingFields() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "existing", value: "1", type: .text, linkedId: nil)
        ]))
        mutateLoginFields(of: &draft) {
            $0.append(DraftCustomField(name: "added", value: "2", type: .text))
        }

        let names = (loginContent(of: VaultItem(draft))?.customFields ?? []).map(\.name)
        XCTAssertEqual(names, ["existing", "added"])
    }

    // MARK: - Rename / retype

    func test_rename_reachesTheSavedItem() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "old", value: "v", type: .text, linkedId: nil)
        ]))
        mutateLoginFields(of: &draft) { $0[0].name = "renamed" }

        XCTAssertEqual(loginContent(of: VaultItem(draft))?.customFields.first?.name, "renamed")
    }

    func test_retype_reachesTheSavedItem() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "flag", value: "true", type: .text, linkedId: nil)
        ]))
        mutateLoginFields(of: &draft) { $0[0].type = .boolean }

        XCTAssertEqual(loginContent(of: VaultItem(draft))?.customFields.first?.type, .boolean)
    }

    /// Switching to `.linked` and back must not leave a stale `linkedId` behind — the mapper would
    /// otherwise emit a linked field whose type is `.text`.
    func test_retypeToLinkedAndBack_clearsLinkedId() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "f", value: nil, type: .text, linkedId: nil)
        ]))

        mutateLoginFields(of: &draft) {
            $0[0].type = .linked
            $0[0].linkedId = .loginUsername
            $0[0].value = nil
        }
        XCTAssertEqual(loginContent(of: VaultItem(draft))?.customFields.first?.linkedId, .loginUsername)

        mutateLoginFields(of: &draft) {
            $0[0].type = .text
            $0[0].linkedId = nil
        }
        XCTAssertNil(loginContent(of: VaultItem(draft))?.customFields.first?.linkedId)
    }

    // MARK: - Delete

    func test_delete_removesOnlyThatField() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "a", value: "1", type: .text, linkedId: nil),
            CustomField(name: "b", value: "2", type: .text, linkedId: nil),
            CustomField(name: "c", value: "3", type: .text, linkedId: nil)
        ]))
        mutateLoginFields(of: &draft) { $0.remove(at: 1) }

        XCTAssertEqual((loginContent(of: VaultItem(draft))?.customFields ?? []).map(\.name), ["a", "c"])
    }

    /// Deleting by identity rather than by index is what keeps each row's transient view state with
    /// its own field. This is the property the stable `UUID` exists for.
    func test_deleteByIdentity_leavesTheOtherRowIdentitiesIntact() {
        var draft = DraftVaultItem(makeItem())
        mutateLoginFields(of: &draft) {
            $0 = [DraftCustomField(name: "a"), DraftCustomField(name: "b"), DraftCustomField(name: "c")]
        }

        guard case .login(let content) = draft.content else { return XCTFail("expected a login draft") }
        let ids = content.customFields.map(\.id)

        mutateLoginFields(of: &draft) { fields in
            fields.removeAll { $0.id == ids[1] }
        }

        guard case .login(let after) = draft.content else { return XCTFail("expected a login draft") }
        XCTAssertEqual(after.customFields.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(after.customFields.map(\.name), ["a", "c"])
    }

    // MARK: - Reorder

    func test_reorder_roundTripsToTheSavedItem() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "a", value: "1", type: .text, linkedId: nil),
            CustomField(name: "b", value: "2", type: .text, linkedId: nil),
            CustomField(name: "c", value: "3", type: .text, linkedId: nil)
        ]))
        mutateLoginFields(of: &draft) { $0.swapAt(0, 2) }

        XCTAssertEqual((loginContent(of: VaultItem(draft))?.customFields ?? []).map(\.name), ["c", "b", "a"])
    }

    func test_moveUpAndDown_roundTrip() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "a", value: nil, type: .text, linkedId: nil),
            CustomField(name: "b", value: nil, type: .text, linkedId: nil)
        ]))

        mutateLoginFields(of: &draft) { $0.swapAt(0, 1) }
        XCTAssertEqual((loginContent(of: VaultItem(draft))?.customFields ?? []).map(\.name), ["b", "a"])

        mutateLoginFields(of: &draft) { $0.swapAt(0, 1) }
        XCTAssertEqual((loginContent(of: VaultItem(draft))?.customFields ?? []).map(\.name), ["a", "b"])
    }

    // MARK: - allCustomFields across the five content types

    func test_allCustomFields_coversEveryContentType() {
        let field = CustomField(name: "env", value: "prod", type: .text, linkedId: nil)

        let items: [VaultItem] = [
            VaultItem(id: "1", name: "L", isFavorite: false, isDeleted: false,
                      creationDate: baseDate, revisionDate: baseDate,
                      content: .login(LoginContent(username: nil, password: nil, uris: [],
                                                   totp: nil, notes: nil, customFields: [field]))),
            VaultItem(id: "2", name: "C", isFavorite: false, isDeleted: false,
                      creationDate: baseDate, revisionDate: baseDate,
                      content: .card(CardContent(cardholderName: nil, brand: nil, number: nil,
                                                 expMonth: nil, expYear: nil, code: nil,
                                                 notes: nil, customFields: [field]))),
            VaultItem(id: "3", name: "I", isFavorite: false, isDeleted: false,
                      creationDate: baseDate, revisionDate: baseDate,
                      content: .identity(IdentityContent(title: nil, firstName: nil, middleName: nil,
                                                         lastName: nil, address1: nil, address2: nil,
                                                         address3: nil, city: nil, state: nil,
                                                         postalCode: nil, country: nil, company: nil,
                                                         email: nil, phone: nil, ssn: nil, username: nil,
                                                         passportNumber: nil, licenseNumber: nil,
                                                         notes: nil, customFields: [field]))),
            VaultItem(id: "4", name: "S", isFavorite: false, isDeleted: false,
                      creationDate: baseDate, revisionDate: baseDate,
                      content: .secureNote(SecureNoteContent(notes: nil, customFields: [field]))),
            VaultItem(id: "5", name: "K", isFavorite: false, isDeleted: false,
                      creationDate: baseDate, revisionDate: baseDate,
                      content: .sshKey(SSHKeyContent(privateKey: nil, publicKey: nil,
                                                     keyFingerprint: nil, notes: nil,
                                                     customFields: [field])))
        ]

        for item in items {
            let draft = DraftVaultItem(item)
            XCTAssertEqual(draft.allCustomFields.map(\.name), ["env"],
                           "allCustomFields must see the fields of a \(item.content)")
        }
    }

    func test_allCustomFields_isEmptyForAnItemWithoutFields() {
        XCTAssertTrue(DraftVaultItem(makeItem()).allCustomFields.isEmpty)
    }

    // MARK: - unnamedCustomFields (the save guard)

    func test_unnamedCustomFields_findsBlankNames() {
        var draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "good", value: nil, type: .text, linkedId: nil),
            CustomField(name: "", value: nil, type: .text, linkedId: nil)
        ]))
        mutateLoginFields(of: &draft) { $0.append(DraftCustomField(name: "   ")) }

        XCTAssertEqual(draft.unnamedCustomFields.count, 2)
    }

    func test_unnamedCustomFields_isEmptyWhenEveryFieldIsNamed() {
        let draft = DraftVaultItem(makeItem(customFields: [
            CustomField(name: "a", value: nil, type: .text, linkedId: nil),
            CustomField(name: "b", value: nil, type: .text, linkedId: nil)
        ]))
        XCTAssertTrue(draft.unnamedCustomFields.isEmpty)
    }
}

// MARK: - LinkedFieldId options

final class LinkedFieldOptionsTests: XCTestCase {

    func test_options_forLogin() {
        XCTAssertEqual(LinkedFieldId.options(for: .login), [.loginUsername, .loginPassword])
    }

    func test_options_forCard() {
        XCTAssertEqual(LinkedFieldId.options(for: .card),
                       [.cardCardholderName, .cardBrand, .cardNumber,
                        .cardExpMonth, .cardExpYear, .cardCode])
    }

    func test_options_forIdentity_hasNoDuplicates() {
        let options = LinkedFieldId.options(for: .identity)
        XCTAssertFalse(options.isEmpty)
        XCTAssertEqual(Set(options).count, options.count)
    }

    /// A secure note and an SSH key have no native fields, so `.linked` must not even be offered —
    /// showing it and rejecting the choice afterwards would be worse than not showing it.
    func test_options_areEmptyForSecureNoteAndSSHKey() {
        XCTAssertTrue(LinkedFieldId.options(for: .secureNote).isEmpty)
        XCTAssertTrue(LinkedFieldId.options(for: .sshKey).isEmpty)
    }

    /// The whole point of the per-type split: a login must not be able to link to a card field, and
    /// vice versa. The server would accept it and no client would resolve it.
    func test_options_neverMixItemTypes() {
        XCTAssertFalse(LinkedFieldId.options(for: .login).contains(.cardNumber))
        XCTAssertFalse(LinkedFieldId.options(for: .card).contains(.loginPassword))
        XCTAssertFalse(LinkedFieldId.options(for: .identity).contains(.loginPassword))
    }

    func test_supportsLinking() {
        XCTAssertTrue(LinkedFieldId.supportsLinking(.login))
        XCTAssertTrue(LinkedFieldId.supportsLinking(.card))
        XCTAssertTrue(LinkedFieldId.supportsLinking(.identity))
        XCTAssertFalse(LinkedFieldId.supportsLinking(.secureNote))
        XCTAssertFalse(LinkedFieldId.supportsLinking(.sshKey))
    }

    func test_availableFieldTypes_removesLinkedWhereThereIsNothingToLinkTo() {
        XCTAssertEqual(LinkedFieldId.availableFieldTypes(for: .login), CustomFieldType.allCases)
        XCTAssertEqual(LinkedFieldId.availableFieldTypes(for: .card), CustomFieldType.allCases)
        XCTAssertEqual(LinkedFieldId.availableFieldTypes(for: .identity), CustomFieldType.allCases)

        XCTAssertEqual(LinkedFieldId.availableFieldTypes(for: .secureNote),
                       CustomFieldType.allCases.filter { $0 != .linked })
        XCTAssertEqual(LinkedFieldId.availableFieldTypes(for: .sshKey),
                       CustomFieldType.allCases.filter { $0 != .linked })
    }

    func test_availableFieldTypes_neverReturnsAnEmptyPicker() {
        for type in ItemType.allCases {
            XCTAssertFalse(LinkedFieldId.availableFieldTypes(for: type).isEmpty,
                           "\(type) would show an empty type picker")
        }
    }
}

// MARK: - CustomFieldType metadata

final class CustomFieldTypeTests: XCTestCase {

    func test_allCases_areOrderedForThePicker() {
        XCTAssertEqual(CustomFieldType.allCases, [.text, .hidden, .boolean, .linked])
    }

    func test_allCases_haveNonEmptyDistinctLabels() {
        let labels = CustomFieldType.allCases.map(\.displayName)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertEqual(Set(labels).count, labels.count)
    }
}
