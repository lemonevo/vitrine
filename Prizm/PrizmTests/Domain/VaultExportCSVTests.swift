import XCTest
@testable import Prizm

/// The CSV serializer.
///
/// The point of this file is that a CSV the official client cannot import is worse than no CSV, so
/// every assertion here is about matching a **documented** encoding rather than about producing
/// something reasonable-looking. Where the documentation gave an example, it is reproduced exactly.
@MainActor
final class VaultExportCSVTests: XCTestCase {

    // MARK: - Fixtures

    private func folder(id: String = "f-1", name: String = "Social") -> ExportFolder {
        ExportFolder(id: id, name: name)
    }

    private func login(
        name: String = "Twitter",
        folderId: String? = "f-1",
        favorite: Bool = true,
        reprompt: Int = 0,
        notes: String? = nil,
        fields: [ExportCustomField]? = nil,
        uris: [ExportLoginURI]? = [ExportLoginURI(uri: "twitter.com", match: nil)],
        username: String? = "me@example.com",
        password: String? = "password123",
        totp: String? = nil
    ) -> ExportItem {
        ExportItem(
            id: "c-1", organizationId: nil, folderId: folderId,
            collectionIds: nil, type: 1, reprompt: reprompt, name: name,
            notes: notes, favorite: favorite,
            fields: fields,
            login: ExportLogin(uris: uris, username: username, password: password, totp: totp),
            secureNote: nil, card: nil, identity: nil, sshKey: nil,
            passwordHistory: nil,
            creationDate: nil, revisionDate: nil, deletedDate: nil, archivedDate: nil
        )
    }

    private func document(items: [ExportItem], folders: [ExportFolder] = []) -> VaultExportDocument {
        VaultExportDocument(encrypted: false, folders: folders, items: items)
    }

    private func lines(_ csv: String) -> [String] {
        csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    // MARK: - 1.1 the header

    func testHeader_isTheDocumentedColumnList() {
        let result = VaultExportCSV.serialise(document(items: [login()], folders: [folder()]))

        XCTAssertEqual(
            lines(result.csv).first,
            "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp"
        )
    }

    // MARK: - 1.2 the documented example, byte for byte

    /// The official import-conditions page gives this row as its example:
    ///
    ///     Social,1,login,Twitter,,,0,twitter.com,me@example.com,password123,
    ///
    /// Reproducing it exactly is the strongest available evidence that the encodings are right —
    /// stronger than any reasoning about what they "should" be.
    func testRow_matchesTheDocumentedExample() {
        let result = VaultExportCSV.serialise(document(
            items: [login()], folders: [folder()]
        ))

        XCTAssertEqual(
            lines(result.csv)[1],
            "Social,1,login,Twitter,,,0,twitter.com,me@example.com,password123,"
        )
    }

    // MARK: - 1.3 booleans and reprompt are digits

    func testFavoriteAndReprompt_areDigitsNotWords() {
        let notFavorite = VaultExportCSV.serialise(document(
            items: [login(favorite: false, reprompt: 1)], folders: [folder()]
        ))
        let row = lines(notFavorite.csv)[1].split(separator: ",", omittingEmptySubsequences: false)

        XCTAssertEqual(row[1], "0", "favorite must be 0/1, not false/true")
        XCTAssertEqual(row[6], "1")
    }

    // MARK: - 1.4 RFC 4180 quoting

    func testValueWithAComma_isQuoted() {
        let result = VaultExportCSV.serialise(document(
            items: [login(name: "Doe, John")], folders: [folder()]
        ))

        XCTAssertTrue(lines(result.csv)[1].hasPrefix("Social,1,login,\"Doe, John\","))
    }

    func testValueWithAQuote_hasItDoubled() {
        let result = VaultExportCSV.serialise(document(
            items: [login(password: #"pa"ss"#)], folders: [folder()]
        ))

        XCTAssertTrue(result.csv.contains(#""pa""ss""#), "got: \(result.csv)")
    }

    /// The case that silently breaks a file: a newline inside a cell must be quoted, or the row splits
    /// and every subsequent row is misaligned.
    func testNotesWithNewlines_areQuotedAndSurviveAParse() throws {
        let notes = "line one\nline two"
        let result = VaultExportCSV.serialise(document(
            items: [login(notes: notes)], folders: [folder()]
        ))

        let rows = try parseCSV(result.csv)
        XCTAssertEqual(rows.count, 2, "a quoted newline must not create a third row")
        XCTAssertEqual(rows[1][4], notes, "the notes come back unchanged")
    }

    // MARK: - 1.5 / 1.6 the folder column

    func testFolderColumn_carriesTheNameNotTheId() {
        let result = VaultExportCSV.serialise(document(
            items: [login(folderId: "f-1")], folders: [folder(id: "f-1", name: "Work")]
        ))

        XCTAssertTrue(lines(result.csv)[1].hasPrefix("Work,"))
        XCTAssertFalse(result.csv.contains("f-1"), "the id must not leak into the file")
    }

    func testItemInNoFolder_hasAnEmptyFolderColumn() {
        let result = VaultExportCSV.serialise(document(items: [login(folderId: nil)]))

        XCTAssertTrue(lines(result.csv)[1].hasPrefix(","), "got: \(lines(result.csv)[1])")
    }

    /// A folder the document does not describe is empty too — not the literal "nil", which would be a
    /// folder named "nil" to every importer.
    func testUnknownFolderId_isEmptyRatherThanNil() {
        let result = VaultExportCSV.serialise(document(items: [login(folderId: "missing")]))

        XCTAssertTrue(lines(result.csv)[1].hasPrefix(","))
        XCTAssertFalse(result.csv.contains("nil"))
    }

    // MARK: - 1.7 custom fields

    func testCustomFields_useTheDocumentedNameColonValueForm() {
        let fields = [
            ExportCustomField(name: "PIN", value: "1234", type: 1, linkedId: nil),
            ExportCustomField(name: "Recovery", value: nil, type: 0, linkedId: nil)
        ]
        let result = VaultExportCSV.serialise(document(
            items: [login(fields: fields)], folders: [folder()]
        ))

        // A field with no value keeps its name: the field's existence is itself data, and a boolean
        // field is stored exactly this way.
        XCTAssertTrue(result.csv.contains("PIN:1234;Recovery:"), "got: \(result.csv)")
    }

    // MARK: - 1.9 omissions are counted

    func testNonLoginItems_areOmittedAndCounted() {
        let card = ExportItem(
            id: "c-2", organizationId: nil, folderId: nil, collectionIds: nil,
            type: 3, reprompt: 0, name: "Visa", notes: nil, favorite: false,
            fields: nil, login: nil, secureNote: nil, card: nil, identity: nil, sshKey: nil,
            passwordHistory: nil,
            creationDate: nil, revisionDate: nil, deletedDate: nil, archivedDate: nil
        )

        let result = VaultExportCSV.serialise(document(items: [login(), card]))

        XCTAssertEqual(result.omittedCount, 1)
        XCTAssertFalse(result.csv.contains("Visa"), "a card cannot be represented by these columns")
        XCTAssertEqual(lines(result.csv).count, 3, "header, one row, and the trailing newline")
    }

    // MARK: - 1.10 nothing of this type is refused

    func testVaultWithNoLogins_isRefusedByTheUseCase() async throws {
        let vault = MockVaultRepository()
        await vault.populate(
            items: [VaultItem(
                id: "1", name: "A Note", isFavorite: false, isDeleted: false,
                creationDate: .now, revisionDate: .now,
                content: .secureNote(SecureNoteContent(notes: "x", customFields: []))
            )],
            folders: [], organizations: [], collections: [], syncedAt: Date()
        )
        let sut = ExportVaultUseCaseImpl(vault: vault)

        await XCTAssertThrowsErrorAsync(try await sut.execute(format: .csv)) { error in
            XCTAssertEqual(error as? ExportVaultError, .nothingInThisFormat)
        }
    }

    // MARK: - 2.x the use case's format handling

    private func vaultWithOneLoginAndOneCard() async -> MockVaultRepository {
        let vault = MockVaultRepository()
        await vault.populate(
            items: [
                VaultItem(
                    id: "1", name: "Twitter", isFavorite: true, isDeleted: false,
                    creationDate: .now, revisionDate: .now,
                    content: .login(LoginContent(
                        username: "me@example.com", password: "password123",
                        uris: [LoginURI(uri: "twitter.com", matchType: nil)],
                        totp: nil, notes: nil, customFields: []
                    ))
                ),
                VaultItem(
                    id: "2", name: "Visa", isFavorite: false, isDeleted: false,
                    creationDate: .now, revisionDate: .now,
                    content: .card(CardContent(
                        cardholderName: "A Person", brand: "Visa", number: "4111",
                        expMonth: "04", expYear: "2030", code: "123",
                        notes: nil, customFields: []
                    ))
                )
            ],
            folders: [Folder(id: "f-1", name: "Social")],
            organizations: [], collections: [], syncedAt: Date()
        )
        return vault
    }

    func testExecute_csv_returnsCSVAndACsvFilename() async throws {
        let sut = ExportVaultUseCaseImpl(vault: await vaultWithOneLoginAndOneCard())

        let export = try await sut.execute(format: .csv)

        let text = try XCTUnwrap(String(data: export.data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("folder,favorite,type,name,notes"))
        XCTAssertTrue(export.suggestedFilename.hasSuffix(".csv"))
        XCTAssertEqual(export.itemCount, 1, "only the login is a row")
        XCTAssertEqual(export.omittedItemCount, 1, "the card is counted, not swallowed")
    }

    /// The regression guard for the format that already existed: adding a second format must not
    /// change the first one's bytes.
    func testExecute_json_isUnchangedAndOmitsNothing() async throws {
        let sut = ExportVaultUseCaseImpl(vault: await vaultWithOneLoginAndOneCard())

        let export = try await sut.execute(format: .json)

        XCTAssertTrue(export.suggestedFilename.hasSuffix(".json"))
        XCTAssertEqual(export.omittedItemCount, 0, "JSON carries every item type")
        XCTAssertEqual(export.itemCount, 2)
        let text = try XCTUnwrap(String(data: export.data, encoding: .utf8))
        XCTAssertTrue(text.contains(#""encrypted" : false"#), "got: \(text.prefix(120))")
    }

    func testFilename_extensionFollowsTheFormat() {
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(ExportVaultUseCaseImpl.filename(format: .json, now: epoch).hasSuffix(".json"))
        XCTAssertTrue(ExportVaultUseCaseImpl.filename(format: .csv,  now: epoch).hasSuffix(".csv"))
    }

    // MARK: - Helpers

    /// A minimal RFC 4180 reader, so the quoting tests assert that a real parser recovers the value
    /// rather than that the output contains certain characters.
    private func parseCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character?

        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let ch = next() {
            if inQuotes {
                if ch == "\"" {
                    if let peek = next() {
                        if peek == "\"" { cell.append("\"") } else { inQuotes = false; pending = peek }
                    } else { inQuotes = false }
                } else {
                    cell.append(ch)
                }
                continue
            }
            switch ch {
            case "\"": inQuotes = true
            case ",":  row.append(cell); cell = ""
            case "\n": row.append(cell); rows.append(row); row = []; cell = ""
            case "\r": break
            default:   cell.append(ch)
            }
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}
