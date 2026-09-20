import Foundation

/// Permanently deletes every item in Trash.
///
/// **Why this returns a result instead of throwing.** The server exposes only per-item permanent
/// deletion, so emptying Trash is a sequence of independent requests. Throwing on the first failure
/// would stop halfway and leave the user unable to tell how much was actually removed. Returning
/// counts lets the caller report "9 deleted, 3 failed" and refresh the list to whatever is really
/// left — the honest outcome for an operation made of N independent requests.
protocol EmptyTrashUseCase {
    func execute() async -> EmptyTrashResult
}

/// Outcome of emptying Trash.
nonisolated struct EmptyTrashResult: Equatable, Sendable {

    /// How many items were permanently deleted.
    let deletedCount: Int

    /// How many delete requests failed. These items are still in Trash.
    let failedCount: Int

    /// The last error message seen, for surfacing to the user. Nil when nothing failed.
    let errorMessage: String?

    static let none = EmptyTrashResult(deletedCount: 0, failedCount: 0, errorMessage: nil)

    /// Whether anything went wrong.
    var hadFailures: Bool { failedCount > 0 }

    /// Whether the operation had nothing to do.
    var isEmpty: Bool { deletedCount == 0 && failedCount == 0 }
}
