import AppKit
import Combine
import Foundation
import os.log

// MARK: - VaultBrowserViewModel

/// ViewModel for the three-pane vault browser (User Story 3).
///
/// Responsibilities:
///   - Manages sidebar selection and item list content
///   - Runs in-memory search filter in real time (FR-012)
///   - Provides clipboard copy with 30-second auto-clear (FR-011, SC-004)
///   - Surfaces the last-synced timestamp for the toolbar (FR-037, FR-041)
///   - Tracks and dismisses the sync error banner (FR-049)
@MainActor
final class VaultBrowserViewModel: ObservableObject {

    // MARK: - Published state

    @Published var sidebarSelection: SidebarSelection = .allItems {
        didSet {
            if oldValue != sidebarSelection {
                if isGlobalSearch { deactivateGlobalSearch(restoreSelection: false) }
                Task { @MainActor [weak self] in
                    self?.itemSelection = nil
                    self?.refreshItems()
                }
            }
        }
    }

    @Published var itemSelection: VaultItem? {
        didSet {
            guard oldValue?.id != itemSelection?.id else { return }
            // A reveal belongs to the item on screen. Leaving it set would unmask the *next*
            // item's password because an unrelated one was revealed first — which is the same
            // bug as a grant that is not scoped per item, one level up.
            revealedItemIds = []
        }
    }

    @Published var searchQuery:   String = "" {
        didSet { Task { @MainActor in refreshItems() } }
    }

    /// When true, search queries are scoped to `.allItems` regardless of sidebar selection.
    @Published private(set) var isGlobalSearch: Bool = false

    /// The sidebar selection that was active before global search was activated.
    private(set) var previousSelection: SidebarSelection?

    @Published private(set) var displayedItems: [VaultItem] = []
    @Published private(set) var itemCounts: [SidebarSelection: Int] = [:]
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var organizations: [Organization] = []
    @Published private(set) var collections: [OrgCollection] = []

    var selectedFolderId: String? {
        if case .folder(let id) = sidebarSelection { return id }
        return nil
    }

    /// Non-nil when the active sidebar selection is a specific collection.
    /// Used to pre-fill the collection picker when creating items from a collection context (task 5.9).
    var selectedCollectionId: String? {
        if case .collection(let id) = sidebarSelection { return id }
        return nil
    }
    @Published private(set) var lastSyncedAt: Date?
    @Published var syncErrorMessage: String? = nil

    /// Where the vault currently on screen came from.
    ///
    /// `.cache` is the offline case: the server could not be reached and what is displayed is a copy
    /// of the last payload that was fetched. The label has to say so — a vault that looks live and
    /// is not is the failure this distinction exists to prevent.
    @Published private(set) var syncSource: SyncSource = .server

    /// How many of the vault's items the last sync could not read.
    ///
    /// Surfaced rather than logged. These items are missing from the list with nothing else to
    /// distinguish them from items the user never saved, and "my password isn't here" has a very
    /// different meaning depending on which it is.
    @Published private(set) var unreadableItemCount: Int = 0

    /// When the displayed data was written by the server.
    ///
    /// Equal to `lastSyncedAt` after a live sync, and older than it after a cache read, where it is
    /// the only honest answer to "how old is what I am looking at".
    private(set) var payloadTimestamp: Date?

    /// `true` while a manual sync is in flight. Drives the toolbar button's disabled state and its
    /// progress indicator, and gates ⌘R.
    ///
    /// Distinct from `SyncRepositoryImpl.isSyncing`, which protects the actor. This one protects
    /// the button: without it the user could queue a second sync that the repository would then
    /// reject with `SyncError.syncInProgress`.
    ///
    /// Shared with the background refresh rather than duplicated for it. A second flag would mean
    /// two ways to be syncing and one guard checking the wrong one — precisely the defect
    /// `SyncError.syncInProgress` exists to prevent.
    @Published private(set) var isSyncing: Bool = false

    /// `true` while a write the user asked for is in flight — a delete, restore, duplicate,
    /// favourite toggle, move, or empty-trash.
    ///
    /// A background refresh must not land in the middle of one. Completing a sync replaces the item
    /// list and re-reads the selected item from the store, so a refresh arriving between a write and
    /// the store's update would leave the list disagreeing with the server — and the next sync would
    /// not necessarily repair it.
    ///
    /// A counter, not a flag: two overlapping writes are possible (`performSoftDelete` on a second
    /// item while the first is still in flight), and the first to finish must not clear the state
    /// the second still needs. Counted rather than `@Published` because the only reader asks at tick
    /// time, not reactively.
    var isMutating: Bool { mutationCount > 0 }
    private var mutationCount = 0

    /// Order the item list is displayed in. Persisted, so it survives relaunch.
    ///
    /// Applied here rather than in the repository because the repository's per-selection indexes
    /// are pre-sorted at `populate()` time and must stay free of display preferences — see
    /// `ItemSortOrder`.
    @Published var sortOrder: ItemSortOrder {
        didSet {
            guard oldValue != sortOrder else { return }
            ItemSortPreference.save(sortOrder, to: userDefaults)
            refreshItems()
        }
    }

    /// Reflects whether the edit sheet is currently open. Used by `MenuBarViewModel`
    /// to enable/disable the Edit and Save menu bar actions.
    @Published private(set) var editSheetOpen: Bool = false

    // MARK: - Published state (trash actions)

    /// Set when a delete, restore, or empty-trash operation fails.
    /// The Presentation layer surfaces this as an alert.
    @Published var actionError: String? = nil

    /// Set to a non-nil `ItemType` to present the create sheet for that type.
    /// Automatically cleared if the user switches to Trash.
    @Published var createItemType: ItemType? = nil {
        didSet {
            if sidebarSelection == .trash { createItemType = nil }
        }
    }

    // MARK: - Published state (backup)

    /// The export/import surface currently presented, or nil.
    @Published var backupSheet: VaultBackupSheet? = nil

    // MARK: - Published state (master-password re-prompt)

    /// Items whose secrets are currently shown in the detail pane.
    ///
    /// Held here rather than inside `MaskedFieldView` because the reveal has to survive the view
    /// being rebuilt, and has to be clearable from outside it when the selection changes. A
    /// `@State` inside the field view cannot do either.
    @Published private(set) var revealedItemIds: Set<String> = []

    /// The re-prompt request on screen, or nil when the sheet is closed.
    @Published var pendingReprompt: PendingReprompt?

    /// Non-nil when the last submitted master password was wrong, or when the check could not be
    /// made at all. Shown inside the sheet.
    @Published private(set) var repromptError: String? = nil

    /// `true` while a submitted password is being checked.
    @Published private(set) var isVerifyingReprompt: Bool = false

    /// Runs once the master password checks out for the pending request.
    ///
    /// A closure rather than a stored value: a one-time code generated when the sheet opened is
    /// stale by the time the password has been typed, so the thing that must be deferred is the
    /// *action*, not its result.
    private var repromptContinuation: (@MainActor () -> Void)?

    // MARK: - Dependencies

    private let vault:                  any VaultRepository
    private let search:                 any SearchVaultUseCase
    private let deleteUseCase:          any DeleteVaultItemUseCase
    private let permanentDeleteUseCase: any PermanentDeleteVaultItemUseCase
    private let restoreUseCase:         any RestoreVaultItemUseCase
    private let duplicateUseCase:       any DuplicateVaultItemUseCase
    private let emptyTrashUseCase:      any EmptyTrashUseCase
    private let syncUseCase:            any SyncUseCase
    private let createFolderUseCase:      any CreateFolderUseCase
    private let renameFolderUseCase:      any RenameFolderUseCase
    private let deleteFolderUseCase:      any DeleteFolderUseCase
    private let moveItemUseCase:          any MoveItemToFolderUseCase
    private let createCollectionUseCase:  any CreateCollectionUseCase
    private let renameCollectionUseCase:  any RenameCollectionUseCase
    private let deleteCollectionUseCase:  any DeleteCollectionUseCase
    private var syncTimestamp:          any SyncTimestampRepository
    private var getLastSyncDate:        any GetLastSyncDateUseCase
    private let exportUseCase:          any ExportVaultUseCase
    private let importUseCase:          any ImportVaultUseCase
    private let verifyMasterPassword:   any VerifyMasterPasswordUseCase

    /// The re-prompt gate. Set by `RootViewModel`, which owns the grants; see `RepromptGating`.
    ///
    /// Weak because `RootViewModel` owns this object, and a strong reference back would make the
    /// pair a cycle that neither `deinit` nor a lock could break.
    weak var repromptGate: (any RepromptGating)?

    /// Writes exported bytes to a user-chosen location.
    ///
    /// Returns `nil` when the user cancelled the save panel, and **throws** when the write itself
    /// failed. The two are kept apart on purpose: cancelling is a decision and must produce no
    /// error, while a failed write must produce one — a silent failure here would leave the user
    /// believing they have a backup they do not have.
    ///
    /// A closure rather than a call to `NSSavePanel` here, for the reason `AttachmentRowViewModel`
    /// already uses the same seam: the Presentation layer must not import AppKit (Constitution §II),
    /// and a view model that pops a modal panel cannot be unit-tested.
    private let fileSaver:  @MainActor (String, Data) throws -> URL?

    /// Asks the user for a file to import, returning nil if they cancelled. Same reasoning as
    /// `fileSaver`.
    private let filePicker: @MainActor () -> URL?

    /// The running import, so dismissing the sheet can stop it.
    private var importTask: Task<Void, Never>?

    /// Identifies the session this view model is showing.
    ///
    /// A sync that returns after the session ended must not write into the UI: the user locked, and
    /// the unlock screen would otherwise be repopulated by the sync they cancelled by locking.
    ///
    /// Defaults to a private epoch rather than being required, so a test that never locks does not
    /// have to thread one through. `AppContainer` is the only production construction site and
    /// passes the shared instance — a private one there would make every sync look stale the moment
    /// a real lock happened, which is a failure the tests below would not catch.
    private let sessionEpoch: SessionEpoch

    /// Set by `clearSessionState()`, cleared when a new session's data arrives.
    ///
    /// The teardown must be the *last* word, and several of the properties it clears have observers
    /// that start work: assigning `searchQuery` kicks off `refreshItems()`, and that refresh reads
    /// from the vault store. Whether the list came back therefore depended on the caller having
    /// already emptied the store — correct today, and exactly the kind of ordering-by-luck this
    /// change exists to remove. A refresh that runs while this is set is dropped instead.
    private var sessionStateCleared = false

    /// The domain this view model's user preferences are read from and written to. `.standard` in
    /// the app; a private suite in a test.
    private let userDefaults: UserDefaults

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "VaultBrowserViewModel")

    // MARK: - Menu bar action relay

    /// Incremented each time the "Item > Edit" menu bar action fires (spec §9.3).
    /// `ItemDetailView` uses `.onChange(of: editTrigger)` to open the edit sheet.
    /// An integer counter (rather than a Combine PassthroughSubject) keeps the relay
    /// within the async/await pattern mandated by CLAUDE.md.
    @Published private(set) var editTrigger: Int = 0

    /// Incremented each time the "Item > Save" menu bar action fires (spec §9.4).
    /// `ItemDetailView` uses `.onChange(of: saveTrigger)` to call `save()`.
    @Published private(set) var saveTrigger: Int = 0

    func triggerEdit() { editTrigger += 1 }
    func triggerSave() { saveTrigger += 1 }

    // MARK: - Sync label refresh timer

    /// Fires every 60 seconds to re-evaluate the relative sync label while the app is open.
    /// Invalidated in `deinit` to prevent the timer outliving the ViewModel.
    // nonisolated(unsafe) is required because deinit is always nonisolated in Swift 6,
    // and Timer is non-Sendable. The timer is only mutated on MainActor, so this is safe.
    nonisolated(unsafe) private var labelRefreshTimer: Timer?

    /// Relative label derived from `lastSyncedAt`, refreshed every 60 seconds.
    @Published private(set) var syncStatusLabel: String = "Never synced"

    // MARK: - Clipboard auto-clear

    private var clipboardClearTask: Task<Void, Never>?

    /// Whether a clipboard clear is currently pending.
    ///
    /// Read-only, and exposed for tests. "Never" must schedule *nothing* rather than a very long
    /// timer, and the two are indistinguishable from the outside within any test's lifetime — which
    /// is precisely the promise the setting makes. Asking whether a task exists is the only honest
    /// way to assert it.
    var isClipboardClearPending: Bool { clipboardClearTask != nil }

    // MARK: - Init

    init(
        vault:             any VaultRepository,
        search:            any SearchVaultUseCase,
        delete:            any DeleteVaultItemUseCase,
        permanentDelete:   any PermanentDeleteVaultItemUseCase,
        restore:           any RestoreVaultItemUseCase,
        duplicate:         any DuplicateVaultItemUseCase,
        emptyTrash:        any EmptyTrashUseCase,
        sync:              any SyncUseCase,
        createFolder:      any CreateFolderUseCase,
        renameFolder:      any RenameFolderUseCase,
        deleteFolder:      any DeleteFolderUseCase,
        moveItem:          any MoveItemToFolderUseCase,
        createCollection:  any CreateCollectionUseCase,
        renameCollection:  any RenameCollectionUseCase,
        deleteCollection:  any DeleteCollectionUseCase,
        syncTimestamp:     any SyncTimestampRepository,
        getLastSyncDate:   any GetLastSyncDateUseCase,
        export:            any ExportVaultUseCase,
        importVault:       any ImportVaultUseCase,
        verifyMasterPassword: any VerifyMasterPasswordUseCase,
        fileSaver:         @escaping @MainActor (String, Data) throws -> URL?,
        filePicker:        @escaping @MainActor () -> URL?,
        sessionEpoch:      SessionEpoch = SessionEpoch(),
        /// The domain this view model's user preferences live in — the sort order, and the clipboard
        /// clear interval it reads when copying.
        ///
        /// Defaulted so the app is unchanged, and injectable so a test can use a domain of its own.
        /// Without one, suites running in **parallel processes** share the real preference domain:
        /// one suite deletes the key another has just written, which made a sort test fail at random.
        /// `ItemSortPreference` and `ClipboardClearInterval` both already took a domain for exactly
        /// this reason; this type was the straggler. See
        /// `openspec/changes/fix-test-preference-isolation/`.
        userDefaults: UserDefaults = .standard
    ) {
        self.vault                  = vault
        self.search                 = search
        self.deleteUseCase          = delete
        self.permanentDeleteUseCase = permanentDelete
        self.restoreUseCase         = restore
        self.duplicateUseCase       = duplicate
        self.emptyTrashUseCase      = emptyTrash
        self.syncUseCase            = sync
        self.createFolderUseCase    = createFolder
        self.renameFolderUseCase    = renameFolder
        self.deleteFolderUseCase    = deleteFolder
        self.moveItemUseCase        = moveItem
        self.createCollectionUseCase = createCollection
        self.renameCollectionUseCase = renameCollection
        self.deleteCollectionUseCase = deleteCollection
        self.syncTimestamp          = syncTimestamp
        self.getLastSyncDate        = getLastSyncDate
        self.exportUseCase          = export
        self.importUseCase          = importVault
        self.verifyMasterPassword   = verifyMasterPassword
        self.fileSaver              = fileSaver
        self.filePicker             = filePicker
        self.sessionEpoch           = sessionEpoch
        self.userDefaults           = userDefaults
        self.sortOrder              = ItemSortPreference.load(from: userDefaults)
        refreshItems()
        refreshCounts()
        refreshFolders()
        refreshOrganizations()
        lastSyncedAt    = getLastSyncDate.execute()
        refreshSyncStatusLabel()
        startLabelRefreshTimer()
    }

    deinit {
        labelRefreshTimer?.invalidate()
        clipboardClearTask?.cancel()
        importTask?.cancel()
    }

    // MARK: - Timer

    private func startLabelRefreshTimer() {
        // Re-evaluate the relative label every 60 seconds so "2 minutes ago" stays accurate
        // without requiring a view reload. The timer is weak-captured to avoid a retain cycle.
        labelRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshSyncStatusLabel()
            }
        }
    }

    /// Recomputes `syncStatusLabel` from the current provenance.
    ///
    /// One function rather than one expression per call site: the 60-second tick, the initial load,
    /// the account re-scope and the sync completion all have to agree on whether the vault on screen
    /// is live, and the offline branch is the one that must not be lost by whichever of them runs
    /// last. The no-op guard is kept from the timer's original body so a ticking clock does not
    /// re-render the sidebar once a minute for no reason — the label is recomputed from provenance on
    /// every call, so the guard can only suppress a write that would have changed nothing.
    private func refreshSyncStatusLabel() {
        let updated: String
        switch syncSource {
        case .server:
            updated = lastSyncedAt.syncStatusLabel()
        case .cache:
            updated = OfflineSyncLabel.make(payloadTimestamp: payloadTimestamp)
        }
        if syncStatusLabel != updated { syncStatusLabel = updated }
    }

    // MARK: - Actions

    /// Activates global search mode: stores the current sidebar selection and sets the flag.
    func activateGlobalSearch() {
        guard !isGlobalSearch else { return }
        previousSelection = sidebarSelection
        isGlobalSearch = true
        refreshItems()
    }

    /// Deactivates global search mode: restores the previous sidebar selection and clears the query.
    /// - Parameter restoreSelection: When `true` (default), restores the sidebar selection
    ///   that was active before global search. Pass `false` when the caller already set a new selection.
    func deactivateGlobalSearch(restoreSelection: Bool = true) {
        guard isGlobalSearch else { return }
        let saved = previousSelection
        isGlobalSearch = false
        previousSelection = nil
        if restoreSelection, let previous = saved {
            sidebarSelection = previous
        }
        searchQuery = ""
    }

    /// Copies `value` to the pasteboard and schedules a clear after the configured interval
    /// (FR-011, SC-004).
    ///
    /// The interval is read at copy time rather than captured once, so a Settings change applies to
    /// the next copy without a relaunch. "Never" schedules nothing at all — not a very long timer,
    /// which would still depend on the process outliving it.
    func copy(_ value: String) {
        SecretClipboard.shared.write(value)

        // Cancel any previous clear task before scheduling a new one.
        clipboardClearTask?.cancel()
        clipboardClearTask = nil

        guard let seconds = ClipboardClearInterval.load(from: userDefaults).seconds else {
            logger.debug("Clipboard left uncleared (interval is Never)")
            return
        }

        clipboardClearTask = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
                // Only clear if our value is still on the clipboard.
                if SecretClipboard.shared.stillHolds(value) {
                    SecretClipboard.shared.clearIfStillOurs()
                    logger.debug("Clipboard auto-cleared after \(Int(seconds)) s")
                }
            } catch {
                // Task cancelled (e.g. new copy) — do nothing.
            }
        }
    }

    // MARK: - Master-password re-prompt

    /// Runs `action` now, or after the master password has been entered, depending on whether the
    /// item carries re-prompt protection and whether it has already been given.
    ///
    /// The gate is asked rather than `item.reprompt` read directly: whether a prompt is needed is a
    /// function of the grant as well as the flag, and the grant is not this object's to read
    /// (design D7). An item with no gate wired is never gated — a browser view model standing on
    /// its own has no session to protect.
    ///
    /// **The action is deferred, not its result.** A one-time code generated when the sheet opened
    /// is stale by the time a password has been typed, so what has to wait is the work, not the
    /// value it produces.
    /// The master-password gate for one item's secrets.
    ///
    /// Built here rather than in a view so that the detail pane and the verification-codes list cannot
    /// drift on what "gated" means. `.none` for an item the user did not protect: there is nothing to
    /// ask for, and a gate that asks anyway teaches people to click through prompts.
    func revealGate(for item: VaultItem) -> RevealGateBinding {
        guard needsPrompt(for: item) else { return .none }
        return .gated(
            isRevealed:     isRevealed(item.id),
            request:        { [weak self] in self?.toggleReveal(itemId: item.id) },
            requiresPrompt: true,
            copyGated:      { [weak self] value in self?.copyGated(itemId: item.id, value) }
        )
    }

    func performGated(itemId: String, action: @escaping @MainActor () -> Void) {
        let item = displayedItems.first { $0.id == itemId } ?? itemSelection
        guard let item, item.id == itemId, repromptGate?.needsReprompt(for: item) == true else {
            action()
            return
        }
        repromptContinuation = action
        repromptError        = nil
        pendingReprompt      = PendingReprompt(itemId: item.id, itemName: item.name)
    }

    /// Reveals the secrets of `itemId`, asking for the master password first when the item asks.
    func requestReveal(itemId: String) {
        performGated(itemId: itemId) { [weak self] in
            self?.revealedItemIds.insert(itemId)
        }
    }

    /// Whether asking to reveal `item` will actually prompt.
    ///
    /// False for an item without the flag and for one whose master password has already been given
    /// this session. A view uses this to describe the gate honestly rather than promising a prompt
    /// that will not come.
    func needsPrompt(for item: VaultItem) -> Bool {
        repromptGate?.needsReprompt(for: item) == true
    }

    /// Copies `value` once the gate has been satisfied.
    ///
    /// Exists because tapping a field row copies it (FR-023), so a protected row's tap has to take
    /// the same route as the Copy Password command. Gating only the menu item would leave the gate
    /// walkable in one click.
    func copyGated(itemId: String, _ value: String) {
        performGated(itemId: itemId) { [weak self] in
            self?.copy(value)
        }
    }

    /// Shows or hides `itemId`'s secrets. This is what the eye button on a gated field calls.
    ///
    /// Hiding never prompts, and hiding does **not** revoke the grant: the master password has
    /// already been given for this item this session, so revealing again must not ask again
    /// (spec: "The grant covers the rest of the session"). The grant dies with the session, in
    /// the lock and sign-out teardowns, not with the eyeball.
    func toggleReveal(itemId: String) {
        guard revealedItemIds.contains(itemId) else {
            requestReveal(itemId: itemId)
            return
        }
        revealedItemIds.remove(itemId)
    }

    /// Whether `itemId`'s secrets are currently unmasked.
    func isRevealed(_ itemId: String) -> Bool {
        revealedItemIds.contains(itemId)
    }

    /// Checks `password` and, if it is the master password, runs what the request was for.
    ///
    /// A wrong password is not thrown and does not close the sheet: the spec asks for an error and
    /// for the prompt to remain open, and closing on a wrong answer would be indistinguishable
    /// from a cancel — the user would not know which happened.
    func submitReprompt(_ password: Data) {
        guard let pending = pendingReprompt else { return }
        isVerifyingReprompt = true
        repromptError       = nil
        let useCase = verifyMasterPassword

        Task { @MainActor [weak self] in
            guard let self else { return }
            // A local copy so these bytes can be zeroed here; the caller zeroes its own. Capturing
            // the parameter directly would be a mutable capture in concurrently-executing code.
            var buffer = password
            defer {
                buffer.zeroize()
                isVerifyingReprompt = false
            }
            do {
                let matched = try await useCase.execute(buffer)
                guard matched else {
                    repromptError = L("That is not the master password for this account.")
                    return
                }
                repromptGate?.grantReprompt(for: pending.itemId)
                let continuation = repromptContinuation
                pendingReprompt      = nil
                repromptContinuation = nil
                repromptError        = nil
                continuation?()
            } catch {
                // "Could not check" is shown, not swallowed. A sheet that stays open with no
                // message is indistinguishable from one that is broken.
                repromptError = error.localizedDescription
            }
        }
    }

    /// Drops every reveal and closes any open re-prompt request.
    ///
    /// Called from the lock and sign-out teardowns. A reveal is a decision made under a grant, and
    /// both die with the session — leaving one behind would show a password after the vault has
    /// been locked, with no prompt to account for it.
    func discardReveals() {
        revealedItemIds = []
        cancelReprompt()
    }

    /// Closes the sheet having granted nothing.
    ///
    /// Dropping the continuation without running it is what makes cancelling safe: nothing is
    /// revealed and nothing reaches the clipboard (spec: "Cancelling grants nothing").
    func cancelReprompt() {
        pendingReprompt      = nil
        repromptContinuation = nil
        repromptError        = nil
    }

    /// Dismisses the sync error banner (FR-049).
    func dismissSyncError() {
        syncErrorMessage = nil
    }

    // MARK: - Refresh

    /// Refreshes `displayedItems` from the vault store based on current selection + search query.
    /// Executes the vault read on the actor executor via a fire-and-forget `Task`.
    func refreshItems() {
        guard !sessionStateCleared else { return }
        Task { [weak self] in
            guard let self, !sessionStateCleared else { return }
            do {
                let scope: SidebarSelection
                if isGlobalSearch {
                    if case .folder = sidebarSelection { scope = sidebarSelection }
                    else { scope = .allItems }
                } else {
                    scope = sidebarSelection
                }
                displayedItems = sortOrder.sort(try await search.execute(query: searchQuery, in: scope))
            } catch {
                logger.error("Failed to load vault items: \(error.localizedDescription, privacy: .public)")
                displayedItems = []
            }
        }
    }

    /// Selects the item with the given id, moving the list to a scope that contains it.
    ///
    /// Used by the health report, which runs over the whole vault and can therefore name an item the
    /// current sidebar scope excludes. Selecting an item the list does not contain leaves the detail
    /// pane empty, so the scope has to move first.
    ///
    /// The selection is taken from `displayedItems` once the item arrives there rather than from a
    /// separately-fetched copy: `List`'s selection is compared by value, and two `VaultItem` values
    /// for the same cipher are not necessarily equal.
    func selectItem(id: String) {
        sidebarSelection = .allItems

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Assigning `sidebarSelection` clears `itemSelection` and refreshes on a later turn, so
            // this waits for the item to reach the list rather than racing that turn.
            for _ in 0..<50 {
                if let match = displayedItems.first(where: { $0.id == id }) {
                    itemSelection = match
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            logger.error("Item \(id.prefix(8), privacy: .public) never reached the list after selection")
        }
    }

    /// Re-reads the currently selected item from the vault store and updates `itemSelection`.
    ///
    /// Called after a successful attachment upload so the detail pane reflects the new
    /// attachment list without requiring a full vault sync. Safe to call on cancel — if
    /// the item hasn't changed the assignment is a no-op.
    func refreshItemSelection() {
        guard !sessionStateCleared else { return }
        guard let currentId = itemSelection?.id else { return }
        Task { [weak self] in
            guard let self, !sessionStateCleared else { return }
            guard let updated = try? await vault.allItems().first(where: { $0.id == currentId }) else { return }
            itemSelection = updated
        }
    }

    /// Refreshes sidebar item counts from the vault store.
    func refreshCounts() {
        guard !sessionStateCleared else { return }
        Task { [weak self] in
            guard let self, !sessionStateCleared else { return }
            do {
                itemCounts = try await vault.itemCounts()
            } catch {
                logger.error("Failed to load item counts: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Re-scopes the sync timestamp repository to a newly resolved account email.
    ///
    /// Called by `RootViewModel` immediately after a login or unlock transition to `.vault`,
    /// before `handleSyncCompleted` — ensures the timestamp is written to and read from
    /// the correct per-account UserDefaults key even on first launch (when the email was
    /// not yet known at `AppContainer.init()` time).
    func updateSyncTimestamp(
        repository: any SyncTimestampRepository,
        useCase:    any GetLastSyncDateUseCase
    ) {
        self.syncTimestamp   = repository
        self.getLastSyncDate = useCase
        // Reload the persisted timestamp from the now-correct account-scoped key.
        lastSyncedAt = useCase.execute()
        refreshSyncStatusLabel()
    }

    /// Called after a sync returns to update counts, items, timestamp and provenance.
    ///
    /// A live sync persists the timestamp via `SyncTimestampRepository` so it survives app restarts.
    /// A cache-sourced one deliberately does **not**: nothing was synced, and writing "now" would
    /// tell the next launch the vault had been fetched when the network was gone. The label carries
    /// the payload's own age instead, which is the fact the user needs.
    ///
    /// Error paths MUST NOT call this method — the stored timestamp reflects the last *successful*
    /// server sync.
    func handleSyncCompleted(_ result: SyncResult) {
        // A new session's data has arrived, so the refreshes below are wanted again.
        sessionStateCleared = false
        syncSource       = result.source
        unreadableItemCount = result.failedDecryptionCount
        payloadTimestamp = result.payloadTimestamp
        if result.source == .server {
            lastSyncedAt = result.syncedAt
            syncTimestamp.recordSuccessfulSync()
        }
        refreshSyncStatusLabel()
        refreshItems()
        refreshCounts()
        refreshFolders()
        refreshOrganizations()
        // Re-read the selected item from the vault store so its attachment list
        // reflects the latest sync data. Without this, itemSelection can be a
        // stale copy (e.g. from before a cipher-key fix that silently dropped
        // attachments), and the detail pane would show "No attachments" even
        // after a sync that correctly mapped them.
        refreshItemSelection()
        syncErrorMessage = nil
    }

    /// Called when the vault screen is entered by a flow that produced no sync result — the
    /// credentials were accepted and the vault could not then be fetched.
    ///
    /// It refreshes everything `handleSyncCompleted` does and touches no timestamp, because there is
    /// nothing to record: the last successful sync is still whatever it was. Reporting `Date()` here
    /// was the previous behaviour, and it told the user their vault was current at the moment they
    /// were least able to check.
    func handleVaultEnteredWithoutSync() {
        sessionStateCleared = false
        refreshItems()
        refreshCounts()
        refreshFolders()
        refreshOrganizations()
        refreshItemSelection()
    }

    /// Called when a sync fails mid-session (FR-049).
    func handleSyncError(_ message: String) {
        syncErrorMessage = message
    }

    /// Called by `ItemDetailView` when the edit sheet opens or closes.
    func handleEditSheetState(_ open: Bool) {
        editSheetOpen = open
    }

    /// Called after a successful item edit save to refresh the list pane and detail pane.
    ///
    /// Updates `itemSelection` so the detail pane reflects the saved values, then
    /// refreshes the item list and sidebar counts so any name change appears immediately.
    func handleItemSaved(_ updatedItem: VaultItem) {
        itemSelection = updatedItem
        refreshItems()
        refreshCounts()
    }

    // MARK: - Mutation tracking

    /// Marks a user-requested write as started. Every `beginMutation()` needs a matching
    /// `endMutation()`, on the failure path as much as the success one: a count left standing
    /// disables the background refresh for the rest of the session.
    ///
    /// A save through the edit sheet does not come through here — that sheet's whole lifetime is
    /// already reported by `editSheetOpen`, which the background decision checks first.
    private func beginMutation() { mutationCount += 1 }

    private func endMutation() { mutationCount = max(0, mutationCount - 1) }

    // MARK: - Toggle Favorite

    func toggleFavorite(item: VaultItem) {
        Task {
            beginMutation()
            defer { endMutation() }
            var draft = DraftVaultItem(item)
            draft.isFavorite.toggle()
            do {
                let updated = try await vault.update(draft)
                handleItemSaved(updated)
            } catch {
                logger.error("Toggle favorite failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Delete / Restore / Empty Trash

    /// Soft-deletes `id`, moving it to Trash.
    ///
    /// On success refreshes the active list and sidebar counts. If the deleted item was
    /// selected in the detail pane, it is deselected so the empty-state appears.
    /// Errors are surfaced via `actionError` for the Presentation layer to show as an alert.
    func performSoftDelete(id: String) async {
        beginMutation()
        defer { endMutation() }
        do {
            try await deleteUseCase.execute(id: id)
            logger.info("Item soft-deleted: \(id, privacy: .public)")
            if itemSelection?.id == id {
                let idx = displayedItems.firstIndex(where: { $0.id == id })
                refreshItems()
                if let idx {
                    itemSelection = displayedItems.indices.contains(idx) ? displayedItems[idx]
                        : displayedItems.indices.contains(idx - 1) ? displayedItems[idx - 1]
                        : nil
                } else {
                    itemSelection = nil
                }
            } else {
                refreshItems()
            }
            refreshCounts()
        } catch {
            logger.error("Soft-delete failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Restores the trashed item with `id` to the active vault.
    ///
    /// On success refreshes the list and sidebar counts. If the restored item was selected
    /// in the detail pane, deselects it (it has moved to the active vault).
    func performRestore(id: String) async {
        beginMutation()
        defer { endMutation() }
        do {
            try await restoreUseCase.execute(id: id)
            logger.info("Item restored: \(id, privacy: .public)")
            if itemSelection?.id == id { itemSelection = nil }
            refreshItems()
            refreshCounts()
        } catch {
            logger.error("Restore failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Permanently deletes the trashed item with `id`.
    ///
    /// The item must already be in Trash (`isDeleted == true`). Calls `DELETE /ciphers/{id}`
    /// via `PermanentDeleteVaultItemUseCase`, which permanently removes the cipher from the server.
    /// The caller is responsible for showing a confirmation alert before invoking this method.
    func performPermanentDelete(id: String) async {
        beginMutation()
        defer { endMutation() }
        do {
            try await permanentDeleteUseCase.execute(id: id)
            logger.info("Item permanently deleted: \(id, privacy: .public)")
            if itemSelection?.id == id { itemSelection = nil }
            refreshItems()
            refreshCounts()
        } catch {
            logger.error("Permanent delete failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    // MARK: - Sync

    /// What prompted a sync. The only thing it changes is what happens when the sync *fails*.
    enum SyncOrigin {
        /// The user pressed ⌘R or the toolbar button.
        case manual
        /// A background tick. Nobody asked for it, so nobody is told it failed.
        case background
    }

    /// Runs a vault sync on demand and folds the outcome into the same state the automatic sync
    /// uses, so a manual sync cannot drift from the login-time one.
    ///
    /// Re-entrancy is guarded here as well as in the UI. `SyncRepositoryImpl` also refuses a
    /// concurrent sync, which covers the race between this button and a login-time sync — that
    /// refusal surfaces as the ordinary error banner rather than as two syncs racing.
    func performManualSync() {
        performSync(origin: .manual)
    }

    /// Refreshes the vault because a background tick decided it was due.
    ///
    /// Deliberately not a second implementation: it shares `performSync(origin:)` and therefore the
    /// in-flight guard, so a tick landing during a manual sync is refused rather than queued. The
    /// caller has already established that the vault is unlocked and the session is not mid-edit —
    /// see `BackgroundSyncMonitor.shouldSync(trigger:isUnlocked:isBusy:lastSuccessfulSyncAt:)`.
    func backgroundSync() {
        performSync(origin: .background)
    }

    private func performSync(origin: SyncOrigin) {
        guard !isSyncing else { return }
        // Captured synchronously, before the task is created. Reading it inside the task would leave
        // a gap between deciding to sync and recording which session that was for — and a lock
        // landing in that gap would hand this sync the *new* session's token.
        let epochToken = sessionEpoch.current()
        isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                // Progress messages are not surfaced: the toolbar already shows a spinner, and the
                // messages are sub-second for a small vault.
                let result = try await syncUseCase.execute(progress: { _ in })

                guard sessionEpoch.isCurrent(epochToken) else {
                    // The user locked while this was in flight. Applying it would repopulate the
                    // unlock screen, and reporting it would tell them their locked vault failed.
                    logger.info("\(origin == .manual ? "Manual" : "Background", privacy: .public) sync discarded: the session ended while it was in flight")
                    return
                }

                logger.info("\(origin == .manual ? "Manual" : "Background", privacy: .public) sync completed: \(result.totalCiphers) ciphers, \(result.failedDecryptionCount) failed, source=\(String(describing: result.source), privacy: .public)")
                handleSyncCompleted(result)
            } catch {
                // A sync refused because its session ended is not a failure — it is the correct
                // outcome of a race the teardown won, so it is not reported and not logged as one.
                if case SyncError.sessionEnded = error { return }

                switch origin {
                case .manual:
                    logger.error("Manual sync failed: \(error.localizedDescription, privacy: .public)")
                    // `handleSyncError` deliberately does not touch the timestamp: it must keep
                    // reflecting the last *successful* sync.
                    handleSyncError(error.localizedDescription)

                case .background:
                    // Logged and left at that. A dismissable banner for a sync the user did not ask
                    // for would appear every interval to anyone working offline, and the same banner
                    // is how a *manual* failure is reported — becoming noise would cost it that.
                    // What the user sees instead is the last-sync label ageing, which is true and
                    // needs no dismissal.
                    logger.error("Background sync failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Session teardown

    /// Drops everything this view model holds that came out of the vault in plaintext.
    ///
    /// Locking zeroes the keys and empties the store, but neither reaches the copies kept here: the
    /// decrypted item list, the selection, and the folder, organisation and collection names all
    /// survive it — and so does `RootViewModel.selectedLogin`, which is derived from the selection
    /// and is what keeps the copy commands enabled on the unlock screen.
    ///
    /// One method, called from both `lockVault()` and `signOut()`, for the reason the offline cache
    /// is deleted inside `signOut()` rather than by its callers: two call sites each clearing what
    /// they remember is how the two sign-out paths drifted before. A property added here is cleared
    /// on both paths by construction.
    func clearSessionState() {
        // First, so the refreshes that the assignments below trigger are dropped rather than
        // repopulating the list from a store the caller may not have emptied yet.
        sessionStateCleared = true
        // The item list and the selection are the bulk of it — `VaultItem` fields are plain
        // `String`s, decrypted at sync time and never re-encrypted.
        itemSelection            = nil
        displayedItems           = []
        itemCounts               = [:]
        // Decrypted names, same reasoning.
        folders                  = []
        organizations            = []
        collections              = []
        // What the user searched a password manager for is frequently the secret itself.
        searchQuery              = ""
        isGlobalSearch           = false
        // Reveals and re-prompt state are permissions to show material that is now gone.
        discardReveals()
        pendingReprompt          = nil
        repromptContinuation     = nil
        repromptError            = nil
        isVerifyingReprompt      = false
        // The count describes this session's vault, so it goes with the rest of it.
        unreadableItemCount      = 0
        // Error strings can quote the server or the item.
        syncErrorMessage         = nil
        actionError              = nil
        // Sheets that would open onto an empty vault.
        createItemType           = nil
        backupSheet              = nil
    }

    // MARK: - Duplicate

    /// Duplicates the item with `id` and selects the copy.
    ///
    /// Selecting the copy rather than the original is what makes the action useful — the reason to
    /// duplicate is almost always to then edit the copy.
    func duplicateItem(id: String) {
        Task {
            beginMutation()
            defer { endMutation() }
            do {
                let copy = try await duplicateUseCase.execute(id: id)
                logger.info("Item duplicated: \(id, privacy: .public) → \(copy.id, privacy: .public)")
                refreshItems()
                refreshCounts()
                itemSelection = copy
            } catch {
                logger.error("Duplicate failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: - Empty Trash

    /// Permanently deletes every item in Trash.
    ///
    /// Failures are reported rather than thrown: emptying Trash is a sequence of independent
    /// requests, and the user needs to know how much was actually removed. See `EmptyTrashResult`.
    func performEmptyTrash() async {
        beginMutation()
        defer { endMutation() }
        let result = await emptyTrashUseCase.execute()
        logger.info("Empty Trash: \(result.deletedCount) deleted, \(result.failedCount) failed")

        refreshItems()
        refreshCounts()

        if result.hadFailures {
            actionError = L("%d of %d items could not be deleted. They are still in Trash.",
                            result.failedCount, result.deletedCount + result.failedCount)
        }

        // Deselect only if the selected item is genuinely gone. Re-reading Trash rather than
        // assuming: on a partial failure the selected item may well still be there, and clearing
        // the detail pane would be a lie.
        if let selectedId = itemSelection?.id, itemSelection?.isDeleted == true {
            let remaining = (try? await vault.items(for: .trash))?.map(\.id) ?? []
            if !remaining.contains(selectedId) { itemSelection = nil }
        }
    }

    // MARK: - Backup (export / import)

    /// Opens the export consent sheet.
    ///
    /// Nothing is written until `confirmExport()` runs, and that only happens from the sheet's own
    /// confirm button. The consent is mandatory, not decorative — Bitwarden's normative security
    /// requirements make it a precondition of any vault export.
    /// Which plaintext format the next export writes. A presentation choice, so it lives here rather
    /// than in the use case; kept across openings because a user who wants CSV usually wants it again.
    @Published var exportFormat: VaultExportFormat = .json

    /// Whether the verification-codes sheet is up.
    @Published var isShowingVerificationCodes = false

    func requestExport() {
        guard backupSheet == nil else { return }
        backupSheet = .exportConsent
    }

    /// Runs the export and writes the file, after the user has confirmed the consent sheet.
    func confirmExport() {
        Task {
            do {
                let export = try await exportUseCase.execute(format: exportFormat)

                // A cancelled save panel returns nil. That is a decision, not a failure: the
                // sheet closes and no error is shown, because the user just said no.
                guard let url = try fileSaver(export.suggestedFilename, export.data) else {
                    backupSheet = nil
                    return
                }

                logger.info("Export written: \(export.itemCount, privacy: .public) items")
                backupSheet = .exportDone(
                    url: url,
                    itemCount: export.itemCount,
                    organisationItemCount: export.organisationItemCount,
                    omittedItemCount: export.omittedItemCount
                )
            } catch {
                logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
                backupSheet = nil
                actionError = error.localizedDescription
            }
        }
    }

    /// Asks for a file and imports it.
    ///
    /// The read happens off the main actor: an export of a large vault is tens of megabytes, and
    /// blocking the UI on `Data(contentsOf:)` while a progress sheet is supposed to be animating
    /// would be the one place this feature could look broken.
    ///
    /// **The file is sized before it is read.** `Data(contentsOf:)` allocates the whole file in one
    /// step, so picking the wrong file — a database dump, an archive, a device image — meant the app
    /// committed its entire size to memory before anything got round to rejecting it. The size comes
    /// from the file's metadata, not from reading it.
    func requestImport() {
        guard backupSheet == nil else { return }
        guard let url = filePicker() else { return }

        if let rejection = importFileRejection(for: url) {
            logger.error("Import refused for \(url.lastPathComponent, privacy: .private)")
            actionError = rejection
            return
        }

        backupSheet = .importing(done: 0, total: 0)
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                // The detached read is the one step that cannot be interrupted — `Data(contentsOf:)`
                // never checks the task's cancellation flag, and dismissing the sheet therefore has
                // to wait for it. Checking again here covers the case where the user dismissed it
                // while the read was queued, so the sheet is not reopened behind them and the rest of
                // the run does not start at all.
                if Task.isCancelled { return }

                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url)
                }.value

                if Task.isCancelled { return }

                let summary = try await importUseCase.execute(data: data) { done, total in
                    Task { @MainActor [weak self] in
                        self?.updateImportProgress(done: done, total: total)
                    }
                }

                // The list is refreshed even for a cancelled import: everything created before the
                // cancellation is really in the vault, and the browser has to show it.
                refreshItems()
                refreshCounts()
                refreshFolders()

                // Only show the report if the sheet is still the one that started this run.
                //
                // A cancelled import returns a partial summary rather than throwing — by design, so
                // the caller learns what landed — so without this guard, dismissing the progress
                // sheet would immediately re-present it as a report. Closing a window the user just
                // closed is the one thing a dismissal must never do.
                guard backupSheet?.isImporting == true else { return }
                backupSheet = .importReport(summary)
            } catch {
                logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
                backupSheet = nil
                actionError = error.localizedDescription
            }
        }
    }

    /// Closes the backup sheet. Cancels a running import first, so dismissing the progress sheet
    /// stops the run rather than leaving it creating items behind a closed window.
    func dismissBackupSheet() {
        importTask?.cancel()
        importTask = nil
        backupSheet = nil
    }

    // MARK: - Import preflight

    /// The largest export this app will read, in bytes.
    ///
    /// A Bitwarden JSON export of ten thousand items is single-digit megabytes, so 64 MB sits two
    /// orders of magnitude above anything a real vault reaches. The number is not a claim about what
    /// a vault can hold — it is the point past which the file almost certainly is not a vault export,
    /// and reading it would allocate its whole size to find that out.
    private enum ImportLimits {
        static let maximumFileBytes: Int64 = 64 * 1024 * 1024
    }

    /// Why this file will not be imported, or `nil` to go ahead.
    ///
    /// Reads the file's attributes rather than its contents — the whole point is not to read it. A
    /// size that cannot be determined is allowed through: the failure mode being prevented is a
    /// mistaken file selection, not a hostile one, and refusing a legitimate export because a
    /// sandboxed volume declined to report a length would be the worse trade.
    private func importFileRejection(for url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            logger.debug("Import preflight: file size unavailable, proceeding")
            return nil
        }
        guard Int64(size) > ImportLimits.maximumFileBytes else { return nil }

        func megabytes(_ bytes: Int64) -> String {
            String(format: "%.1f", Double(bytes) / 1_048_576)
        }
        return L("That file is too large to import: %@ MB. Vitrine imports exports up to %@ MB.",
                 megabytes(Int64(size)),
                 megabytes(ImportLimits.maximumFileBytes))
    }

    private func updateImportProgress(done: Int, total: Int) {
        // Guarded so a late callback cannot resurrect the sheet after the user dismissed it.
        guard case .importing = backupSheet else { return }
        backupSheet = .importing(done: done, total: total)
    }

    // MARK: - Folder CRUD

    func createFolder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                _ = try await createFolderUseCase.execute(name: trimmed)
                refreshFolders()
                refreshCounts()
            } catch {
                logger.error("Create folder failed: \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

    func renameFolder(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                _ = try await renameFolderUseCase.execute(id: id, name: trimmed)
                refreshFolders()
            } catch {
                logger.error("Rename folder failed: \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

    func deleteFolder(id: String) {
        Task {
            do {
                let wasSelected = if case .folder(let fid) = sidebarSelection { fid == id } else { false }
                try await deleteFolderUseCase.execute(id: id)
                if wasSelected { sidebarSelection = .allItems }
                refreshFolders()
                refreshItems()
                refreshCounts()
            } catch {
                logger.error("Delete folder failed: \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

    func moveItemsToFolder(itemIds: [String], folderId: String) {
        Task {
            beginMutation()
            defer { endMutation() }
            do {
                if itemIds.count == 1, let id = itemIds.first {
                    try await moveItemUseCase.execute(itemId: id, folderId: folderId)
                } else {
                    try await moveItemUseCase.execute(itemIds: itemIds, folderId: folderId)
                }
                refreshItems()
                refreshCounts()
            } catch {
                logger.error("Move to folder failed: \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: - Refresh

    func refreshFolders() {
        guard !sessionStateCleared else { return }
        Task { [weak self] in
            guard let self, !sessionStateCleared else { return }
            do {
                folders = try await vault.folders()
            } catch {
                logger.error("Failed to load folders: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func refreshOrganizations() {
        guard !sessionStateCleared else { return }
        Task { [weak self] in
            guard let self, !sessionStateCleared else { return }
            do {
                organizations = try await vault.organizations()
                collections   = try await vault.collections()
            } catch {
                logger.error("Failed to load organizations: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Collection CRUD

    func createCollection(name: String, organizationId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                _ = try await createCollectionUseCase.execute(name: trimmed, organizationId: organizationId)
                refreshOrganizations()
                refreshCounts()
            } catch {
                logger.error("Create collection failed: \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

    func renameCollection(id: String, organizationId: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                _ = try await renameCollectionUseCase.execute(collectionId: id, name: trimmed,
                                                               organizationId: organizationId)
                refreshOrganizations()
                refreshCounts()
            } catch {
                logger.error("Rename collection failed: \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

    func deleteCollection(id: String, organizationId: String) {
        Task {
            do {
                let wasSelected = if case .collection(let cid) = sidebarSelection { cid == id } else { false }
                try await deleteCollectionUseCase.execute(collectionId: id, organizationId: organizationId)
                if wasSelected { sidebarSelection = .allItems }
                refreshOrganizations()
                refreshCounts()
            } catch {
                logger.error("Delete collection failed: \(error.localizedDescription, privacy: .public)")
                actionError = error.localizedDescription
            }
        }
    }

}
