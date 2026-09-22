import Foundation

// MARK: - ItemSortOrder

/// The order the vault item list is displayed in.
///
/// **Why this is a presentation concern, not a repository one.** `VaultRepositoryImpl` pre-computes
/// one alphabetically-sorted list per `SidebarSelection` at `populate()` time and serves it in O(1)
/// (see `openspec/specs/vault-actor-isolation`). Making the sort order an input to the repository
/// would mean rebuilding those indexes whenever the user touched the sort menu, and would put a
/// display preference inside the actor that exists to hold vault data. The order is therefore
/// applied to the already-filtered result in `VaultBrowserViewModel`.
nonisolated enum ItemSortOrder: String, CaseIterable, Identifiable, Sendable {

    case nameAscending
    case nameDescending
    case modifiedNewestFirst
    case modifiedOldestFirst
    case createdNewestFirst
    case createdOldestFirst

    var id: String { rawValue }

    /// Label shown in the sort menu. Resolved through `L(…)` at call time so it follows the
    /// interface language.
    var displayName: String {
        switch self {
        case .nameAscending:       return L("Name (A–Z)")
        case .nameDescending:      return L("Name (Z–A)")
        case .modifiedNewestFirst: return L("Last Modified (Newest First)")
        case .modifiedOldestFirst: return L("Last Modified (Oldest First)")
        case .createdNewestFirst:  return L("Date Created (Newest First)")
        case .createdOldestFirst:  return L("Date Created (Oldest First)")
        }
    }

    /// The word on the toolbar's sort control.
    ///
    /// `displayName` is what the menu needs ("Last Modified (Newest First)"); in the titlebar it would
    /// be the widest thing on the bar and it changes width every time the user picks another order,
    /// which shuffles the controls beside it. This is the category, stable in width across the two orders
    /// inside it.
    var toolbarLabel: String {
        switch self {
        case .nameAscending, .nameDescending:             return L("Name")
        case .modifiedNewestFirst, .modifiedOldestFirst:  return L("Modified")
        case .createdNewestFirst, .createdOldestFirst:    return L("Created")
        }
    }

    /// Orders `items` according to this order.
    ///
    /// A pass-through for `.nameAscending` was tried here and is wrong. `VaultRepositoryImpl` does hand
    /// over buckets already in that order, but this is a public function on a value type and cannot know
    /// its caller's state — `ItemSortOrderTests` and the view model's own test both feed it an unsorted
    /// array, and both went red. The per-keystroke cost is real; it is also a sort of a few hundred
    /// short strings, which is not what makes this app feel slow.
    func sort(_ items: [VaultItem]) -> [VaultItem] {
        items.sorted(by: areInIncreasingOrder)
    }

    /// The comparator behind `sort(_:)`.
    ///
    /// Every order falls back to case-insensitive name order when the primary keys tie. Without
    /// that, two items sharing a timestamp would be free to swap places between refreshes, because
    /// Swift's `sorted(by:)` is not a stable sort.
    ///
    /// Note the name orders deliberately return `false` for equal names rather than falling back
    /// to something else: `sorted(by:)` requires a strict weak ordering, and `a < a` must be false.
    private func areInIncreasingOrder(_ lhs: VaultItem, _ rhs: VaultItem) -> Bool {
        switch self {
        case .nameAscending:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending

        case .nameDescending:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending

        case .modifiedNewestFirst:
            return byDate(lhs.revisionDate, rhs.revisionDate, newestFirst: true, lhs, rhs)

        case .modifiedOldestFirst:
            return byDate(lhs.revisionDate, rhs.revisionDate, newestFirst: false, lhs, rhs)

        case .createdNewestFirst:
            return byDate(lhs.creationDate, rhs.creationDate, newestFirst: true, lhs, rhs)

        case .createdOldestFirst:
            return byDate(lhs.creationDate, rhs.creationDate, newestFirst: false, lhs, rhs)
        }
    }

    private func byDate(_ left: Date, _ right: Date, newestFirst: Bool,
                        _ lhs: VaultItem, _ rhs: VaultItem) -> Bool {
        if left != right { return newestFirst ? left > right : left < right }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - ItemSortPreference

/// Persistence for the chosen `ItemSortOrder`.
///
/// Follows the shape of `WebsiteIconsPreference`: an injectable `UserDefaults` so tests never
/// touch the real domain.
nonisolated enum ItemSortPreference {

    /// `UserDefaults` key. Read by `VaultBrowserViewModel`, written when the sort menu changes.
    static let key = "itemSortOrder"

    /// The stored order, or `.nameAscending` when the key has never been written or holds a value
    /// this build does not recognise (e.g. written by a newer version).
    static func load(from defaults: UserDefaults = .standard) -> ItemSortOrder {
        guard let raw = defaults.string(forKey: key),
              let order = ItemSortOrder(rawValue: raw) else { return .nameAscending }
        return order
    }

    static func save(_ order: ItemSortOrder, to defaults: UserDefaults = .standard) {
        defaults.set(order.rawValue, forKey: key)
    }
}
