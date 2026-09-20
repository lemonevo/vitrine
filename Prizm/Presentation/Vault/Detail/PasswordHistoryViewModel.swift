import Combine
import Foundation
import SwiftUI

// MARK: - PasswordHistoryViewModel

/// Holds one item's previous passwords for as long as the user is looking at them.
///
/// **The plaintext is dropped when the section collapses** (`clear()`), and re-derived on every
/// expand. That is design D10: a previous password is frequently the current password of the account
/// next door, so it should exist in memory only while it is on screen — the same "decrypt on demand"
/// contract `itemDetail(id:)` already has.
///
/// `idle` is distinct from `loading` so the section can tell "not asked yet" from "asked and came
/// back empty". Collapsing returns it to `idle`, which is what makes the next expand re-read rather
/// than showing a cached list.
@MainActor
final class PasswordHistoryViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded([PasswordHistoryEntry])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let itemId: String

    private let useCase: any GetPasswordHistoryUseCase

    init(itemId: String, useCase: any GetPasswordHistoryUseCase) {
        self.itemId  = itemId
        self.useCase = useCase
    }

    /// Number of entries, or nil before the first load. Drives the count badge, which must not read
    /// "0" while the section has simply never been opened.
    var entryCount: Int? {
        if case .loaded(let entries) = state { return entries.count }
        return nil
    }

    func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            state = .loaded(try await useCase.execute(itemId: itemId))
        } catch {
            // Surfaced rather than swallowed into an empty list: an empty list reads as "this item
            // has no previous passwords", which is a different claim from "they could not be read".
            state = .failed(L("Could not read the password history: %@", error.localizedDescription))
        }
    }

    /// Discards the decrypted values. Called when the section collapses.
    func clear() {
        state = .idle
    }
}
