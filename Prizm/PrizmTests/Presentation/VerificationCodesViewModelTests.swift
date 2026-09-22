import XCTest
@testable import Prizm

/// The verification-codes list.
///
/// Two things are being asserted here, and the second matters more than the first: which items appear,
/// and that the list is **not a way around the re-prompt gate**. A screen that showed every code
/// openly would withhold nothing while the gate went on asking for a password on the item itself.
@MainActor
final class VerificationCodesViewModelTests: XCTestCase {

    private var vault: MockVaultRepository!

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
    }

    // MARK: - Fixtures

    private func login(id: String = "1", name: String = "GitHub",
                       totp: String?, username: String? = "octocat",
                       reprompt: Int = 0, isDeleted: Bool = false) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: isDeleted,
            creationDate: now, revisionDate: now,
            content: .login(LoginContent(
                username: username, password: "p", uris: [], totp: totp,
                notes: nil, customFields: []
            )),
            reprompt: reprompt
        )
    }

    private func seed(_ items: [VaultItem]) async {
        await vault.populate(items: items, folders: [], organizations: [],
                             collections: [], syncedAt: now)
    }

    /// A gate that reports what the test tells it to, and records what it was asked to copy.
    private final class RecordingGate {
        var gated: Set<String> = []
        var revealed: Set<String> = []
        private(set) var copied: [String] = []

        func binding(for item: VaultItem) -> RevealGateBinding {
            guard gated.contains(item.id) else { return .none }
            return .gated(
                isRevealed:     revealed.contains(item.id),
                request:        { self.revealed.insert(item.id) },
                copyGated:      { self.copied.append($0) }
            )
        }
    }

    private func makeSUT(gate: RecordingGate = RecordingGate()) -> VerificationCodesViewModel {
        VerificationCodesViewModel(
            vault:     vault,
            generator: StubTOTPGenerator(code: "654321", period: 30),
            gateFor:   { gate.binding(for: $0) },
            now:       { self.now }
        )
    }

    // MARK: - 1.1 / 1.2 which items appear

    func testStart_includesALoginWithASecret() async {
        await seed([login(totp: "JBSWY3DPEHPK3PXP")])
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.rows.count, 1)
        XCTAssertEqual(sut.rows.first?.name, "GitHub")
        XCTAssertEqual(sut.rows.first?.username, "octocat")
    }

    func testStart_excludesALoginWithoutASecret() async {
        await seed([login(totp: nil), login(id: "2", name: "Empty", totp: "")])
        let sut = makeSUT()

        await sut.start()

        XCTAssertTrue(sut.rows.isEmpty, "a row without a code would be a lie about the item")
    }

    /// 1.3 Only a login carries a TOTP secret; the other types must not appear even if one somehow had
    /// a value in that position.
    func testStart_excludesOtherItemTypes() async {
        await seed([
            VaultItem(id: "c", name: "Visa", isFavorite: false, isDeleted: false,
                      creationDate: now, revisionDate: now,
                      content: .card(CardContent(cardholderName: nil, brand: nil, number: nil,
                                                 expMonth: nil, expYear: nil, code: nil,
                                                 notes: nil, customFields: []))),
            VaultItem(id: "n", name: "A Note", isFavorite: false, isDeleted: false,
                      creationDate: now, revisionDate: now,
                      content: .secureNote(SecureNoteContent(notes: "x", customFields: []))),
            login(totp: "JBSWY3DPEHPK3PXP")
        ])
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.rows.map(\.id), ["1"], "only the login has a code")
    }

    // MARK: - 1.4 Trash

    func testStart_excludesTrashedItems() async {
        await seed([login(totp: "JBSWY3DPEHPK3PXP", isDeleted: true)])
        let sut = makeSUT()

        await sut.start()

        XCTAssertTrue(
            sut.rows.isEmpty,
            "a code one click away for an item the user believes they deleted"
        )
    }

    // MARK: - 1.5 an unusable secret is reported, not hidden

    func testStart_unusableSecret_getsARowMarkedUnusable() async {
        // The stub yields no window when it has no code to give, which is what an unreadable seed
        // amounts to here.
        await seed([login(totp: "JBSWY3DPEHPK3PXP")])
        let sut = VerificationCodesViewModel(
            vault:     vault,
            generator: StubTOTPGenerator(code: nil),
            gateFor:   { _ in .none },
            now:       { self.now }
        )

        await sut.start()
        sut.rows.first?.code.refresh(at: now)

        // The row exists — the item *has* a key — and says it cannot produce a code rather than being
        // dropped as though the key were absent.
        XCTAssertEqual(sut.rows.count, 1)
        XCTAssertTrue(sut.rows[0].code.isUnusable)
        XCTAssertNil(sut.rows[0].code.copyValue, "nothing to copy, so nothing is offered")
    }

    // MARK: - 2.1 / 2.4 the gate is not bypassed

    func testStart_gatedItem_reportsItselfGated() async {
        await seed([login(totp: "JBSWY3DPEHPK3PXP", reprompt: 1)])
        let gate = RecordingGate()
        gate.gated = ["1"]
        let sut = makeSUT(gate: gate)

        await sut.start()

        XCTAssertEqual(sut.rows.count, 1)
        XCTAssertTrue(sut.rows[0].gate.isGated, "a re-prompt item must stay protected in the list")
        XCTAssertFalse(sut.rows[0].gate.isRevealed, "and start withheld")
    }

    /// The detail pane only builds a gate for a protected item, and so does this: a gate that asks for
    /// nothing teaches people to click through prompts.
    func testStart_unprotectedItem_isNotGated() async {
        await seed([login(totp: "JBSWY3DPEHPK3PXP")])
        let sut = makeSUT()

        await sut.start()

        XCTAssertFalse(sut.rows[0].gate.isGated)
    }

    /// 2.3 The assertion the security claim rests on: a gated row's copy must go through `copyGated`.
    /// Reading `code.copyValue` directly — the obvious shortcut — is precisely the walk-around.
    func testCopy_ofAGatedRow_goesThroughTheGate() async {
        await seed([login(totp: "JBSWY3DPEHPK3PXP", reprompt: 1)])
        let gate = RecordingGate()
        gate.gated = ["1"]
        let sut = makeSUT(gate: gate)
        await sut.start()
        sut.rows[0].code.refresh(at: now)

        sut.copy(sut.rows[0])

        XCTAssertEqual(gate.copied, ["654321"], "the copy must have been routed through the gate")
    }

    func testCopy_ofAnUngatedRow_doesNotAskTheGate() async {
        await seed([login(totp: "JBSWY3DPEHPK3PXP")])
        let gate = RecordingGate()
        let sut = makeSUT(gate: gate)
        await sut.start()
        sut.rows[0].code.refresh(at: now)

        sut.copy(sut.rows[0])

        XCTAssertTrue(gate.copied.isEmpty, "an unprotected item has nothing to ask for")
    }

    // MARK: - 2.2 the seed never reaches the list

    /// A TOTP seed generates codes forever. The detail pane never shows it and the copy commands never
    /// put it on the clipboard; a list multiplies the chances of that going wrong, so it is asserted
    /// rather than assumed.
    func testRows_neverExposeTheStoredSecret() async {
        let secret = "JBSWY3DPEHPK3PXP"
        await seed([login(totp: secret)])
        let gate = RecordingGate()
        let sut = makeSUT(gate: gate)
        await sut.start()
        sut.rows[0].code.refresh(at: now)

        XCTAssertEqual(sut.rows[0].code.copyValue, "654321")
        XCTAssertNotEqual(sut.rows[0].code.copyValue, secret)

        sut.copy(sut.rows[0])

        XCTAssertFalse(gate.copied.contains(secret), "the seed must never reach the clipboard")
    }

    // MARK: - 1.6 / lifecycle

    func testStop_releasesTheRows() async {
        await seed([login(totp: "JBSWY3DPEHPK3PXP")])
        let sut = makeSUT()
        await sut.start()
        XCTAssertEqual(sut.rows.count, 1)

        sut.stop()

        // One timer per row: a dismissed sheet must not leave a vault's worth of them deriving codes.
        XCTAssertTrue(sut.rows.isEmpty)
    }

    func testStart_withAnUnreadableVault_yieldsNoRowsRatherThanFailing() async {
        let sut = makeSUT()
        // No populate call: the mock starts empty, which is the vault-reads-as-empty case.
        await sut.start()

        XCTAssertTrue(sut.rows.isEmpty)
    }
}
