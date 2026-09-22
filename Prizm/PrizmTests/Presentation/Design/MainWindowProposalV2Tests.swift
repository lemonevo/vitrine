import AppKit
import SwiftUI
import XCTest
@testable import Prizm

/// Renders the second-pass main window proposal to `/tmp/prizm-design/`.
@MainActor
final class MainWindowProposalV2Tests: XCTestCase {

    private let size = CGSize(width: 1400, height: 900)

    private func snapshot(_ name: String, size explicitSize: CGSize? = nil,
                          appearance: NSAppearance.Name,
                          @ViewBuilder _ view: () -> some View) throws {
        let size = explicitSize ?? self.size
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        // The background is supplied here rather than left to the window: `NSWindow.backgroundColor`
        // resolves against the appearance in force at creation, so a window built in a light process
        // keeps a light backing after its appearance is switched.
        window.contentView = NSHostingView(
            rootView: AnyView(
                view().frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))

        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            XCTFail("could not prepare \(name)"); return
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("could not encode \(name)"); return
        }
        let url = URL(fileURLWithPath: "/tmp/prizm-design/\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
        window.orderOut(nil)
    }

    /// A list shaped like the real vault: logins, logins, logins, and two things that are not.
    private var rows: [P2Row] {
        [
            P2Row(id: "1", name: "accounts.google.com", subtitle: "alice@example.com",
                  letter: "G", color: .red, hasTOTP: true, isFavorite: true),
            P2Row(id: "2", name: "ChatGPT", subtitle: "bob@example.com",
                  letter: "C", color: .green, hasTOTP: true, isFavorite: true),
            P2Row(id: "3", name: "OpenAI API Key", subtitle: "sk-proj-…",
                  letter: "O", color: .teal, hasAttachment: true),
            P2Row(id: "4", name: "GitHub", subtitle: "alice",
                  letter: "G", color: .gray, hasTOTP: true),
            P2Row(id: "5", name: "Cloudflare", subtitle: "alice@example.com",
                  letter: "C", color: .orange, hasTOTP: true),
            P2Row(id: "6", name: "阿里云", subtitle: "alice", letter: "阿", color: .orange),
            P2Row(id: "7", name: "AWS Console", subtitle: "root", letter: "A", color: .init(red: 1, green: 0.45, blue: 0)),
            P2Row(id: "8", name: "Steam", subtitle: "alice", letter: "S", color: .init(red: 0.1, green: 0.2, blue: 0.35)),
            P2Row(id: "9", name: "Netflix", subtitle: "alice@example.com", letter: "N", color: .red),
            P2Row(id: "10", name: "JetBrains", subtitle: "alice@example.com", letter: "J", color: .purple),
            P2Row(id: "11", name: "招商银行", subtitle: "6214 **** **** 8890", letter: "招", color: .red),
            P2Row(id: "12", name: "SSH 部署密钥", subtitle: "SHA256:9f3Kq2mZ8vLpQ…", letter: "$", color: .green),
            P2Row(id: "13", name: "AI 密钥", subtitle: "文件夹 · 1 项", letter: "", color: .clear, isFolder: true)
        ]
    }

    func testDark() throws {
        try snapshot("proposal-v2-dark", appearance: .darkAqua) {
            P2MainWindow(rows: rows, selectedId: "1",
                         recent: Array(rows.prefix(3)))
        }
    }

    func testLight() throws {
        try snapshot("proposal-v2-light", appearance: .aqua) {
            P2MainWindow(rows: rows, selectedId: "1",
                         recent: Array(rows.prefix(3)))
        }
    }

    /// The same window with the icon service not answering — which is what the app actually looks
    /// like today. Drawn so the choice is made with both outcomes on the table: a palette chosen
    /// against working favicons and one chosen against broken ones are not the same palette.
    func testNoFavicons() throws {
        try snapshot("proposal-v2-no-icons", appearance: .darkAqua) {
            P2MainWindow(rows: rows.map { var r = $0; r.hasIcon = false; return r },
                         selectedId: "1",
                         recent: Array(rows.prefix(3)))
        }
    }

    /// Proposal §2's two readings side by side: what shipped, the muted palette, and full monochrome.
    func testSidebarIconStyles() throws {
        let size = CGSize(width: 720, height: 700)
        try snapshot("proposal-v2-sidebar-ab", size: size, appearance: .darkAqua) {
            HStack(spacing: 0) {
                labelled("当前：高饱和", P2Sidebar(selected: "全部项目", iconStyle: .saturated))
                Divider()
                labelled("低饱和调色板", P2Sidebar(selected: "全部项目", iconStyle: .muted))
                Divider()
                labelled("全单色", P2Sidebar(selected: "全部项目", iconStyle: .monochrome))
            }
        }
    }

    private func labelled<V: View>(_ caption: String, _ view: V) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            view
        }
        .frame(width: 240)
    }
}
