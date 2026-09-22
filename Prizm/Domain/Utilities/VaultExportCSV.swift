import Foundation

// MARK: - VaultExportCSV

/// Renders a `VaultExportDocument` as Bitwarden's CSV.
///
/// Written against the document rather than against the vault entities, so JSON and CSV agree about
/// what an export contains by construction: there is one mapping from the vault to an export, and
/// this only decides how to spell it.
///
/// **The column encodings are from the official import-conditions page**, which specifies the file
/// rather than describing it. Where it gave an example row it is reproduced in the tests verbatim:
///
/// ```
/// Social,1,login,Twitter,,,0,twitter.com,me@example.com,password123,
/// ```
///
/// A CSV that the official client refuses to import is worse than no CSV, so nothing here is guessed:
/// where the documentation does not say, this omits rather than invents, and counts what it omitted.
nonisolated enum VaultExportCSV {

    /// The documented column list, in the documented order.
    static let columns = [
        "folder", "favorite", "type", "name", "notes", "fields", "reprompt",
        "login_uri", "login_username", "login_password", "login_totp"
    ]

    /// The `type` token for a login row. The only one the documentation pins; see `serialise`.
    private static let loginTypeToken = "login"

    /// The server's `CipherType` for a login, matching `CipherMapper.mapContent`.
    private static let loginCipherType = 1

    struct Result: Equatable {
        let csv: String
        /// Items the format cannot carry. Reported rather than swallowed — a user who exports 400 items
        /// and gets 300 rows must not have to count to find out.
        let omittedCount: Int
    }

    /// Renders `document` as CSV.
    ///
    /// **Logins only.** The columns are `login_*`: this schema has nowhere to put a card number, an
    /// identity's fields or an SSH key, and the official documentation says the unencrypted formats
    /// exclude those types. Secure notes are omitted as well, though `notes` could arguably hold one:
    /// the `type` token for a non-login row is not pinned by the documentation, and a guessed token
    /// produces a file that fails on import — which is the one outcome worth avoiding here.
    ///
    /// - Returns: the CSV text and how many items were left out.
    static func serialise(_ document: VaultExportDocument) -> Result {
        let folderNames = Dictionary(
            document.folders.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        var lines = [columns.joined(separator: ",")]
        var omitted = 0

        for item in document.items {
            guard item.type == loginCipherType, let login = item.login else {
                omitted += 1
                continue
            }
            lines.append(row(item: item, login: login, folderNames: folderNames).joined(separator: ","))
        }

        // A trailing newline: every line-oriented tool expects one, and a file without it makes `diff`
        // report a spurious difference on the last line.
        return Result(csv: lines.joined(separator: "\n") + "\n", omittedCount: omitted)
    }

    // MARK: - Private

    private static func row(
        item: ExportItem,
        login: ExportLogin,
        folderNames: [String: String]
    ) -> [String] {
        // `folderId` is an id in the document and a **name** in the CSV — the documented encoding, and
        // what makes the file portable to a manager that has never seen these ids. An item in no folder,
        // or in a folder the document somehow lacks, gets an empty cell rather than the literal "nil".
        let folder = item.folderId.flatMap { folderNames[$0] } ?? ""

        return [
            escape(folder),
            escape(item.favorite ? "1" : "0"),
            escape(loginTypeToken),
            escape(item.name),
            escape(item.notes ?? ""),
            escape(fieldsValue(item.fields ?? [])),
            escape(String(item.reprompt)),
            // The column is singular. The first URI is written and the rest are dropped — the format
            // has nowhere for them, and inventing a separator would produce a value no importer
            // splits the way we meant.
            escape(login.uris?.first?.uri ?? ""),
            escape(login.username ?? ""),
            escape(login.password ?? ""),
            escape(login.totp ?? "")
        ]
    }

    /// `name:value;name:value`, the documented encoding.
    ///
    /// A field with no value keeps its name and an empty value (`name:`) rather than being dropped:
    /// the existence of the field is itself data, and a boolean field is stored exactly that way.
    private static func fieldsValue(_ fields: [ExportCustomField]) -> String {
        fields.map { "\($0.name):\($0.value ?? "")" }.joined(separator: ";")
    }

    /// RFC 4180: quote when the value contains a comma, a quote, or a line break; double the quotes.
    ///
    /// Not theoretical — item names contain commas, notes contain newlines, and a password can contain
    /// both. Unquoted, those produce a row that parses into the wrong number of columns, silently, and
    /// differently depending on which reader is used.
    private static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
