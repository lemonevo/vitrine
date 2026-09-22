import AppKit
import SwiftUI
import XCTest
@testable import Prizm

/// Renders the auth-screen proposal, and probes the one thing in the current login screen that is a
/// defect rather than a matter of taste.
@MainActor
final class AuthScreenProposalTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        ActiveLocalization.languageCode = "en"
        ActiveLocalization.locale       = Locale(identifier: "en")
    }

    private func snapshot<V: View>(_ name: String, size: CGSize,
                                   appearance: NSAppearance.Name = .aqua,
                                   @ViewBuilder _ view: () -> V) throws {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = NSHostingView(
            rootView: AnyView(view().frame(width: size.width, height: size.height))
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

    func testProposalLight() throws {
        try snapshot("auth-proposed-login", size: CGSize(width: 900, height: 640)) {
            ProposedLoginSheet()
        }
    }

    func testProposalUnlock() throws {
        try snapshot("auth-proposed-unlock", size: CGSize(width: 520, height: 620)) {
            ProposedUnlockSheet()
        }
    }

    func testProposalDark() throws {
        try snapshot("auth-proposed-login-dark", size: CGSize(width: 900, height: 640),
                     appearance: .darkAqua) {
            ProposedLoginSheet()
        }
    }

    /// **Which of the two things in the current login screen is actually a bug.**
    ///
    /// The rendered `auth-login-min.png` shows the placeholder text `https://vault.example.com` and
    /// `you@example.com` in blue with an underline, in fields that are empty. If that is the
    /// placeholder being data-detected into a link, the field looks pre-filled with something
    /// clickable before the user has typed anything — and no amount of restyling fixes it.
    ///
    /// Three variants, so the answer is visible rather than argued about.
    func testPlaceholderLinkProbe() throws {
        try snapshot("auth-probe-placeholder", size: CGSize(width: 460, height: 320)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("A — URL placeholder, focused").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("https://vault.example.com", text: .constant(""))
                    .textFieldStyle(.roundedBorder)

                Text("B — URL placeholder, not focused").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("https://vault.example.com", text: .constant(""))
                    .textFieldStyle(.roundedBorder)

                Text("C — no placeholder").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("", text: .constant(""))
                    .textFieldStyle(.roundedBorder)

                Text("D — plain words as placeholder").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("you at example dot com", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
