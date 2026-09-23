import AppKit
import SwiftUI
import XCTest
@testable import Prizm

/// Renders the vault screens with demo content to PNGs under `/tmp/prizm-design/`.
///
/// **Why a real window.** `ImageRenderer` rasterises a view without a window, and the AppKit-backed
/// controls these screens are built from — `List`, `ScrollView` — do not survive that: they come back
/// as the system's "unavailable" placeholder. An ordered `NSWindow` gives them the layer trees they
/// need, and `cacheDisplay` reads the window's own content view, which needs no screen-recording
/// permission.
///
/// **Why `HStack` instead of `NavigationSplitView`.** The split view needs a live window with a
/// toolbar and a divider position to lay itself out, and offscreen it renders its detail pane blank.
/// Three panes side by side at the split view's own minimum widths is the same picture.
@MainActor
final class VaultScreenshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1180, height: 720)
    private let sidebarWidth: CGFloat = 210
    private let listWidth: CGFloat = 300

    // MARK: - Harness

    private func snapshot<V: View>(
        _ name: String,
        size: CGSize? = nil,
        appearance: NSAppearance.Name = .aqua,
        settle: TimeInterval = 0.9,
        @ViewBuilder _ view: () -> V
    ) throws {
        let size = size ?? windowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        // The background is supplied here rather than left to the window. `NSWindow.backgroundColor`
        // is resolved against the appearance in force when the window is created, so a window made in
        // a light-mode process keeps a light backing even after its appearance is switched — which
        // showed up as a detail pane drawing white text on white. The sidebar and the list hide the
        // problem because `List` paints its own background, and that asymmetry is what made the
        // capture look like a dark-mode bug in the app rather than in the harness.
        window.contentView = NSHostingView(
            rootView: AnyView(
                installEnvironment(view())
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))

        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            XCTFail("could not prepare capture for \(name)")
            return
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("could not encode \(name)")
            return
        }
        let url = URL(fileURLWithPath: "/tmp/prizm-design/\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
        window.orderOut(nil)
    }

    // MARK: - Composition

    /// The three panes side by side, as `VaultBrowserView` lays them out.
    ///
    /// `NavigationSplitView` itself is not used: offscreen it draws its detail pane blank. Three panes
    /// at the split view's own column widths is the same picture.
    ///
    /// The list is filtered by `selection` so each shot shows what that category would really hold.
    /// Passing the whole fixture set made the sidebar's badge counts and the list disagree, which is
    /// exactly the kind of thing a screenshot review is for catching.
    @ViewBuilder
    private func vaultWindow(
        selection: SidebarSelection? = .allItems,
        item: VaultItem?,
        detailWidth: CGFloat = 574
    ) -> some View {
        HStack(spacing: 0) {
            SidebarView(
                selection: .constant(selection),
                itemCounts: DesignFixtures.itemCounts,
                folders: DesignFixtures.folders,
                organizations: DesignFixtures.organizations,
                collections: DesignFixtures.collections
            )
            .frame(width: sidebarWidth)

            Divider()

            ItemListView(
                items: items(for: selection),
                selection: .constant(item),
                faviconLoader: faviconLoader,
                organizations: DesignFixtures.organizations
            )
            .frame(width: listWidth)

            Divider()

            ItemDetailView(
                item: item,
                faviconLoader: faviconLoader,
                folders: DesignFixtures.folders,
                organizations: DesignFixtures.organizations,
                onCopy: { _ in },
                makeEditViewModel: { candidate in
                    ItemEditViewModel(item: candidate, useCase: NoopEditVaultItemUseCase(),
                                      folders: DesignFixtures.folders,
                                      organizations: DesignFixtures.organizations,
                                      collections: DesignFixtures.collections)
                },
                makePasswordHistoryViewModel: nil,
                makePasskeysViewModel: nil,
                makeTOTPCodeViewModel: { _, secret in
                    TOTPCodeViewModel(itemId: "shot", secret: secret, generator: TOTPGeneratorImpl())
                },
                totpGenerator: TOTPGeneratorImpl()
            )
            .frame(width: detailWidth)
        }
    }

    /// The same scoping `VaultRepositoryImpl.items(for:)` applies, over the fixtures.
    private func items(for selection: SidebarSelection?) -> [VaultItem] {
        let live = DesignFixtures.items.filter { !$0.isDeleted }
        switch selection {
        case .none, .some(.allItems):  return live
        case .some(.favorites):        return live.filter(\.isFavorite)
        case .some(.trash):            return DesignFixtures.items.filter(\.isDeleted)
        case .some(.type(let type)):   return live.filter { DesignFixtures.matches($0, type) }
        case .some(.folder(let id)):   return live.filter { $0.folderId == id }
        case .some(.organization(let id)): return live.filter { $0.organizationId == id }
        case .some(.collection(let id)):   return live.filter { $0.collectionIds.contains(id) }
        case .some(.verificationCodes): return []
        // Scoped the way the real index scopes it, so a shot of this destination shows the same items
        // the app would list.
        case .some(.passkeys):          return live.filter(\.hasPasskey)
        case .some(.newFolder), .some(.newCollection): return live
        }
    }

    private var faviconLoader = FaviconLoader(session: .shared)

    override func setUp() async throws {
        try await super.setUp()
        // The shots show English string keys, so the dates have to be formatted in English too.
        // In the app `LocalizationManager` sets both halves from one choice; a bare test process sets
        // neither, and the default is the machine's language — which here is zh-Hans, producing
        // "Updated 4天前" under an English "UPDATED" heading.
        ActiveLocalization.languageCode = "en"
        ActiveLocalization.locale       = Locale(identifier: "en")
    }

    /// `MaskedFieldView` reads this from the environment and traps when it is absent — which is every
    /// field holding a password, card number or private key. The real app installs one in
    /// `PrizmApp.body`; the harness has to do the same or the detail pane kills the test process.
    private let optionKeyMonitor = OptionKeyMonitor()

    private func installEnvironment<V: View>(_ view: V) -> some View {
        view.environment(optionKeyMonitor)
    }

    // MARK: - Shots

    func testVaultLoginSelected() throws {
        let item = DesignFixtures.items.first { $0.id == "i-github" }
        try snapshot("vault-login") { vaultWindow(item: item) }
        try snapshot("vault-login-dark", appearance: .darkAqua) { vaultWindow(item: item) }
    }

    func testVaultCardSelected() throws {
        try snapshot("vault-card") {
            vaultWindow(selection: .type(.card),
                        item: DesignFixtures.items.first { $0.id == "i-visa" })
        }
    }

    func testVaultIdentitySelected() throws {
        try snapshot("vault-identity") {
            vaultWindow(selection: .type(.identity),
                        item: DesignFixtures.items.first { $0.id == "i-identity" })
        }
    }

    func testVaultNotesAndSSH() throws {
        try snapshot("vault-wifi-note") {
            vaultWindow(selection: .type(.secureNote),
                        item: DesignFixtures.items.first { $0.id == "i-wifi" })
        }
        try snapshot("vault-ssh-key") {
            vaultWindow(selection: .type(.sshKey),
                        item: DesignFixtures.items.first { $0.id == "i-ssh" })
        }
    }

    func testVaultRepromptItem() throws {
        try snapshot("vault-reprompt") {
            vaultWindow(item: DesignFixtures.items.first { $0.id == "i-bank" })
        }
    }

    func testVaultEmptySelection() throws {
        try snapshot("vault-empty-selection") { vaultWindow(item: nil) }
    }

    func testVaultTrash() throws {
        try snapshot("vault-trash", size: CGSize(width: 1180, height: 420)) {
            vaultWindow(selection: .trash, item: DesignFixtures.items.first { $0.id == "i-old-twitter" })
        }
    }

    /// The passkeys destination, with two items whose credentials read successfully and one whose read
    /// failed — the three states a row can be in, in one shot.
    ///
    /// The loader is canned rather than wired to a key: what this picture is for is the row's layout
    /// (name, username, how many it carries, who they are registered with, and the footnote), and the
    /// decryption itself is pinned by `VaultRepositoryPasskeysTests` against the real implementation.
    func testPasskeysPane() throws {
        try snapshot("passkeys", size: CGSize(width: 320, height: 380)) {
            PasskeysPane(
                items: [
                    passkeyItem(id: "p-github", name: "GitHub", username: "octocat", count: 2),
                    passkeyItem(id: "p-acme", name: "Acme VPN", username: nil, count: 1),
                    passkeyItem(id: "p-broken", name: "Unreadable", username: "someone", count: 1),
                ],
                onSelect: { _ in },
                makeViewModel: { id in
                    PasskeysViewModel(itemId: id,
                                      useCase: StubPasskeyLoader(credentials: self.stubCredentials(for: id),
                                                                 failing: id == "p-broken"))
                }
            )
        }
    }

    /// Two credentials on one row, so the shot shows the multi-line layout and the count agreeing with
    /// the names beneath it.
    private func stubCredentials(for itemId: String) -> [PasskeyCredential] {
        switch itemId {
        case "p-github":
            return [
                PasskeyCredential(rpId: "github.com", rpName: "GitHub", userName: "octocat",
                                  userDisplayName: nil,
                                  creationDate: Date(timeIntervalSince1970: 1_767_225_600)),
                PasskeyCredential(rpId: "desktop.github.com", rpName: nil, userName: nil,
                                  userDisplayName: nil, creationDate: nil),
            ]
        case "p-acme":
            return [PasskeyCredential(rpId: "vpn.acme.example", rpName: "Acme", userName: "octocat",
                                      userDisplayName: nil, creationDate: nil)]
        default:
            return []
        }
    }

    private func passkeyItem(id: String, name: String, username: String?, count: Int) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: .now, revisionDate: .now,
            content: .login(LoginContent(username: username, password: nil, uris: [],
                                         totp: nil, notes: nil, customFields: [])),
            preserved: PreservedCipherFields(
                fido2Credentials: (0..<count).map { .object(["rpId": .string("opaque-\($0)")]) }
            )
        )
    }

    /// The verification-codes sheet, with the countdown as the detail pane draws it.
    func testVerificationCodesPane() async throws {
        let vault = MockVaultRepository()
        await vault.populate(items: DesignFixtures.items,
                             folders: DesignFixtures.folders,
                             organizations: DesignFixtures.organizations,
                             collections: DesignFixtures.collections,
                             syncedAt: Date())

        try snapshot("codes", size: CGSize(width: 420, height: 300)) {
            VerificationCodesPane(
                makeViewModel: {
                    VerificationCodesViewModel(vault: vault,
                                               generator: TOTPGeneratorImpl(),
                                               gateFor: { _ in .none })
                },
                onSelect: { _ in }
            )
        }
    }

    /// The countdown has to actually reach the screen.
    ///
    /// **Why the clock is advanced by hand.** The view model refreshes from a timer whose block hops
    /// with `Task { @MainActor … }`, and this test method is itself a block executing on the main
    /// queue — so that hop cannot run until the test returns. A plain `Timer` fires under
    /// `RunLoop.run(until:)`; a main-queue continuation does not. Waiting for real seconds therefore
    /// proves nothing about the app, only about the harness. Calling `refresh(at:)` directly drives the
    /// same published values the timer would, and leaves the thing actually under test — does a change
    /// in the model reach this view — as the only variable.
    ///
    /// **What was broken.** The row held its `TOTPCodeViewModel` as a plain `let`, which installs no
    /// subscription, so the cell drew once when the sheet opened and never again: the seconds sat still,
    /// and `displayCode` was frozen by the same omission, meaning an expired code stayed on screen
    /// looking current. The view model was correct throughout and its own tests were green.
    func testCodesCountdownReachesTheView() async throws {
        let vault = MockVaultRepository()
        await vault.populate(items: DesignFixtures.items,
                             folders: DesignFixtures.folders,
                             organizations: DesignFixtures.organizations,
                             collections: DesignFixtures.collections,
                             syncedAt: Date())

        var listModel: VerificationCodesViewModel?
        let size = CGSize(width: 420, height: 300)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(
            rootView: AnyView(
                installEnvironment(
                    VerificationCodesPane(
                        makeViewModel: {
                            let made = VerificationCodesViewModel(
                                vault: vault, generator: TOTPGeneratorImpl(), gateFor: { _ in .none })
                            listModel = made
                            return made
                        },
                        onSelect: { _ in }
                    )
                )
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        window.orderFrontRegardless()

        func grab() -> Data? {
            guard let content = window.contentView,
                  let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
            content.cacheDisplay(in: content.bounds, to: rep)
            return rep.representation(using: .png, properties: [:])
        }

        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let before = try XCTUnwrap(grab(), "could not capture the codes sheet")

        let codes = try XCTUnwrap(listModel?.rows.map(\.code), "the sheet built no rows")
        XCTAssertFalse(codes.isEmpty, "the fixtures produced no verification codes to watch")
        // Six seconds on: a different second, and the ring's fraction has moved with it.
        let later = Date().addingTimeInterval(6)
        codes.forEach { $0.refresh(at: later) }

        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let after = try XCTUnwrap(grab(), "could not re-capture the codes sheet")

        window.orderOut(nil)

        try before.write(to: URL(fileURLWithPath: "/tmp/prizm-design/codes-before-tick.png"))
        try after.write(to: URL(fileURLWithPath: "/tmp/prizm-design/codes-after-tick.png"))

        XCTAssertNotEqual(before, after, """
        Advancing every code's clock by six seconds changed nothing on screen. The cell is not         observing its view model — check for a plain `let` where an `@ObservedObject` belongs.
        """)
    }

    func testSidebarAlone() throws {
        try snapshot("sidebar", size: CGSize(width: sidebarWidth, height: 620)) {
            SidebarView(
                selection: .constant(.allItems),
                itemCounts: DesignFixtures.itemCounts,
                folders: DesignFixtures.folders,
                organizations: DesignFixtures.organizations,
                collections: DesignFixtures.collections
            )
        }
    }
}

// MARK: - Passkeys destination fixtures

/// Answers with fixed credentials, or throws for the item it was told is unreadable.
private struct StubPasskeyLoader: GetPasskeysUseCase {
    let credentials: [PasskeyCredential]
    let failing: Bool

    func execute(itemId: String) async throws -> [PasskeyCredential] {
        if failing { throw VaultError.decryptionFailed("stubbed for the screenshot") }
        return credentials
    }
}
