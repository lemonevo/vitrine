import Foundation

// MARK: - GetPasswordHistoryUseCase

/// Produces the decrypted previous passwords of one item.
///
/// **Why this exists when `VaultRepository.passwordHistory(for:)` already does the work.** So the
/// detail view depends on a domain protocol rather than on a repository. The alternative is a view
/// model that takes `any VaultRepository`, which would let a presentation type reach past the use
/// case layer for every other operation on that repository too.
///
/// **Nothing is decrypted until this is called, and nothing is held afterwards.** The section is
/// collapsed by default and the view model drops the entries when it closes, so the plaintext exists
/// only while the user is looking at it (design D10).
///
/// **Order is the server's, and is deliberately not re-applied here.** Vaultwarden prepends each
/// replaced password, so the array arrives newest-first. Re-sorting by `lastUsedDate` would look
/// more deliberate and be worse: an entry with no parseable date has no position, and putting those
/// at one end would silently misrepresent entries the server had already ordered correctly.
protocol GetPasswordHistoryUseCase: Sendable {
    func execute(itemId: String) async throws -> [PasswordHistoryEntry]
}
