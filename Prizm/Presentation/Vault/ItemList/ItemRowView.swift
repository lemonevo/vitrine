import SwiftUI

// MARK: - ItemRowView

/// A single row in the item list, showing a type-tinted icon chip, name, subtitle, and favorite star.
///
/// FR-021: type-specific subtitle
///   - Login:       username
///   - Card:        `*` + last 4 digits of card number
///   - Identity:    first + last name; falls back to email; then blank (FR-046)
///   - Secure Note: first 30 chars of note body truncated with `…`
///   - SSH Key:     key fingerprint, or "[No fingerprint]" if absent (FR-047)
///
/// FR-022: favorite star indicator (display-only)
/// FR-009: favicon with SF Symbol fallback
///
/// **The chip keeps the favicon.** It would have been simpler to draw the type symbol in every row,
/// and it would have deleted a feature: a row that stops showing the site's own icon is a regression
/// wearing the redesign's clothes. The favicon sits on the tinted square and the tint shows around it;
/// when there is no favicon the type symbol is drawn in that same tint, so the chip reads as the type
/// either way.
struct ItemRowView: View {

    let item:          VaultItem
    let faviconLoader: FaviconLoader
    var searchQuery:   String? = nil
    /// Org name shown as a small badge when the item belongs to an organization (FR task 6.1).
    var orgName:       String? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Spacing.listRowSpacing) {
            typeChip

            VStack(alignment: .leading, spacing: 1) {
                Text(styledName)
                    .font(Typography.listTitle)
                    .lineLimit(1)
                HStack(spacing: Spacing.listRowBadgeSpacing) {
                    if let subtitle = subtitle(for: item) {
                        Text(styledSubtitle(subtitle))
                            .font(Typography.listSubtitle)
                            .foregroundStyle(Foreground.muted)
                            .lineLimit(1)
                    }
                    if let org = orgName {
                        Text(org)
                            .font(Typography.orgBadge)
                            .foregroundStyle(itemType(for: item).tint)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.badgeHorizontal)
                            .padding(.vertical, Spacing.badgeVertical)
                            .background(
                                itemType(for: item).tint.opacity(Opacity.typeChip(contrast)),
                                in: RoundedRectangle(cornerRadius: Spacing.badgeCornerRadius)
                            )
                    }
                }
            }

            Spacer(minLength: 4)

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Foreground.favorite)
                    .accessibilityLabel(L("Favorited"))
            }
        }
        .padding(.vertical, Spacing.listRowVertical)
    }

    /// The tinted square holding the favicon, or the type symbol when there is no favicon.
    private var typeChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.listChipCornerRadius)
                .fill(itemType(for: item).tint.opacity(Opacity.typeChip(contrast)))
            FaviconView(
                domain:   primaryDomain(for: item),
                itemType: itemType(for: item),
                loader:   faviconLoader,
                size:     Spacing.listChipIcon,
                tint:     itemType(for: item).tint
            )
        }
        .frame(width: Spacing.listChip, height: Spacing.listChip)
    }

    // MARK: - Highlighted text helpers

    private var styledName: AttributedString {
        guard let q = searchQuery, !q.isEmpty else { return AttributedString(item.name) }
        return Self.highlightedText(item.name, query: q)
    }

    private func styledSubtitle(_ text: String) -> AttributedString {
        guard let q = searchQuery, !q.isEmpty else { return AttributedString(text) }
        return Self.highlightedText(text, query: q)
    }

    /// Returns an `AttributedString` with the first case-insensitive match of `query` rendered in bold.
    static func highlightedText(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty,
              let range = text.range(of: query, options: .caseInsensitive) else {
            return result
        }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        let start = result.index(result.startIndex, offsetByCharacters: lower)
        let end   = result.index(result.startIndex, offsetByCharacters: upper)
        result[start..<end].inlinePresentationIntent = .stronglyEmphasized
        return result
    }

    // MARK: - Subtitle (FR-021, FR-046, FR-047)

    private func subtitle(for item: VaultItem) -> String? {
        switch item.content {
        case .login(let l):
            return l.username

        case .card(let c):
            if let number = c.number, number.count >= 4 {
                return "*" + String(number.suffix(4))
            }
            return nil

        case .identity(let i):
            let firstName = i.firstName ?? ""
            let lastName  = i.lastName  ?? ""
            let fullName  = [firstName, lastName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !fullName.isEmpty { return fullName }
            if let email = i.email, !email.isEmpty { return email }
            return nil

        case .secureNote(let n):
            guard let notes = n.notes, !notes.isEmpty else { return nil }
            if notes.count <= 30 { return notes }
            return String(notes.prefix(30)) + "…"

        case .sshKey(let k):
            if let fp = k.keyFingerprint, !fp.isEmpty { return fp }
            return L("[No fingerprint]")
        }
    }

    // MARK: - Favicon helpers

    private func primaryDomain(for item: VaultItem) -> String? {
        guard case .login(let l) = item.content,
              let first = l.uris.first else { return nil }
        return URL(string: first.uri)?.host
    }

    private func itemType(for item: VaultItem) -> ItemType {
        switch item.content {
        case .login:      return .login
        case .card:       return .card
        case .identity:   return .identity
        case .secureNote: return .secureNote
        case .sshKey:     return .sshKey
        }
    }
}
