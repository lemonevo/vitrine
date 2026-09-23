import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Prizm

/// Renders the item list's toolbar — the three controls, and the search control in both its states —
/// to PNGs under `/tmp/prizm-design/probe/`.
///
/// **Why a real window with a real `NavigationSplitView`.** The subject is how the *toolbar* draws
/// these items, and macOS 26 puts adjacent toolbar items into one shared capsule. Only a real
/// toolbar shows that: `VaultScreenshotTests` lays its panes out in an `HStack`, which has no
/// toolbar at all, and an offscreen split view draws its detail pane blank.
///
/// **Why the theme frame is captured rather than `contentView`.** An `NSToolbar` is not a subview of
/// the content view; AppKit draws it in the theme frame above. Capturing the content view would omit
/// exactly the thing under review.
///
/// **Why the expanded state is flipped from inside.** The reported failure was "the search will not
/// expand", which is a question about whether a toolbar item's content follows the state that
/// reveals it — not about how the field looks. Setting the flag after the window is up and then
/// capturing answers that; a screenshot of a hand-set state would not.
///
/// **What is real and what is rebuilt.** The panes are the app's own views over `DesignFixtures`.
/// The controls are rebuilt here because `VaultBrowserView` declares them `private`. Read these for
/// grouping and placement; do not read them as pixel-exact chrome.
@MainActor
final class MainWindowToolbarProbeTests: XCTestCase {

    private let windowSize = CGSize(width: 1180, height: 720)
    private let optionKeyMonitor = OptionKeyMonitor()

    // MARK: - Capture

    /// Renders with the toolbar's display mode forced to "Icon and Text".
    ///
    /// The right-click menu macOS offers on a toolbar item switches between the two modes. With empty
    /// item labels there is nothing for the other mode to draw — but that is a claim about the
    /// rendered result, so it is rendered.
    private func renderIconAndLabel(_ name: String) throws {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(
            rootView: AnyView(ProbeWindow(state: ProbeState(), size: windowSize)
                .environment(optionKeyMonitor)))
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(1.4))
        window.toolbar?.displayMode = .iconAndLabel
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else {
            return XCTFail("could not prepare capture for \(name)")
        }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("could not encode \(name)")
        }
        let url = URL(fileURLWithPath: "/tmp/prizm-design/probe/\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
        window.orderOut(nil)
    }

    /// Renders one arrangement, optionally flipping the search open once the window is up.
    private func render(_ name: String, expandAfterMount: Bool) throws {
        let state = ProbeState()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.title = "Vitrine"
        window.contentView = NSHostingView(
            rootView: AnyView(
                ProbeWindow(state: state, size: windowSize)
                    .environment(optionKeyMonitor)
            )
        )
        window.setFrame(NSRect(origin: .zero, size: windowSize), display: true)
        window.orderFrontRegardless()

        // Let SwiftUI bridge `.toolbar` onto the window's `NSToolbar` and settle the columns.
        RunLoop.current.run(until: Date().addingTimeInterval(1.4))

        if expandAfterMount {
            // The same thing the magnifier's action does, one run-loop turn later — which is when the
            // field is in the hierarchy for the toolbar to draw.
            state.isSearchExpanded = true
            RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        }

        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else {
            return XCTFail("could not prepare capture for \(name)")
        }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("could not encode \(name)")
        }
        let url = URL(fileURLWithPath: "/tmp/prizm-design/probe/\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
        window.orderOut(nil)
    }

    // MARK: - Shots

    /// The three controls, each in its own capsule.
    func testListToolbarCollapsed() throws {
        try render("list-toolbar-collapsed", expandAfterMount: false)
    }

    /// What "Icon and Text" would draw for controls that carry no label.
    func testListToolbarIconAndLabel() throws {
        try renderIconAndLabel("list-toolbar-icon-and-label")
    }

    /// The magnifier replaced by the field — the state the click is supposed to produce.
    func testListToolbarExpanded() throws {
        try render("list-toolbar-expanded", expandAfterMount: true)
    }
}

// MARK: - ProbeState

/// The one piece of state the probe flips, held in a reference type so the capture can reach the
/// same instance the view is observing.
@MainActor
private final class ProbeState: ObservableObject {
    @Published var isSearchExpanded = false
}

// MARK: - ProbeWindow

private let probeQuery = "accounts.google.com"

private struct ProbeWindow: View {
    @ObservedObject var state: ProbeState
    let size: CGSize

    /// Long on purpose: the state under review is what a *filled* field does to the toolbar item's
    /// width, which is what "it crosses the column once I type" described.
    @State private var query = probeQuery
    @State private var selection: VaultItem?
    @State private var sidebarSelection: SidebarSelection? = .allItems

    private let faviconLoader = FaviconLoader(session: .shared)

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $sidebarSelection,
                itemCounts: DesignFixtures.itemCounts,
                folders: DesignFixtures.folders,
                organizations: DesignFixtures.organizations,
                collections: DesignFixtures.collections
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 280)
        } content: {
            ItemListView(
                items: DesignFixtures.items.filter { !$0.isDeleted },
                selection: $selection,
                faviconLoader: faviconLoader,
                organizations: DesignFixtures.organizations
            )
            .toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .automatic) { disc { createControl } }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed)
                ToolbarItem(placement: .automatic) { disc { sortControl } }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed)
                ToolbarItem(placement: .automatic) { searchControl }
                    .sharedBackgroundVisibility(.hidden)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 262, max: 340)
        } detail: {
            ItemDetailView(
                item: nil,
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
                    TOTPCodeViewModel(itemId: "probe", secret: secret, generator: TOTPGeneratorImpl())
                },
                totpGenerator: TOTPGeneratorImpl()
            )
        }
        .frame(width: size.width, height: size.height)
    }

    @Environment(\.colorSchemeContrast) private var contrast

    /// The circular chrome the app draws for these toolbar items — see `VaultBrowserView.toolbarDisc`.
    private func disc<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 37, height: 37)
            .background(
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.16), radius: 1.5, y: 0.5)
            )
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(Opacity.cardBorder(contrast)), lineWidth: 0.5)
            )
    }

    // MARK: Controls — mirrors the app's, which are `private`

    private var createControl: some View {
        Menu {
            ForEach(ItemType.allCases) { type in
                Button {} label: { Label(type.displayName, systemImage: type.sfSymbol) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Foreground.action)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    private var sortControl: some View {
        Menu {
            ForEach(ItemSortOrder.allCases) { order in
                Button {} label: {
                    if order == .createdNewestFirst {
                        Label(order.displayName, systemImage: "checkmark")
                    } else {
                        Text(order.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchControl: some View {
        if state.isSearchExpanded {
            // What `expandedSearchFieldWidth` yields for this 262pt column:
            // min(180, max(80, 262 - 37*2 - 40)) = 148.
            searchField(width: 118)
        } else {
            disc {
                Button {} label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Foreground.muted)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 26, height: 26)
        }
    }

    private func searchField(width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Foreground.muted)
            TextField(L("Search vault"), text: $query)
                .textFieldStyle(.plain)
                .font(Typography.listSubtitle)
                .frame(minWidth: 0, maxWidth: .infinity)

            // The clear control, which only exists once there is something to clear — the second
            // thing that appears when the user types, and the one most likely to push the item wider.
            if !query.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Foreground.muted)
            }
        }
        .padding(.horizontal, 9)
        // Frame before background — see the note in `VaultBrowserView.searchField`.
        .frame(width: width, height: Spacing.toolbarDisc)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(Opacity.cardBorder(contrast)), lineWidth: 0.5)
        )
    }
}
