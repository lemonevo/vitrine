import Combine
import Foundation
import os.log

// MARK: - VerificationCodeRow

/// One item's code in the list.
///
/// The `gate` is carried per row rather than looked up at render time, for the reason
/// `RevealGateBinding`'s own comment gives: a dropped `isGated` is silent — the row simply reveals —
/// and a list is a lot of rows for that to go wrong in.
struct VerificationCodeRow: Identifiable {
    let id: String
    let name: String
    let username: String?

    /// Whether this item's secrets require the master password, and how to ask for it.
    let gate: RevealGateBinding

    /// Derives and refreshes this row's code. Owned per row, so an item whose code runs on a different
    /// period is unaffected by its neighbours.
    let code: TOTPCodeViewModel

    /// The row's copy control, absent when the item has no code to copy.
    ///
    /// Goes through `gate.copyGated` when the item is gated — see `VerificationCodesViewModel.copy`.
    let copy: ((VerificationCodeRow) -> Void)?
}

// MARK: - VerificationCodesViewModel

/// Every TOTP code in the vault, in one list.
///
/// **The security question this type has to answer.** A list of every code is exactly what an item's
/// re-prompt protection exists to withhold. Built naively it would be a bypass: the gate would still
/// ask for a password on the item while the list handed the same code over without it.
///
/// So it does not get its own rule. The gate is the same `RevealGateBinding` the detail view uses, and
/// the copy route is `copyGated` — the closure `RevealGateBinding.gated` makes *required* precisely so
/// that a gated row cannot fall back to an ordinary copy.
///
/// **And the stored secret is never exposed.** The row shows a derived code; `TOTPCodeViewModel`'s
/// `copyValue` is the code, never the seed. A credential that generates codes forever does not belong on
/// a screen that lists values to copy, and a list is a larger surface for getting that wrong than a
/// single detail pane.
@MainActor
final class VerificationCodesViewModel: ObservableObject {

    /// The rows, in vault order.
    @Published private(set) var rows: [VerificationCodeRow] = []

    private let vault: any VaultRepository
    private let generator: any TOTPGenerator
    private let gateFor: (VaultItem) -> RevealGateBinding
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.prizm", category: "VerificationCodes")

    init(vault: any VaultRepository,
         generator: any TOTPGenerator,
         gateFor: @escaping (VaultItem) -> RevealGateBinding,
         now: @escaping () -> Date = Date.init) {
        self.vault    = vault
        self.generator = generator
        self.gateFor  = gateFor
        self.now      = now
    }

    // MARK: - Lifecycle

    /// Builds the rows and starts them deriving. Called when the sheet appears.
    func start() async {
        await rebuild()
        rows.forEach { $0.code.start() }
    }

    /// Stops every row's timer. Called when the sheet closes — one timer per row must not outlive the
    /// screen it belongs to.
    func stop() {
        rows.forEach { $0.code.stop() }
        rows = []
    }

    // MARK: - Copy

    /// Copies a row's code.
    ///
    /// Routed through the row's own copy control, which for a gated item is `copyGated`. Deliberately
    /// not a second path: a convenience that read `row.code.copyValue` directly would be the gate
    /// walk-around that `RevealGateBinding` is shaped to prevent.
    func copy(_ row: VerificationCodeRow) {
        row.copy?(row)
    }

    // MARK: - Private

    private func rebuild() async {
        let items: [VaultItem]
        do {
            items = try await vault.allItems()
        } catch {
            logger.error("Could not read the vault for verification codes: \(error.localizedDescription, privacy: .public)")
            rows = []
            return
        }

        rows = items.compactMap { makeRow(for: $0) }
        logger.info("Verification codes: \(self.rows.count, privacy: .public) row(s)")
    }

    /// The row for an item, or `nil` when the item has no code to show.
    ///
    /// Four filters, and each excludes for its own reason: a deleted item is not in the vault; only a
    /// login carries a TOTP secret; an item with no secret has no code; and an item whose name is empty
    /// would be an unidentifiable row in a list the user scans by name.
    private func makeRow(for item: VaultItem) -> VerificationCodeRow? {
        guard !item.isDeleted else { return nil }
        guard case .login(let login) = item.content else { return nil }
        guard let secret = login.totp, !secret.isEmpty else { return nil }

        let gate = gateFor(item)
        let codeVM = TOTPCodeViewModel(
            itemId:    item.id,
            secret:    secret,
            generator: generator,
            now:       now
        )

        return VerificationCodeRow(
            id:       item.id,
            name:     item.name,
            username: login.username,
            gate:     gate,
            code:     codeVM,
            copy:     { row in
                guard let value = row.code.copyValue else { return }
                // A gated row must not be copyable without the password. `copyGated` is present
                // whenever `isGated`, which is what makes this branch total.
                if let copyGated = row.gate.copyGated {
                    copyGated(value)
                }
            }
        )
    }
}
