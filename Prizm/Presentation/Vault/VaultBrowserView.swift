import SwiftUI
import os.log

// MARK: - VaultBrowserView

/// Three-pane vault browser using `NavigationSplitView`.
///
/// - Sidebar:  `SidebarView` (categories + counts)
/// - Content:  `ItemListView` with native search and `+` button
/// - Detail:   `ItemDetailView` with Edit / Delete buttons
struct VaultBrowserView: View {

    @ObservedObject var viewModel: VaultBrowserViewModel
    let faviconLoader: FaviconLoader
    let makeEditViewModel: (VaultItem) -> ItemEditViewModel
    let makeCreateViewModel: (ItemType, String?) -> ItemEditViewModel
    /// Factory for creating `AttachmentAddViewModel` — injected from AppContainer to
    /// keep the Presentation layer decoupled from the Data layer (Constitution §II).
    var makeAddAttachmentViewModel: ((String) -> AttachmentAddViewModel)? = nil
    /// Factory for creating `AttachmentBatchViewModel` — injected from AppContainer.
    var makeBatchAttachmentViewModel: ((String) -> AttachmentBatchViewModel)? = nil
    /// Factory for `AttachmentRowViewModel` — injected from AppContainer.
    var makeAttachmentRowViewModel: ((String, Attachment) -> AttachmentRowViewModel)? = nil
    /// Factory for `PasswordHistoryViewModel`, threaded to the login detail view.
    var makePasswordHistoryViewModel: ((String) -> PasswordHistoryViewModel)? = nil
    var makePasskeysViewModel: ((String) -> PasskeysViewModel)? = nil
    /// Factory for `TOTPCodeViewModel`; the second argument is the item's stored authenticator key.
    var makeTOTPCodeViewModel: ((String, String?) -> TOTPCodeViewModel)? = nil

    /// Factory for the verification-codes list. A closure rather than a built view model, so the rows
    /// — and their timers — come into existence when the sheet opens and not before.
    var makeVerificationCodesViewModel: (() -> VerificationCodesViewModel)? = nil

    /// Derives the one-time code behind the detail header's Copy code action. Injected so the
    /// Presentation layer never constructs a crypto service (Constitution §II).
    var totpGenerator: (any TOTPGenerator)? = nil

    @State private var showPermanentDeleteAlert = false
    @State private var showDeleteFolderAlert = false
    @State private var folderToDelete: Folder?
    /// Focus for the list's search field. A `@FocusState` rather than the `isPresented` binding
    /// `.searchable` took: the field is drawn by hand now, so ⌘F below moves focus to it directly.
    @FocusState private var isSearchFieldFocused: Bool

    /// Whether the toolbar's search control is showing its field rather than its magnifier.
    @State private var isSearchExpanded = false

    /// The search and sort the codes destination is under.
    ///
    /// Held here rather than in the codes view model because the controls that set them live in the
    /// window's toolbar, and the pane builds its view model internally. Filtering and ordering rows is
    /// presentation, so it happens over the rows rather than inside the type that fetches them.
    @State private var codesQuery = ""
    @State private var codesSort: ItemSortOrder = .nameAscending

    private var isShowingVerificationCodes: Bool { viewModel.sidebarSelection == .verificationCodes }

    /// What the toolbar's search field filters: the item list, or the codes when that is what the list
    /// column is showing. One field, two subjects — the field belongs to the column, not to a list.
    private var listSearchQuery: Binding<String> {
        isShowingVerificationCodes
            ? Binding(get: { codesQuery }, set: { codesQuery = $0 })
            : $viewModel.searchQuery
    }

    /// The list column's width, read from the layout.
    ///
    /// The expanded search field is sized from this rather than given a fixed width: with the discs at
    /// `Spacing.toolbarDisc` a fixed field overflowed the column and pushed the group off its trailing
    /// edge, which is what "it crosses the second column" described.
    @State private var listColumnWidth: CGFloat = 0

    /// What is left of the column for the field once the two discs and their gaps have taken theirs.
    ///
    /// Clamped at both ends. Below 80pt the field cannot show a query; above 180pt it stops reading as
    /// a field and starts reading as the row. The clamp is also why the column's own minimum matters:
    /// `navigationSplitViewColumnWidth` declares 240pt, and this is what fits inside it.
    private var expandedSearchFieldWidth: CGFloat {
        // The two discs, the fixed spacers and the toolbar's own insets measured ~121pt of the column
        // in a real window. Reserving 137 leaves a ~16pt margin at every width, which is the part that
        // matters: a field that merely *ends* inside the column still reads as crossing when it stops
        // against the divider. At the column's 240pt minimum this yields 103pt, still above the floor.
        let taken = Spacing.toolbarDisc * 2 + 63
        return min(180, max(80, listColumnWidth - taken))
    }

    /// The master-password gate for the selected item.
    ///
    /// Rebuilt on each render from the view model's current answer rather than cached, so a reveal
    /// granted a moment ago is reflected immediately and there is no second source of truth about
    /// whether a password may be shown.
    /// The sidebar's selection binding, extracted from the view body.
    ///
    /// Not a style choice: inlined, the `NavigationSplitView` closure grew past what the type checker
    /// will do in reasonable time once a row was added to the sidebar.
    private var sidebarSelectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: { viewModel.isGlobalSearch ? nil : viewModel.sidebarSelection },
            set: { newValue in
                guard let value = newValue else { return }
                Task { @MainActor in viewModel.sidebarSelection = value }
            }
        )
    }

    /// The item list's own controls, in the window's toolbar above the column that owns the list.
    ///
    /// All three are toolbar items again. They were briefly drawn in the column's own content area,
    /// which put them below the titlebar; the toolbar row is where the rest of the window's controls
    /// live and where they belong.
    ///
    /// The search field is not `.searchable`: that hands the field to the window's toolbar, which
    /// draws it in the trailing slot past the detail column, so it can never sit beside these two. A
    /// plain toolbar item holding our own field can — and it is collapsed to a glyph until it is
    /// clicked, which is what a toolbar search looks like when it is not the system one.
    @ToolbarContentBuilder
    private var listToolbarItems: some ToolbarContent {
        // The spacer puts the group at this column's trailing edge, so it sits at the top-right of
        // the list column rather than against the sidebar toggle. `placement` cannot do it — see the
        // note on the detail column's toolbar for the measurement.
        ToolbarSpacer(.flexible)

        if viewModel.sidebarSelection != .trash {
            ToolbarItem(placement: .automatic) { toolbarDisc { createControl } }
                .sharedBackgroundVisibility(.hidden)
        }
        // A fixed spacer between each pair, not decoration: macOS 26 merges adjacent toolbar items
        // into one shared capsule, which drew sort and search as a single control and made three
        // separate functions look like two. A fixed spacer ends the group.
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .automatic) { toolbarDisc { sortControl } }
            .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .automatic) { searchControl }
            .sharedBackgroundVisibility(.hidden)
    }

    /// The disc a toolbar control is drawn in.
    ///
    /// macOS 26 wraps each toolbar item in a shared capsule whose height the toolbar decides — giving
    /// the item a square content frame does **not** turn that capsule into a circle, which was measured
    /// rather than assumed. So these items hide the capsule and draw this instead, sized and styled to
    /// match the split view's own sidebar toggle: `Spacing.toolbarDisc` across, a light fill and a soft
    /// shadow so it reads as the same kind of control as the toggle sitting a few hundred points away.
    private func toolbarDisc<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: Spacing.toolbarDisc, height: Spacing.toolbarDisc)
            .background(
                Circle()
                    .fill(Color.primary.opacity(Opacity.toolbarDiscFill))
                    .shadow(color: .black.opacity(Opacity.toolbarDiscShadow), radius: 1.5, y: 0.5)
            )
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(Opacity.cardBorder(contrast)), lineWidth: 0.5)
            )
    }

    /// The magnifier until it is clicked, the field after that.
    ///
    /// The field is a fixed width rather than flexible: it shares a 240–340pt column with two other
    /// items, and a field that asked for the room it wanted would push them out of the toolbar.
    @ViewBuilder
    private var searchControl: some View {
        if isSearchExpanded {
            searchField(width: expandedSearchFieldWidth)
                // Escape leaves search, which is what the system field did for free and what the
                // global-search requirement has a scenario for: clearing the query is what
                // deactivates global search, through the `onChange` wiring below.
                .onExitCommand {
                    viewModel.searchQuery = ""
                    isSearchExpanded = false
                    isSearchFieldFocused = false
                }
        } else {
            toolbarDisc {
                Button {
                    expandSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Foreground.muted)
                }
                .buttonStyle(.plain)
                .help(L("Search vault"))
                .accessibilityLabel(L("Search vault"))
                .accessibilityIdentifier(AccessibilityID.Vault.searchButton)
            }
        }
    }

    /// Shows the field and puts the caret in it.
    ///
    /// The focus hop is one run-loop turn late on purpose: the field does not exist in the same update
    /// that reveals it, and `@FocusState` cannot be pointed at a view that has not been inserted yet.
    /// Setting it in the same turn is silently dropped, which reads as "the click did nothing".
    private func expandSearch() {
        isSearchExpanded = true
        Task { @MainActor in isSearchFieldFocused = true }
    }

    /// The sort-order menu.
    private var sortControl: some View {
        Menu {
            // A code row has a name and nothing else orderable — no dates, no type — so the codes
            // destination is offered the two name orders and not the four that would do nothing.
            ForEach(isShowingVerificationCodes
                        ? [ItemSortOrder.nameAscending, .nameDescending]
                        : ItemSortOrder.allCases) { order in
                Button {
                    if isShowingVerificationCodes { codesSort = order }
                    else                           { viewModel.sortOrder = order }
                } label: {
                    if order == currentSortOrder {
                        Label(order.displayName, systemImage: "checkmark")
                    } else {
                        Text(order.displayName)
                    }
                }
            }
        } label: {
            // Glyph only. The comment here used to explain why an `HStack` was built by hand instead
            // of a `Label`: a control is free to collapse a `Label` to its icon, and the word was the
            // point. The word is no longer wanted, so the collapse that comment fought is the result
            // now — and the tooltip and accessibility label carry the name the glyph does not print.
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help(L("Sort Order"))
        .accessibilityLabel(L("Sort Order"))
        .accessibilityIdentifier(AccessibilityID.Vault.sortMenu)
    }

    private var currentSortOrder: ItemSortOrder {
        isShowingVerificationCodes ? codesSort : viewModel.sortOrder
    }

    /// The vault search field.
    ///
    /// Drawn rather than borrowed. `TextField` is the plain one — no magnifier, no clear affordance,
    /// no capsule — so the three parts of a search field are assembled here. The `xmark` appears only
    /// when there is something to clear, which is what makes it a control rather than decoration.
    ///
    /// **The frame goes before the background, and that ordering is the point.** `.frame` applied
    /// *after* a `.background` sizes the layout but not the shape: the capsule stays at the content's
    /// own 21pt and the field draws visibly shorter than the discs beside it, which is exactly what was
    /// reported. Both dimensions are passed in because the width has to come from the column.
    private func searchField(width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Foreground.muted)
                .accessibilityHidden(true)

            TextField(L("Search vault"), text: listSearchQuery)
                .textFieldStyle(.plain)
                .font(Typography.listSubtitle)
                .focused($isSearchFieldFocused)
                // The field inside the field. A toolbar sizes its item to the content's ideal width,
                // and a `TextField`'s ideal width grows with its text — so with only the outer frame
                // set, typing widened the whole item until it crossed the column. `maxWidth: .infinity`
                // inside a fixed frame makes the text scroll within the field instead of pushing it.
                .frame(minWidth: 0, maxWidth: .infinity)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Foreground.muted)
                }
                .buttonStyle(.plain)
                .help(L("Clear search"))
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: Spacing.toolbarDisc)
        // The same chrome the discs wear, in the shape a field needs: the four controls in this row
        // have to look like one family, and a grey capsule beside three white discs did not.
        .background(Capsule().fill(Color.primary.opacity(Opacity.toolbarDiscFill)))
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(Opacity.cardBorder(contrast)), lineWidth: 0.5)
        )
        .accessibilityIdentifier(AccessibilityID.Vault.searchField)
    }

    /// A trashed item's two commands.
    ///
    /// **An active item's commands are not here** — favouriting and editing act on the item you are
    /// looking at, so they live in its header (`ItemDetailView.itemHeader`). Why the trash keeps its
    /// pair in the toolbar is in `openspec/changes/item-actions-in-detail-header/design.md` (D3).
    ///
    /// Extracted for the same reason as `sortOrderToolbarItem`: the whole `NavigationSplitView` is one
    /// expression to the type checker, and an `if` inside its toolbar was enough to exceed it again.
    @ToolbarContentBuilder
    private var trashToolbarItems: some ToolbarContent {
        if let item = viewModel.itemSelection, item.isDeleted {
            ToolbarItem(placement: .primaryAction) {
                Button("Restore") {
                    Task { await viewModel.performRestore(id: item.id) }
                }
                .accessibilityIdentifier(AccessibilityID.Trash.restoreButton)
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete Permanently", role: .destructive) {
                    showPermanentDeleteAlert = true
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier(AccessibilityID.Trash.permanentDeleteButton)
            }
        }
    }

    /// The "new item" menu, with ⌘N on a zero-size companion button because a `Menu` cannot itself
    /// carry a keyboard shortcut.
    ///
    /// `list-column-header` requires this control to be **absent from the view tree** in Trash rather
    /// than merely disabled, because the shortcut rides in the hidden companion above — hide the
    /// control, and the shortcut goes with it. `listHeaderRow` applies that condition.
    private var createControl: some View {
        Menu {
            ForEach(ItemType.allCases) { type in
                Button {
                    viewModel.createItemType = type
                } label: {
                    Label(type.displayName, systemImage: type.sfSymbol)
                }
            }
        } label: {
            // Glyph only, for the same reason and by the same request as the sort control: this was an
            // `HStack` built to stop a `Label` collapsing to a bare plus, and a bare plus is what is
            // wanted now. The tooltip and accessibility label are the only things that still name it.
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Foreground.action)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("New Item (⌘N)")
        .accessibilityLabel("New Item")
        .accessibilityIdentifier(AccessibilityID.Create.newItemButton)
        .background {
            Button("") { viewModel.createItemType = .login }
                .keyboardShortcut("n", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    /// The detail column, extracted from the `NavigationSplitView` expression.
    ///
    /// Extracted for the same reason as the toolbar items above: `NavigationSplitView { } content: { }
    /// detail: { }` is a single expression to the type checker, and adding one more closure argument to
    /// the `ItemDetailView(...)` call — the header's favourite callback — was enough to exceed it.
    private var detailColumn: some View {
        ItemDetailView(
            item:                           viewModel.itemSelection,
            faviconLoader:                  faviconLoader,
            folders:                        viewModel.folders,
            organizations:                  viewModel.organizations,
            onCopy:                         { viewModel.copy($0) },
            makeEditViewModel:              makeEditViewModel,
            makeAddAttachmentViewModel:     makeAddAttachmentViewModel,
            makeBatchAttachmentViewModel:   makeBatchAttachmentViewModel,
            makeAttachmentRowViewModel:     makeAttachmentRowViewModel,
            makePasswordHistoryViewModel:   makePasswordHistoryViewModel,
            makePasskeysViewModel:          makePasskeysViewModel,
            makeTOTPCodeViewModel:          makeTOTPCodeViewModel,
            totpGenerator:                  totpGenerator,
            onAttachmentsChanged:           { viewModel.refreshItemSelection() },
            onEditSheetChanged:             { viewModel.handleEditSheetState($0) },
            onSoftDelete:                   { id in await viewModel.performSoftDelete(id: id) },
            onRestore:                      { id in await viewModel.performRestore(id: id) },
            onPermanentDelete:              { id in await viewModel.performPermanentDelete(id: id) },
            onToggleFavorite:               { viewModel.toggleFavorite(item: $0) },
            editTrigger:                    viewModel.editTrigger,
            saveTrigger:                    viewModel.saveTrigger,
            gate:                           revealGate
        )
        // The gate's own prompt. Driven by the view model rather than by local state so
        // there is exactly one place that decides a master password is owed.
        .sheet(isPresented: Binding(
            get: { viewModel.pendingReprompt != nil },
            set: { presented in if !presented { viewModel.cancelReprompt() } }
        )) {
            RepromptSheet(viewModel: viewModel)
        }
        .toolbar {
            // The trash controls stay at the window's trailing edge. The browser's own controls —
            // sort and create — moved to the content column at the user's request: they act on the
            // item list, and they now sit above it beside the search field rather than at the far
            // side of a detail pane that is empty until something is selected.
            trashToolbarItems
            // Everything after a flexible spacer is drawn against the window's trailing edge, and
            // this is the only arrangement that does it. Measured in a window-sized probe of the
            // three-column split: items declared on a column land inside that column's span; on the
            // split view itself (or with `placement: .primaryAction`, or as a `.primaryAction`
            // group) they pack in behind the sidebar toggle. `placement` has no effect inside a
            // column — the column owns the position — so the trailing edge has to be reached by
            // pushing with a spacer from the column that is already last.
            ToolbarSpacer(.flexible)
        }
    }

    /// The verification-codes destination's content, extracted from the modifier chain.
    ///
    /// A view body of this size is one expression to the type checker, and an inline closure here was
    /// enough to push it past what the checker will do — reporting, unhelpfully, that some unrelated
    /// toolbar button could not be type-checked.
    @ViewBuilder
    private var verificationCodesPane: some View {
        if let makeVerificationCodesViewModel {
            VerificationCodesPane(
                makeViewModel: makeVerificationCodesViewModel,
                onSelect: { viewModel.highlightItem(id: $0) },
                query: codesQuery,
                sortOrder: codesSort
            )
        }
    }

    /// Opens the delete-folder confirmation.
    ///
    /// A method rather than an inline closure: multi-statement closures inside an initializer this size
    /// are disproportionately expensive to infer, and this body is already near the checker's limit.
    private func beginFolderDelete(_ folder: Folder) {
        folderToDelete = folder
        showDeleteFolderAlert = true
    }

    private var revealGate: RevealGateBinding {
        guard let item = viewModel.itemSelection else { return .none }
        return viewModel.revealGate(for: item)
    }
    @Environment(\.colorSchemeContrast) private var contrast

    /// Asks SwiftUI for the app's `Settings` scene. Used by the gear in the sidebar's status row;
    /// resolving it here rather than constructing a window means there is one Settings window and
    /// ⌘, and the button cannot end up pointing at two different things.
    @Environment(\.openSettings) private var openSettings

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "UI.VaultBrowser")

    var body: some View {
        NavigationSplitView(
            sidebar: {
                VStack(spacing: 0) {
                    SidebarView(
                        selection: sidebarSelectionBinding,
                        itemCounts: viewModel.itemCounts,
                        folders: viewModel.folders,
                        organizations: viewModel.organizations,
                        collections: viewModel.collections,
                        actions: SidebarActions(
                            createFolder: { viewModel.createFolder(name: $0) },
                            renameFolder: { viewModel.renameFolder(id: $0, name: $1) },
                            deleteFolder: beginFolderDelete,
                            dropItems: { viewModel.moveItemsToFolder(itemIds: $0, folderId: $1) },
                            createCollection: { viewModel.createCollection(name: $0, organizationId: $1) },
                            renameCollection: { viewModel.renameCollection(id: $0, organizationId: $1, name: $2) },
                            deleteCollection: { viewModel.deleteCollection(id: $0, organizationId: $1) },
                            showVerificationCodes: { viewModel.sidebarSelection = .verificationCodes }
                        )
                    )
                    // The refresh control rides with the state it refreshes, at the leading end of the
                    // sidebar's status row, and the settings gear closes the same row — rather than
                    // either of them sitting in the titlebar beside the sort control.
                    SyncStatusView(
                        label:           viewModel.syncStatusLabel,
                        isSyncing:       viewModel.isSyncing,
                        unreadableCount: viewModel.unreadableItemCount,
                        onSync:          { viewModel.performManualSync() },
                        // The same window ⌘, opens, so the two routes cannot drift: there is one
                        // `Settings` scene and this asks SwiftUI for it rather than rebuilding one.
                        onOpenSettings:  { openSettings() }
                    )
                }
                // The vault search field used to be attached here, on the reasoning that searching and
                // choosing *where* to search belong in one place. It moved to the content column at
                // the user's request, so that the three controls which act on the item list — sort,
                // create, search — sit together above that list. The binding, the focused state, the
                // ⌘F activation and the global-search rules are untouched by the move.
                //
                // No gear in this strip either: the approved reference holds nothing between the
                // traffic lights and the sidebar toggle, so Settings is reached from the app menu
                // (⌘,) and from the gear at the end of the status row below.
                //
                // Last in the chain on purpose, and the ordering is the point: measured against a
                // saved-column readout, with `.searchable` and `.toolbar` applied *after* this
                // preference the sidebar laid out at 144pt — below the 200pt minimum declared right
                // here — while the content column, which applies the same modifier last, holds its
                // 262pt ideal. The preference was being dropped for this column, not ignored by the
                // API, so it now goes last.
                .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 280)
            },
            content: {
                VStack(spacing: 0) {
                    syncErrorBanner
                    if viewModel.sidebarSelection == .verificationCodes {
                        verificationCodesPane
                    } else if viewModel.sidebarSelection == .trash {
                        TrashView(
                            items:             viewModel.displayedItems,
                            selection:         $viewModel.itemSelection,
                            faviconLoader:     faviconLoader,
                            onRestore:         { id in await viewModel.performRestore(id: id) },
                            onPermanentDelete: { id in await viewModel.performPermanentDelete(id: id) },
                            onEmptyTrash:      { await viewModel.performEmptyTrash() }
                        )
                    } else {
                        ItemListView(
                            items:          viewModel.displayedItems,
                            selection:      $viewModel.itemSelection,
                            faviconLoader:  faviconLoader,
                            searchQuery:    viewModel.searchQuery.isEmpty ? nil : viewModel.searchQuery,
                            organizations:  viewModel.organizations,
                            onDelete:       { id in await viewModel.performSoftDelete(id: id) },
                            onToggleFavorite: { viewModel.toggleFavorite(item: $0) },
                            onDuplicate:    { viewModel.duplicateItem(id: $0.id) }
                        )
                    }
                }
                // The list's own controls live in the window's toolbar, above this column — see
                // `listToolbarItems`. They are not `.searchable`: that gives the field to the window's
                // toolbar, which draws it in the trailing slot beyond the detail column, so it can
                // never sit beside the create and sort controls.
                //
                // The width is reported out of here because the toolbar draws in a different hierarchy
                // from this column, and the expanded field has to be sized to the column it belongs to.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listColumnWidth = $0 }
                .toolbar {
                    listToolbarItems
                }
                // Last in the chain, and the ordering is still load-bearing: measured against a
                // saved-column readout, with `.toolbar` applied *after* this preference the content
                // column lost its 262pt ideal. The preference is dropped, not ignored by the API.
                .navigationSplitViewColumnWidth(min: 240, ideal: 262, max: 340)
            },
            detail: { detailColumn }
        )
        .navigationSplitViewStyle(.balanced)
        .alert("Action Failed", isPresented: Binding(
            get:  { viewModel.actionError != nil },
            set:  { if !$0 { viewModel.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .alert("Delete Permanently?", isPresented: $showPermanentDeleteAlert) {
            Button("Delete Permanently", role: .destructive) {
                if let item = viewModel.itemSelection {
                    Task { await viewModel.performPermanentDelete(id: item.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L("\"%@\" will be permanently deleted and cannot be recovered.", viewModel.itemSelection?.name ?? ""))
        }
        .alert("Delete Folder?", isPresented: $showDeleteFolderAlert) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderToDelete {
                    viewModel.deleteFolder(id: folder.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L("Items in \"%@\" will not be deleted. They will become unfoldered.", folderToDelete?.name ?? ""))
        }
        .accessibilityIdentifier(AccessibilityID.Vault.navigationSplit)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onChange(of: viewModel.sidebarSelection) { _, newValue in
            if newValue == .trash {
                viewModel.searchQuery = ""
            }
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            if newValue.isEmpty && viewModel.isGlobalSearch {
                viewModel.deactivateGlobalSearch()
            }
        }
        .onChange(of: viewModel.isGlobalSearch) { _, isActive in
            if !isActive { isSearchFieldFocused = false }
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            // Collapses back to the magnifier when the field loses focus with nothing typed.
            //
            // Without this the toolbar keeps a text field open for the rest of the session, which is
            // what "once it expands it will not go back" describes. A non-empty query keeps it open on
            // purpose: hiding an active filter behind a glyph would hide the fact that the list is
            // showing fewer items than the vault holds.
            if !focused, viewModel.searchQuery.isEmpty {
                isSearchExpanded = false
            }
        }
        .onChange(of: viewModel.syncErrorMessage) { _, newMessage in
            if let message = newMessage {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: viewModel.actionError) { _, newError in
            if let error = newError {
                AccessibilityNotification.Announcement(error).post()
            }
        }
        .background {
            Button("") {
                // `activateGlobalSearch` is the item list's search: it widens the scope and drops the
                // sidebar selection, which would take the user off the codes destination mid-keystroke.
                // On that destination ⌘F only has to reach the field.
                if !isShowingVerificationCodes { viewModel.activateGlobalSearch() }
                expandSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .sheet(item: $viewModel.createItemType) { type in
            ItemEditView(
                viewModel: makeCreateViewModel(type,
                    viewModel.selectedCollectionId ?? viewModel.selectedFolderId),
                isPresented: Binding(
                    get: { viewModel.createItemType != nil },
                    set: { if !$0 { viewModel.createItemType = nil } }
                )
            )
        }
        // Export and import. `isPresented` rather than `.sheet(item:)` so that the hand-offs —
        // consent → done, progress → report — update the content instead of tearing the sheet
        // down and rebuilding it. See `VaultBackupSheet`.
        .sheet(isPresented: Binding(
            get: { viewModel.backupSheet != nil },
            set: { if !$0 { viewModel.dismissBackupSheet() } }
        )) {
            if let sheet = viewModel.backupSheet {
                VaultBackupSheetView(
                    sheet: sheet,
                    itemCount: viewModel.itemCounts[.allItems] ?? 0,
                    onDismiss: { viewModel.dismissBackupSheet() },
                    onConfirmExport: { viewModel.confirmExport() },
                    exportFormat: $viewModel.exportFormat
                )
            }
        }
        // The codes are a destination now, not a sheet: nothing is presented here, and leaving the
        // destination is what releases the rows' timers.
    }

    // MARK: - Sync Error Banner

    @ViewBuilder
    private var syncErrorBanner: some View {
        if let message = viewModel.syncErrorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(Typography.bannerText)
                Spacer()
                Button {
                    viewModel.dismissSyncError()
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier(AccessibilityID.Vault.syncErrorDismiss)
            }
            .padding(.horizontal, Spacing.bannerHorizontal)
            .padding(.vertical, Spacing.bannerVertical)
            .background(Color.yellow.opacity(Opacity.bannerBackground(contrast)))
            .frame(maxHeight: 44)
            .accessibilityIdentifier(AccessibilityID.Vault.syncErrorBanner)
        }
    }
}
