import Combine
import Foundation
import SwiftUI

// MARK: - PasskeysViewModel

/// Holds one item's passkeys for as long as the user is looking at them.
///
/// Shaped like `PasswordHistoryViewModel`, for the same reason: the values come from decrypting
/// vault contents, so they are derived when the item is shown and dropped with the view model when
/// the selection moves on. Per item rather than shared — a shared instance would keep one item's
/// credentials alive while the user reads a different item.
///
/// `idle` is distinct from `loading` so the section can tell "not asked yet" from "asked and came
/// back empty", which is what keeps an unread list from rendering as "no passkeys".
@MainActor
final class PasskeysViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded([PasskeyCredential])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let itemId: String

    private let useCase: any GetPasskeysUseCase

    init(itemId: String, useCase: any GetPasskeysUseCase) {
        self.itemId  = itemId
        self.useCase = useCase
    }

    /// Number of credentials, or nil before the first load. Drives the count badge, which must not
    /// read "0" for a section that has simply never been read.
    var credentialCount: Int? {
        if case .loaded(let credentials) = state { return credentials.count }
        return nil
    }

    func load() async {
        // Not guarded on `.idle` the way the history view model is: `clear()` returns it there, so
        // collapsing and re-opening re-reads rather than showing a stale list.
        state = .loading
        do {
            state = .loaded(try await useCase.execute(itemId: itemId))
        } catch {
            // Surfaced rather than swallowed into an empty list: an empty list reads as "this item
            // has no passkeys", which is a different claim from "they could not be read".
            state = .failed(L("Could not read the passkeys: %@", error.localizedDescription))
        }
    }

    /// Drops what was read, returning to `idle`. Called when the section collapses.
    ///
    /// Without it the decrypted values would outlive the section that asked for them, and the
    /// "decrypted on demand, never cached" rule would hold only until the user closed the disclosure
    /// once.
    func clear() {
        state = .idle
    }
}
