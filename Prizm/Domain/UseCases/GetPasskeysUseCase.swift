import Foundation

// MARK: - GetPasskeysUseCase

/// Produces the passkeys stored on one item, for display only.
///
/// **Why this exists when `VaultRepository.passkeys(for:)` already does the work.** So the detail
/// view depends on a domain protocol rather than on a repository — the same reason as
/// `GetPasswordHistoryUseCase`, and it matters more here: a view model holding `any VaultRepository`
/// could reach past this layer for every other operation on the vault.
///
/// **Nothing is decrypted until this is called, and nothing is held afterwards.** The credential
/// fields arrive as EncStrings and stay that way in the domain model until the section is shown.
///
/// **The result cannot be used to sign in.** `PasskeyCredential` carries no key material — see that
/// type. This is not a limitation of the use case being thin; it is the shape of the type it
/// returns, so no caller can accidentally have more than it was given.
protocol GetPasskeysUseCase: Sendable {
    func execute(itemId: String) async throws -> [PasskeyCredential]
}
