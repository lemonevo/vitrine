import Foundation

// MARK: - VaultBackupSheet

/// Which backup surface, if any, the vault browser is presenting.
///
/// **Why this is one enum rather than four booleans.** The states are mutually exclusive and they
/// hand off to each other in a fixed order — consent, then done; picker, then progress, then
/// report. Four independent flags can express sixteen states, twelve of which are nonsense, and a
/// bug that sets two of them is a sheet fighting another sheet. One value cannot do that.
///
/// **Why the view presents it with `.sheet(isPresented:)` and switches inside, rather than with
/// `.sheet(item:)`.** The two transitions that matter — consent → done, and progress → report —
/// change the payload but not the fact that *a* sheet is up. `.sheet(item:)` keys on the item's
/// identity, so it would tear the sheet down and rebuild it for each transition, and it writes
/// `nil` back through the binding as it does. `.sheet(isPresented:)` keeps one sheet alive and
/// lets the content follow the value, which is what actually happens here.
nonisolated enum VaultBackupSheet: Equatable {

    /// The mandatory consent shown before anything is written (design D2).
    case exportConsent

    /// Carried into the consent sheet so the format can be chosen before anything is written.

    /// Where the file went, and what is in it.
    case exportDone(url: URL, itemCount: Int, organisationItemCount: Int, omittedItemCount: Int, unreadableItemCount: Int)

    /// An import in flight. `total` is 0 until the file has been read and counted.
    case importing(done: Int, total: Int)

    /// What the import actually did.
    case importReport(ImportSummary)

    /// Whether dismissing the sheet should stop an in-flight import.
    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }
}
