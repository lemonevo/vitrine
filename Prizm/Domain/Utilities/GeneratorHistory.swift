import Combine
import Foundation

// MARK: - GeneratorHistoryEntry

/// One value the user generated and then used, with the time it was generated.
///
/// The identifier exists so the list can be diffed by SwiftUI without relying on the value: two
/// generations can legitimately produce the same string, and a value-keyed list would collapse them
/// into one row.
nonisolated struct GeneratorHistoryEntry: Identifiable, Equatable, Sendable {

    let id: UUID
    let value: String
    let generatedAt: Date

    init(value: String, generatedAt: Date = Date(), id: UUID = UUID()) {
        self.id          = id
        self.value       = value
        self.generatedAt = generatedAt
    }
}

// MARK: - GeneratorHistory

/// The values generated in this session and actually used, most recent first.
///
/// **Memory only, on purpose.** A generated password that was never saved is still a credential —
/// very often it is about to become someone's actual password. Writing this list to disk would
/// create a plaintext secret store the user never asked for and cannot see the contents of
/// (design D9). Nothing here is `Codable`; quitting Prizm loses the list, which is the correct
/// behaviour and is stated in the section footer rather than left for the user to discover.
///
/// **Bounded.** At most `capacity` entries are kept; appending past that drops the oldest. The
/// generator is a convenience, not a clipboard manager, and an unbounded list would grow for as
/// long as the vault stayed unlocked.
///
/// **Only what was used.** Entries are appended when the user copies or accepts a value, never on
/// every regeneration — a history of values the user never looked at is noise.
///
/// Held by `AppContainer` so the vault lock and sign-out paths can clear it alongside the key
/// caches; a value generated before a lock must not survive it.
@MainActor
final class GeneratorHistory: ObservableObject {

    /// How many values are kept. Matches Bitwarden's generator history.
    static let capacity = 20

    /// The recorded values, most recent first.
    @Published private(set) var entries: [GeneratorHistoryEntry] = []

    /// Records a value, dropping the oldest entry once `capacity` is reached.
    ///
    /// - Parameters:
    ///   - value: the generated value. Empty strings are ignored: an empty value is what a failed
    ///     generation leaves behind, and there is nothing for the user to copy back from it.
    ///   - date: when the value was generated. Injectable so a test can pin the timestamp instead
    ///     of racing the clock.
    func append(_ value: String, at date: Date = Date()) {
        guard !value.isEmpty else { return }

        entries.insert(GeneratorHistoryEntry(value: value, generatedAt: date), at: 0)

        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    /// Drops every entry.
    ///
    /// Called from `RootViewModel.lockVault()` and `signOut()` — the same two paths that clear the
    /// vault store and the key caches — so generated values cannot outlive the session that
    /// produced them.
    func clear() {
        entries.removeAll()
    }
}
