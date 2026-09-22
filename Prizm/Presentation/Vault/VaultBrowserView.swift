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
    @State private var isSearchFieldFocused = false

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

    /// The sort-order menu.
    ///
    /// Extracted from the toolbar rather than written inline. `NavigationSplitView`'s closures are one
    /// enormous expression to the type checker, and adding a second toolbar item to it pushed the whole
    /// body past what it will do in reasonable time. The message it gives ("unable to type-check this
    /// expression") points at whichever sub-expression it gave up on, not at the cause.
    private var sortOrderToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(ItemSortOrder.allCases) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        if order == viewModel.sortOrder {
                            Label(order.displayName, systemImage: "checkmark")
                        } else {
                            Text(order.displayName)
                        }
                    }
                }
            } label: {
                // An `HStack`, not a `Label`. A toolbar is free to collapse a `Label` to its icon when it
                // judges there is no room for the title, and that is what it did here: the word on the
                // control — the whole point of the item — disappeared. Built by hand, it is drawn as
                // written.
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(viewModel.sortOrder.toolbarLabel)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Foreground.muted)
                }
                .foregroundStyle(.primary)
            }
            // `.borderlessButton`, not `.button`: the latter draws the label in a button's own chrome,
            // and in a macOS 26 toolbar that chrome is the rounded capsule the reference does not have.
            // `.buttonStyle(.plain)` was already applied when the capsule was still drawn, so the
            // chrome comes from the menu style, not from the button style.
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help(L("Sort Order"))
            .accessibilityLabel(L("Sort Order"))
            .accessibilityIdentifier(AccessibilityID.Vault.sortMenu)
        }
        // macOS 26 draws each toolbar item on its own shared capsule — the new chrome — which is the
        // pill the reference does not have. Hiding it leaves the label itself, flat, which is what the
        // picture shows: a sort label and, in the action colour, "New Item".
        .sharedBackgroundVisibility(.hidden)
    }

    /// The browser's own controls, minus the ones a trashed item replaces.
    ///
    /// `list-column-header` requires the create menu to be **absent from the view tree** in Trash
    /// rather than merely disabled, because the ⌘N shortcut rides in a hidden companion button inside
    /// the menu item — hide the item and the shortcut goes with it. The requirement was written when
    /// this item lived on the content column, where the `List` swapped for `TrashView` and the item
    /// was declared beside it; it has been unconditional since. Extracted into a builder because an
    /// `if` written straight into the toolbar closure is enough to exceed the type checker on this
    /// view — the same reason `trashToolbarItems` exists.
    @ToolbarContentBuilder
    private var browserToolbarItems: some ToolbarContent {
        sortOrderToolbarItem
        if viewModel.sidebarSelection != .trash {
            newItemToolbarItem
        }
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
    private var newItemToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(ItemType.allCases) { type in
                    Button {
                        viewModel.createItemType = type
                    } label: {
                        Label(type.displayName, systemImage: type.sfSymbol)
                    }
                }
            } label: {
                // Same reason as the sort control: a `Label` here renders as a bare plus.
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L("New Item"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Foreground.action)
            }
            // `.borderlessButton`, not `.button`: the latter draws the label in a button's own chrome,
            // and in a macOS 26 toolbar that chrome is the rounded capsule the reference does not have.
            // `.buttonStyle(.plain)` was already applied when the capsule was still drawn, so the
            // chrome comes from the menu style, not from the button style.
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
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
        .sharedBackgroundVisibility(.hidden)
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
            trashToolbarItems
            // Everything after a flexible spacer is drawn against the window's trailing edge, and
            // this is the only arrangement that does it. Measured in a window-sized probe of the
            // three-column split: the same items declared on the content column land inside that
            // column's span; on the split view itself (or with `placement: .primaryAction`, or as a
            // `.primaryAction` group) they pack in behind the sidebar toggle. `placement` has no
            // effect inside a column — the column owns the position — so the trailing edge has to be
            // reached by pushing with a spacer from the column that is already last.
            ToolbarSpacer(.flexible)
            browserToolbarItems
        }
    }

    /// The verification-codes sheet's content, extracted from the modifier chain.
    ///
    /// A view body of this size is one expression to the type checker, and an inline closure here was
    /// enough to push it past what the checker will do — reporting, unhelpfully, that some unrelated
    /// toolbar button could not be type-checked.
    @ViewBuilder
    private var verificationCodesSheet: some View {
        if let makeVerificationCodesViewModel {
            VerificationCodesSheet(
                makeViewModel: makeVerificationCodesViewModel,
                onDismiss: { viewModel.isShowingVerificationCodes = false }
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
                            showVerificationCodes: { viewModel.isShowingVerificationCodes = true }
                        )
                    )
                    // The refresh control rides with the state it refreshes, at the end of the sidebar's
                    // status row, rather than sitting in the titlebar beside the sort control.
                    SyncStatusView(
                        label:           viewModel.syncStatusLabel,
                        isSyncing:       viewModel.isSyncing,
                        hasSynced:       viewModel.lastSyncedAt != nil,
                        unreadableCount: viewModel.unreadableItemCount,
                        onSync:          { viewModel.performManualSync() }
                    )
                }
                // The vault search field, in the sidebar column.
                //
                // Moved here from the detail column: searching and choosing *where* to search belong
                // in one place, and the sidebar is the column that says where. Only the placement
                // changed — the binding, the focused state, the ⌘F activation and the global-search
                // rules are the ones that were already here and tested.
                //
                // No gear button beside it: the approved reference's strip holds nothing between the
                // traffic lights and the sidebar toggle. Settings remains in the app menu (⌘,).
                .searchable(
                    text: $viewModel.searchQuery,
                    isPresented: $isSearchFieldFocused,
                    placement: .sidebar,
                    prompt: "Search vault"
                )
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
                    if viewModel.sidebarSelection == .trash {
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
                viewModel.activateGlobalSearch()
                isSearchFieldFocused = true
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
        // Verification codes. A sheet, and built here rather than held, so the rows' timers exist only
        // while it is up.
        .sheet(isPresented: $viewModel.isShowingVerificationCodes) { verificationCodesSheet }
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
