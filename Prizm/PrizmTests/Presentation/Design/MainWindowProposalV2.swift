import AppKit
import SwiftUI
@testable import Prizm

// MARK: - Main window proposal, second pass
//
// Drawn against the *real* vault rather than the fixture: 86 items of which 84 are logins. That
// ratio breaks the first pass — a per-type colour tells you nothing when one type is 97% of the
// list, so the item list became a column of identical blue squares. This is the correction.

// MARK: - Sidebar icon treatment

/// How the sidebar's row icons are coloured.
///
/// Three options rather than one, because the proposal under review asks for "monochrome or a
/// lower-saturation palette" and the two read differently enough that it has to be looked at:
/// monochrome is calmer but the sidebar then stops helping you find a type, and the muted palette
/// keeps that help without the five crayons.
enum P2IconStyle {
    /// What shipped in the first pass: the full-saturation system colours.
    case saturated
    /// Same hues, pulled back so they sit beside grey folder icons without clashing.
    case muted
    /// Proposal §2 taken at its word: every row icon in the secondary colour.
    case monochrome
}

/// The low-saturation counterpart to `ItemType.tint`.
///
/// These are hand-picked rather than derived from the system colours because "less saturated" is not
/// one operation: desaturating the system purple goes grey, and grey-on-grey is the outcome being
/// avoided. Each of these keeps enough hue to still read as a colour while dropping far enough back
/// to stop competing with the row text.
enum P2MutedTint {
    static func of(_ type: ItemType) -> Color {
        switch type {
        case .login:      return Color(red: 0.44, green: 0.58, blue: 0.82)
        case .card:       return Color(red: 0.63, green: 0.50, blue: 0.76)
        case .identity:   return Color(red: 0.42, green: 0.68, blue: 0.68)
        case .secureNote: return Color(red: 0.83, green: 0.64, blue: 0.45)
        case .sshKey:     return Color(red: 0.48, green: 0.72, blue: 0.55)
        }
    }
}

private func sidebarIconColor(type: ItemType?, style: P2IconStyle) -> Color {
    switch style {
    case .saturated:  return type?.tint ?? .secondary
    case .muted:      return type.map(P2MutedTint.of) ?? .secondary
    case .monochrome: return .secondary
    }
}

// MARK: - Simulated favicon

/// A stand-in for a loaded site icon.
///
/// The harness has no network, so `FaviconView` always renders its fallback glyph here — which is
/// exactly what the user is seeing in the real app, and exactly the thing that has to change. The
/// monogram shows what the row looks like when the icon service works.
private struct Monogram: View {
    let letter: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color)
            .overlay(
                Text(letter)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: 22, height: 22)
    }
}

// MARK: - List

struct P2Row: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let letter: String
    let color: Color
    var hasTOTP = false
    var hasAttachment = false
    var isFavorite = false
    var isFolder = false
    /// `false` stands for the icon service not answering — which is every row in the app today, and
    /// the state the muted-palette proposal would be designed around.
    var hasIcon = true
}

private struct P2ListRow: View {
    let row: P2Row
    var isSelected = false

    var body: some View {
        HStack(spacing: 9) {
            if row.isFolder {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            } else if row.hasIcon {
                Monogram(letter: row.letter, color: row.color)
            } else {
                // The fallback that is currently the norm: no site identity at all, so every login
                // is the same glyph and the row's colour carries no information.
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        Image(systemName: "key")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    )
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // The two facts that make an item worth finding, shown without opening it. Neither is
            // about the item's type — which, at 84 logins out of 86, is the least informative thing
            // about any row in this list.
            if row.hasTOTP {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if row.hasAttachment {
                Image(systemName: "paperclip")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if row.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10)).foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.22) : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(width: 2.5)
            }
        }
        .contentShape(Rectangle())
    }
}

struct P2ItemList: View {
    let title: String
    let count: Int
    let rows: [P2Row]
    let selectedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The pane header the first pass had not: which category this is, and how much of it.
            // Without it the list is a column of names with no stated scope, and the only cue is a
            // highlighted row two panes away.
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        P2ListRow(row: row, isSelected: row.id == selectedId)
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Detail: the vault summary

private struct Stat: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07)))
    }
}

struct P2DetailSummary: View {
    let recent: [P2Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 3) {
                Text("保管库概览").font(.system(size: 20, weight: .semibold))
                Text("还没有选择项目。从左侧列表挑一个，或者用下面这些数字判断哪里该整一整。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Stat(value: "86", label: "项目")
                Stat(value: "12", label: "开启两步验证", tint: .green)
                Stat(value: "7", label: "弱密码", tint: .orange)
                Stat(value: "3", label: "超过一年未更新", tint: .red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近更新").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(recent) { row in
                        P2ListRow(row: row)
                        if row.id != recent.last?.id { Divider().padding(.leading, 42) }
                    }
                }
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07)))
            }

            Button {
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 11))
                    Text("查看保管库健康报告").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Sidebar

struct P2Sidebar: View {
    let selected: String
    var iconStyle: P2IconStyle = .muted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).imageScale(.small)
                Text("搜索保险库").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text("⌘F").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    row("全部项目", "square.grid.2x2", .accentColor, 86, sel: "全部项目")
                    row("收藏夹", "star", .yellow, 2, sel: "收藏夹")
                    // A chevron, because this row opens a sheet rather than choosing a category.
                    // Without one it is indistinguishable from the two above it, and clicking it
                    // leaves the selection looking like it moved when it did not.
                    row("动态验证码", "lock.shield", .secondary, nil, sel: selected, chevron: true)

                    section("类型")
                    row("登录", "key", sidebarIconColor(type: .login, style: iconStyle), 84)
                    row("信用卡", "creditcard", sidebarIconColor(type: .card, style: iconStyle), 2)
                    row("身份", "person.crop.rectangle", sidebarIconColor(type: .identity, style: iconStyle), 0)
                    row("安全笔记", "note.text", sidebarIconColor(type: .secureNote, style: iconStyle), 1)
                    row("SSH 密钥", "terminal", sidebarIconColor(type: .sshKey, style: iconStyle), 1)

                    sectionHeader("文件夹", plus: true)
                    row("AI 密钥", "folder", .secondary, 1)
                    row("New Folder", "folder", .secondary, 0)

                    Spacer(minLength: 10)
                    Divider().padding(.vertical, 6)
                    row("废纸篓", "trash", .secondary, 0)
                }
            }

            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("刚刚同步").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func section(_ t: String) -> some View { sectionHeader(t, plus: false) }

    private func sectionHeader(_ title: String, plus: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            if plus { Image(systemName: "folder.badge.plus").font(.system(size: 12)).foregroundStyle(.primary) }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 3)
    }

    private func row(_ title: String, _ icon: String, _ tint: Color, _ count: Int?,
                     sel: String? = nil, chevron: Bool = false) -> some View {
        let isSel = sel == title
        return HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12))
                // Hierarchical rather than monochrome: a folder glyph is one flat shape, so the mode
                // only shows up on the multi-layer symbols (creditcard, terminal), where it softens
                // them into the same visual weight as the grey folders below.
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title).font(.system(size: 13))
                .foregroundStyle(isSel ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSel ? Color.white.opacity(0.8) : .secondary)
            } else if let count, count > 0 {
                Text("\(count)").font(.system(size: 11))
                    .foregroundStyle(isSel ? Color.white.opacity(0.85) : .secondary)
            }
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 5)
        .background(isSel ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Toolbar strip

struct P2Toolbar: View {
    var body: some View {
        HStack(spacing: 14) {
            // Proposal §3: the three controls stop being filled discs. At rest they are bare glyphs
            // and text, and only take a faint background when hovered — which is also what macOS's
            // own toolbars do, so this is less a restyle than a stop fighting the default.
            //
            // Sort carries its order as a word rather than an arrow glyph, because "↑↓" alone does not
            // say which of the six orders is active, and the active one is the only thing worth
            // knowing without opening the menu.
            ghost {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 11))
                    Text("名称").font(.system(size: 12))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }

            ghost {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
            }

            Spacer()

            // The one control that keeps a fill: it is the only thing here that creates something.
            ghost {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("新建").font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func ghost<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Button { } label: {
            content()
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window

struct P2MainWindow: View {
    let rows: [P2Row]
    let selectedId: String?
    let recent: [P2Row]
    var iconStyle: P2IconStyle = .muted

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 96, height: 44)
                P2Toolbar()
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                P2Sidebar(selected: "全部项目", iconStyle: iconStyle).frame(width: 218)
                Divider()
                P2ItemList(title: "全部项目", count: 86, rows: rows, selectedId: selectedId)
                    .frame(width: 300)
                Divider()
                P2DetailSummary(recent: recent)
            }
        }
    }
}
