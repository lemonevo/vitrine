//
//  PrizmApp.swift
//  Prizm
//
//  Created by Benjamin on 15.03.26.
//

import AppKit
import Combine
import SwiftUI
import os.log

@main
struct PrizmApp: App {

    @StateObject private var container: AppContainer
    @StateObject private var rootVM:    RootViewModel
    @StateObject private var localization = LocalizationManager.shared
    @State       private var optionKeyMonitor = OptionKeyMonitor()

    // Used by the About menu item to open the custom About window scene.
    @Environment(\.openWindow) private var openWindow

    init() {
        // No application appearance is set here, on purpose: the app follows the device, light or dark.
        // Everything the window draws is appearance-aware — the foreground and surface tokens resolve
        // through `NSColor(name:)` closures and the card fill carries both appearances — so pinning an
        // appearance here would only ever cost the user the one they chose.

        // Install the Bundle.main override before anything can resolve a string.
        // `@StateObject` would create the manager lazily on first body access, which
        // happens to be early enough today — this makes the ordering explicit rather
        // than incidental.
        _ = LocalizationManager.shared

        let c = AppContainer()
        _container = StateObject(wrappedValue: c)
        _rootVM    = StateObject(wrappedValue: RootViewModel(container: c))
        NSApplication.shared.activate()
    }

    /// The locale for date and number formatting. String lookups are handled by
    /// `LocalizationManager`'s `Bundle.main` override — this only aligns formatters.
    private var locale: Locale { Locale(identifier: localization.language) }

    var body: some Scene {
        WindowGroup {
            rootView
                .frame(minWidth: 480, minHeight: 360)
                .environment(optionKeyMonitor)
                .environment(\.locale, locale)
                // Rebuilds the whole hierarchy when the language changes. SwiftUI
                // caches resolved strings inside view values, so without this the
                // bundle would switch but the on-screen text would not.
                .id(localization.language)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // Replace the default "About Vitrine" panel with our custom SwiftUI window.
            CommandGroup(replacing: .appInfo) {
                Button("About Vitrine") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandGroup(after: .appInfo) {
                Button("Sign Out…") {
                    rootVM.confirmSignOut()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
                .disabled(!rootVM.isSignedIn)

                Button("Lock Vault") {
                    rootVM.lockVault()
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!rootVM.isVaultUnlocked)
            }

            // View menu — "Sync Now" lives here rather than in the Item menu because it acts on the
            // whole vault, not on the selected item. ⌘R matches the refresh shortcut users expect.
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Sync Now") {
                    rootVM.vaultBrowserVM.performManualSync()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!rootVM.menuBarCanSync)
            }

            // File menu — vault-wide data operations, in the group macOS puts Save/Save As in.
            //
            // The enablement reads `isVaultUnlocked`, a computed property over the @Published
            // `screen`. That is deliberately *not* a separate `@Published` flag mirroring the
            // screen: the phase 1 ⌘R defect was a mirrored flag whose only update site never fired
            // at launch, leaving the command permanently disabled. A property derived from the
            // source of truth cannot go stale.
            CommandGroup(after: .saveItem) {
                Divider()

                Button("Export Vault…") {
                    rootVM.vaultBrowserVM.requestExport()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!rootVM.isVaultUnlocked)

                Button("Import Vault…") {
                    rootVM.vaultBrowserVM.requestImport()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!rootVM.isVaultUnlocked)
            }

            // "Item" menu — sits in the standard macOS menu bar next to Edit/View/Window.
            // Edit opens the edit sheet for the selected vault item (⌘E).
            // Save persists in-flight edits (⌘S).
            // Duplicate creates a copy of the selected item (⌘D).
            // Buttons are disabled by `rootVM` Combine subscriptions that track
            // item selection and edit-sheet state.
            CommandMenu("Item") {
                Button("Edit") {
                    rootVM.vaultBrowserVM.triggerEdit()
                }
                .disabled(!rootVM.menuBarCanEdit)
                .keyboardShortcut("e", modifiers: .command)

                Button("Save") {
                    rootVM.vaultBrowserVM.triggerSave()
                }
                .disabled(!rootVM.menuBarCanSave)
                .keyboardShortcut("s", modifiers: .command)

                Button("Duplicate") {
                    rootVM.duplicateSelectedItem()
                }
                .disabled(!rootVM.menuBarCanDuplicate)
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Copy Username") {
                    rootVM.copySelectedField(.username)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!rootVM.selectedFieldAvailable(.username))

                Button("Copy Password") {
                    rootVM.copySelectedField(.password)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!rootVM.selectedFieldAvailable(.password))

                Button("Copy Code") {
                    rootVM.copySelectedField(.totp)
                }
                .keyboardShortcut("c", modifiers: [.command, .control])
                .disabled(!rootVM.selectedFieldAvailable(.totp))

                Button("Copy Website") {
                    rootVM.copySelectedField(.website)
                }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(!rootVM.selectedFieldAvailable(.website))
            }

            // "Tools" menu — vault-wide analysis. It is not in the Item menu because it reports on
            // every item, not on the selection, and it is not in File because it writes nothing.
            // ⌘⇧H reads as "health"; plain ⌘H is Hide, so the modifier keeps them apart.
            CommandMenu("Tools") {
                Button("Vault Health Report…") {
                    rootVM.presentHealthReport()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!rootVM.menuBarCanRunHealthReport)
            }
        }

        // Custom About window — opened via Prizm → About Prizm.
        // hiddenTitleBar: AboutView provides its own header with the app icon and name,
        // so the system title bar would be redundant.
        // contentSize resizability: window sizes to AboutView's fixed 380pt width; no
        // free resize since the content is a fixed-layout info panel.
        Window("About Vitrine", id: "about") {
            AboutView()
                .environment(\.locale, locale)
                .id(localization.language)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings window — opened via ⌘, (macOS convention) or the gear at the trailing end of the
        // sidebar's status row. The Settings scene does not inherit the WindowGroup environment, so
        // we pass the container explicitly via .environmentObject().
        Settings {
            SettingsView(
                authRepository:      container.authRepository,
                serverTrustStore:    container.serverTrustStore,
                serverHost:          container.authRepository.storedAccount()?.serverEnvironment.base.host,
                pickCertificateFile: { AppContainer.defaultCertificateOpenPanel() },
                loadCertificates:    { try CertificateImporter.certificates(at: $0) },
                loadFingerprint:     { try? await container.getAccountFingerprintUseCase.execute() },
                sshAgent:            container.sshAgentCoordinator
            )
            .environment(\.locale, locale)
                .id(localization.language)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch rootVM.screen {
        case .login:
            LoginView(viewModel: rootVM.loginVM)

        case .loading:
            ProgressView("Signing in…")
                .frame(minWidth: 480, minHeight: 360)

        case .twoFactorPrompt(let provider):
            TwoFactorPromptView(viewModel: rootVM.loginVM, provider: provider)

        case .unlock:
            if let unlockVM = rootVM.unlockVM {
                UnlockView(viewModel: unlockVM)
            }

        case .syncing(let message):
            SyncProgressView(message: message)

        case .vault:
            VaultBrowserView(
                viewModel:         rootVM.vaultBrowserVM,
                faviconLoader:     container.faviconLoader,
                makeEditViewModel: { [vaultBrowserVM = rootVM.vaultBrowserVM] item in
                    let vm = container.makeItemEditViewModel(
                        for: item,
                        folders: vaultBrowserVM.folders,
                        organizations: vaultBrowserVM.organizations,
                        collections: vaultBrowserVM.collections
                    )
                    // Wire the list-pane refresh callback to the shared VaultBrowserViewModel.
                    vm.onSaveSuccess = { [weak vaultBrowserVM] updatedItem in
                        vaultBrowserVM?.handleItemSaved(updatedItem)
                    }
                    return vm
                },
                makeCreateViewModel: { [vaultBrowserVM = rootVM.vaultBrowserVM] type, contextId in
                    // contextId is either a folderId (personal item) or collectionId (org item),
                    // determined by whether the current sidebar selection is a collection.
                    let cols = vaultBrowserVM.collections
                    let isCollection = contextId != nil && cols.contains(where: { $0.id == contextId })
                    let vm: ItemEditViewModel
                    if isCollection {
                        vm = container.makeItemCreateViewModel(
                            for: type, collectionId: contextId,
                            folders: vaultBrowserVM.folders, organizations: vaultBrowserVM.organizations, collections: cols
                        )
                    } else {
                        vm = container.makeItemCreateViewModel(
                            for: type, folderId: contextId,
                            folders: vaultBrowserVM.folders, organizations: vaultBrowserVM.organizations, collections: cols
                        )
                    }
                    vm.onSaveSuccess = { [weak vaultBrowserVM] item in
                        vaultBrowserVM?.handleItemSaved(item)
                    }
                    return vm
                },
                makeAddAttachmentViewModel: { cipherId in
                    container.makeAddAttachmentViewModel(for: cipherId)
                },
                makeBatchAttachmentViewModel: { cipherId in
                    container.makeBatchAttachmentViewModel(for: cipherId)
                },
                makeAttachmentRowViewModel: { cipherId, attachment in
                    container.makeAttachmentRowViewModel(cipherId: cipherId, attachment: attachment)
                },
                makePasswordHistoryViewModel: { itemId in
                    container.makePasswordHistoryViewModel(itemId: itemId)
                },
                makePasskeysViewModel: { itemId in
                    container.makePasskeysViewModel(itemId: itemId)
                },
                makeTOTPCodeViewModel: { itemId, secret in
                    container.makeTOTPCodeViewModel(itemId: itemId, secret: secret)
                },
                makeVerificationCodesViewModel: { [vaultBrowserVM = rootVM.vaultBrowserVM] in
                    container.makeVerificationCodesViewModel(browser: vaultBrowserVM)
                },
                totpGenerator: container.totpGenerator
            )
            // Installed here rather than on the app's root: the generator only exists inside the
            // vault, and a value generated before unlock is not something that can happen.
            .environment(\.generatorHistory, container.generatorHistory)
            // The report is owned by `rootVM`, not rebuilt here: see `healthReportVM` for why a
            // view model created in a sheet's content closure would re-run the analysis forever.
            .sheet(isPresented: Binding(
                get: { rootVM.healthReportVM != nil },
                set: { if !$0 { rootVM.dismissHealthReport() } }
            )) {
                if let vm = rootVM.healthReportVM {
                    HealthReportView(
                        viewModel: vm,
                        onSelect:  { rootVM.openItemFromHealthReport(id: $0) },
                        onDismiss: { rootVM.dismissHealthReport() }
                    )
                }
            }
            // The SSH agent's prompt. Presented at the app's root rather than inside the browser
            // because the request arrives on a socket, from a process the user did not just click
            // on: it has to be able to appear whatever the vault browser is showing, and it has to
            // disappear by itself when a lock revokes what is waiting.
            .sheet(isPresented: Binding(
                get: { rootVM.sshAgentAuthorizer.pending != nil },
                set: { presented in if !presented { rootVM.sshAgentAuthorizer.cancel() } }
            )) {
                SSHAgentAuthorizationSheet(authorizer: rootVM.sshAgentAuthorizer)
            }
        }
    }
}

// MARK: - RootViewModel

/// Dependencies required by `RootViewModel` — extracted for testability.
@MainActor
protocol RootViewModelDependencies: AnyObject {
    var authRepo: any AuthRepository { get }
    var vaultRepo: any VaultRepository { get }
    /// The per-cipher attachment key cache. Cleared on vault lock alongside the vault store.
    var vaultKeyCache: VaultKeyCache { get }
    /// The per-organisation symmetric key cache. Cleared on vault lock alongside the vault store.
    var orgKeyCache: OrgKeyCache { get }
    /// The account's own public key. Cleared on lock and sign-out with the rest, so the fingerprint
    /// phrase is not still on screen for a vault the user has just closed.
    var accountKeyCache: AccountKeyCache { get }
    /// Derives the one-time code for `Item ▸ Copy Code`. Injected rather than constructed here so
    /// the crypto stays in the Data layer and the generator stays testable.
    var totpGenerator: any TOTPGenerator { get }
    func makeLoginViewModel() -> LoginViewModel
    func makeUnlockViewModel(account: Account) -> UnlockViewModel
    func makeVaultBrowserViewModel() -> VaultBrowserViewModel
    /// Creates the verification-codes list. A factory rather than a stored instance because the rows own
    /// one timer each, and they must be built when the sheet opens and released when it closes.
    @MainActor
    func makeVerificationCodesViewModel(browser: VaultBrowserViewModel) -> VerificationCodesViewModel
    /// Creates the health report view model. A factory rather than a stored instance because the
    /// report is per-presentation: each time the sheet opens it runs the checks again, and a cached
    /// report would show the vault as it was the first time.
    func makeHealthReportViewModel() -> HealthReportViewModel
    /// Returns a fresh sync timestamp repository and use case scoped to the given email.
    /// Called after login/unlock to re-scope to the correct account before the first sync.
    func makeSyncTimestampDependencies(for email: String) -> (repository: any SyncTimestampRepository, useCase: any GetLastSyncDateUseCase)
    /// Points the favicon loader at the signed-in account's icon service. Called at the vault
    /// transition, once the account's server URL is known; before that nothing is fetched.
    func refreshWebsiteIcons() async
    /// Idle-timeout observation. Injected so `RootViewModel` can be tested without installing a
    /// real `NSEvent` monitor, which is the one part of the feature a unit test cannot exercise.
    var idleMonitor: any VaultIdleMonitoring { get }
    /// Periodic vault refresh while unlocked, and on reactivation or wake. Injected for the same
    /// reason as `idleMonitor`: the timer and the notification observers are not test material, but
    /// the wiring that starts and stops them is.
    var backgroundSyncMonitor: any BackgroundSyncMonitoring { get }
    /// The session's generator history. Cleared on lock and sign-out so a value that was generated
    /// but never saved cannot outlive the session that produced it (design D9).
    var generatorHistory: GeneratorHistory { get }
    /// The master-password gate for SSH signatures. Shared rather than owned by the agent, because
    /// its grants have to die in the same teardown as the reprompt grants — and because the sheet
    /// that answers it is presented by the app, not by the agent.
    var sshAgentAuthorizer: SSHAgentAuthorizer { get }
    /// The SSH agent itself. Driven from here rather than observed by the coordinator, because the
    /// screen is the only thing that knows when the vault became usable, and the coordinator has no
    /// business knowing about screens.
    var sshAgentCoordinator: SSHAgentCoordinator { get }
    /// The identity of the current unlocked session. Advanced on lock and on sign-out, so that a
    /// sync still in flight cannot write into a session that has ended.
    var sessionEpoch: SessionEpoch { get }
}

extension AppContainer: RootViewModelDependencies {
    var authRepo: any AuthRepository { authRepository }
    var vaultRepo: any VaultRepository { vaultStore }
}

/// Top-level state machine that decides which screen to show.
///
/// On launch: checks for a stored session via `AuthRepository.storedAccount()`.
/// - Session found → `UnlockView` (User Story 2)
/// - No session    → `LoginView`  (User Story 1)
@MainActor
final class RootViewModel: ObservableObject, RepromptGating {

    enum Screen {
        case login
        case loading
        case twoFactorPrompt(TwoFactorProvider)
        case unlock
        case syncing(message: String)
        case vault
    }

    @Published var screen: Screen

    // MARK: - "Item" menu state

    /// Whether the Edit command should be enabled: an item is selected and the edit sheet is closed.
    @Published private(set) var menuBarCanEdit: Bool = false

    /// Whether the Save command should be enabled: the edit sheet is currently open.
    @Published private(set) var menuBarCanSave: Bool = false

    /// Whether the Duplicate command should be enabled: an item is selected, it is not in Trash,
    /// and no edit sheet is open (duplicating mid-edit would race the in-flight draft).
    @Published private(set) var menuBarCanDuplicate: Bool = false

    /// Whether "Sync Now" should be enabled: the vault is unlocked and no sync is in flight.
    @Published private(set) var menuBarCanSync: Bool = false

    /// The login content of the currently selected item, or nil. Drives copy command disabled state.
    @Published private(set) var selectedLogin: LoginContent?

    // MARK: - Health report state

    /// The health report sheet, or nil while it is closed.
    ///
    /// Held here rather than created inside the sheet's content closure. SwiftUI re-evaluates that
    /// closure whenever this object publishes, so a view model built inside it would be replaced —
    /// and reset to `.loading` — on every update, re-running the analysis in a loop.
    ///
    /// It also holds decrypted item names, so it is dropped on lock and sign-out alongside the
    /// generator history.
    @Published private(set) var healthReportVM: HealthReportViewModel?

    // MARK: - Re-prompt grants

    /// Item ids whose master password has been entered since this unlock.
    ///
    /// Cleared by `lockVault()` and `signOut()` in the same teardown that clears the vault store
    /// and every key cache. A grant is permission to show material those caches protect, so it must
    /// not be able to outlive them (design D7).
    ///
    /// Scoped per item and for the rest of the unlock session, rather than per disclosure or for a
    /// short window: "this item was unlocked at this point in the session" is something the user
    /// can reason about, where a thirty-second timer is not.
    @Published private(set) var repromptGrants: Set<String> = []

    /// Whether showing or copying a secret of `item` requires the master password first.
    ///
    /// An item that does not carry the flag never asks, and an item whose password has already been
    /// given this session does not ask again — both halves of that are in one expression so there
    /// is no second place where a grant could be forgotten.
    func needsReprompt(for item: VaultItem) -> Bool {
        item.reprompt != 0 && !repromptGrants.contains(item.id)
    }

    /// Records that the master password was entered correctly for `itemId`.
    func grantReprompt(for itemId: String) {
        repromptGrants.insert(itemId)
    }

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "RootViewModel")

    let loginVM:          LoginViewModel
    @Published var unlockVM: UnlockViewModel?
    let vaultBrowserVM:   VaultBrowserViewModel

    private let container: any RootViewModelDependencies
    /// The SSH agent's master-password gate. Held here so the lock and sign-out teardowns have one
    /// call to make; the agent reaches it through the same instance.
    let sshAgentAuthorizer: SSHAgentAuthorizer
    /// The agent whose socket follows the vault's lock state. Held here so the vault transitions
    /// start and stop it; the switch that turns it on lives in Settings, and the coordinator
    /// reconciles the two.
    let sshAgentCoordinator: SSHAgentCoordinator
    /// Drives the configurable idle timeout. Started only while the vault is unlocked.
    private let idleMonitor: any VaultIdleMonitoring
    /// Refreshes the vault on a timer, and when the app or the machine comes back. Started and
    /// stopped by the same transition as `idleMonitor`, so the two cannot get out of step.
    private let backgroundSyncMonitor: any BackgroundSyncMonitoring
    /// The identity of the current session. Advanced as the *first* step of both teardowns, so a
    /// sync completing while they run already sees that its session is over.
    private let sessionEpoch: SessionEpoch
    /// Combine subscriptions — held for the lifetime of this object.
    /// Using Combine (not SwiftUI .onChange) so transitions fire regardless
    /// of whether the source view is currently in the view hierarchy.
    private var cancellables = Set<AnyCancellable>()
    /// System notification observers for auto-lock (sleep, screensaver, screen lock).
    nonisolated(unsafe) private var sleepObserver: NSObjectProtocol?
    nonisolated(unsafe) private var screensaverObserver: NSObjectProtocol?
    nonisolated(unsafe) private var screenLockObserver: NSObjectProtocol?

    init(container: any RootViewModelDependencies) {
        self.container      = container
        self.loginVM        = container.makeLoginViewModel()
        self.vaultBrowserVM = container.makeVaultBrowserViewModel()
        self.idleMonitor    = container.idleMonitor
        self.backgroundSyncMonitor = container.backgroundSyncMonitor
        self.sessionEpoch    = container.sessionEpoch
        self.sshAgentAuthorizer  = container.sshAgentAuthorizer
        self.sshAgentCoordinator = container.sshAgentCoordinator

        // Check for stored session at launch.
        if let account = container.authRepo.storedAccount() {
            self.screen   = .unlock
            self.unlockVM = container.makeUnlockViewModel(account: account)
        } else {
            self.screen   = .login
            self.unlockVM = nil
        }

        // Route the timeout into the same teardown paths the sleep / screensaver / screen-lock
        // locks use, so the idle timeout introduces no third way to destroy or retain key material.
        idleMonitor.onTimeout = { [weak self] action in
            self?.handleIdleTimeout(action)
        }

        // A tick is only a *fact* that the interval elapsed or the app came back; whether that means
        // "sync now" is decided here, where the session's state is known.
        backgroundSyncMonitor.onTick = { [weak self] trigger in
            self?.handleBackgroundTick(trigger)
        }

        // The browser presents the re-prompt sheet and holds the reveal state, but must not be
        // able to issue the grant it is asking for. Wiring it here rather than at the call site
        // means no sheet can be shown without a gate behind it (design D7).
        vaultBrowserVM.repromptGate = self

        subscribeToFlowStates()
    }

    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let screensaverObserver { DistributedNotificationCenter.default().removeObserver(screensaverObserver) }
        if let screenLockObserver { DistributedNotificationCenter.default().removeObserver(screenLockObserver) }
    }

    // MARK: - Combine subscriptions

    private func subscribeToFlowStates() {
        // Idle-timeout observation follows the unlocked state exactly. Driving it from `screen`
        // rather than from each transition site means a new transition cannot forget to start or
        // stop the monitor, and it is the same predicate as `isVaultUnlocked`.
        //
        // `menuBarCanSync` is recomputed here for the same reason. It depends on both halves —
        // unlocked *and* not syncing — but the `isSyncing` publisher below only emits when a sync
        // starts or finishes. Observing it alone would leave ⌘R disabled from launch until the
        // first sync, and the shortcut is one of the ways to start one: the command could never
        // enable itself.
        $screen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                guard let self else { return }
                self.updateSessionMonitoring(for: screen)
                self.menuBarCanSync = self.isVaultUnlocked && !self.vaultBrowserVM.isSyncing
            }
            .store(in: &cancellables)

        // Login flow — observe for the lifetime of the app (loginVM is never replaced).
        loginVM.$flowState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleLoginFlow(state) }
            .store(in: &cancellables)

        // Unlock flow — re-subscribe whenever unlockVM is assigned.
        $unlockVM
            .compactMap { $0 }
            .flatMap { $0.$flowState }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleUnlockFlow(state) }
            .store(in: &cancellables)

        // canEdit: item selected AND edit sheet not yet open.
        // canSave: edit sheet is open.
        // canDuplicate: item selected, not trashed, and no edit sheet open.
        // All three are derived by watching editSheetOpen and itemSelection independently.
        // `for await` on @Published.values avoids Combine callbacks.
        Task { [weak self, vaultBrowserVM] in
            for await open in vaultBrowserVM.$editSheetOpen.values {
                guard let self else { break }
                self.menuBarCanSave = open
                self.menuBarCanEdit = vaultBrowserVM.itemSelection != nil && !open
                self.menuBarCanDuplicate = vaultBrowserVM.itemSelection.map { !$0.isDeleted && !open } ?? false
            }
        }
        Task { [weak self, vaultBrowserVM] in
            for await selection in vaultBrowserVM.$itemSelection.values {
                guard let self else { break }
                self.menuBarCanEdit = selection != nil && !vaultBrowserVM.editSheetOpen
                self.menuBarCanDuplicate = (selection.map { !$0.isDeleted } ?? false)
                    && !vaultBrowserVM.editSheetOpen
                if case .login(let login) = selection?.content {
                    self.selectedLogin = login
                } else {
                    self.selectedLogin = nil
                }
            }
        }
        // Sync Now is enabled only while the vault is unlocked and no sync is already running.
        Task { [weak self, vaultBrowserVM] in
            for await syncing in vaultBrowserVM.$isSyncing.values {
                guard let self else { break }
                self.menuBarCanSync = self.isVaultUnlocked && !syncing
            }
        }

        // Auto-lock on Mac sleep.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.lockVault() } }

        // Auto-lock on screensaver start.
        screensaverObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screensaver.didstart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.lockVault() } }

        // Auto-lock on screen lock (⌃⌘Q / Lock Screen menu).
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.lockVault() } }
    }

    /// Re-scopes the sync timestamp to the current account and records the sync that got us here,
    /// then transitions to the vault screen.
    ///
    /// Called from both `handleLoginFlow` and `handleUnlockFlow` — the vault transition
    /// logic is identical in both flows. `caller` is included in the error log so the
    /// originating flow is identifiable when the account is unexpectedly missing.
    ///
    /// `syncResult` is the outcome of the sync that preceded this transition, and it is the reason
    /// this method takes an argument at all: the timestamp shown to the user has to come from the
    /// data on screen. An earlier version passed `Date()` here, which reported a fresh successful
    /// sync on a launch where the vault had not been fetched at all. `nil` means exactly that — the
    /// fetch did not happen — and is passed through as such rather than filled in.
    private func transitionToVault(caller: String, syncResult: SyncResult?) {
        // Re-scope before recording: on first login the AppContainer was initialised without
        // a known email; this corrects the UserDefaults key before handleSyncCompleted writes to it.
        if let email = container.authRepo.storedAccount()?.email {
            let deps = container.makeSyncTimestampDependencies(for: email)
            vaultBrowserVM.updateSyncTimestamp(repository: deps.repository, useCase: deps.useCase)
        } else {
            // Unexpected: vault transition reached with no stored account — timestamp will
            // be written under the fallback empty-email key. Should not occur in normal flow.
            logger.error("\(caller, privacy: .public)(.vault): no stored account; sync timestamp not re-scoped")
        }
        // The account's server URL is now known, so the favicon loader can be pointed at that
        // server's icon endpoint. Until this runs the loader fetches nothing at all.
        Task { await container.refreshWebsiteIcons() }
        screen = .vault
        // The vault is readable from here on, which is the half of the agent's condition this
        // transition supplies. Started after `screen` so the keys it reads are the ones the vault
        // screen is about to show; a no-op when the user has not switched the agent on.
        sshAgentCoordinator.vaultDidUnlock()
        // Defer handleSyncCompleted to the next run-loop cycle so that the initial
        // VaultBrowserView layout pass (triggered by `screen = .vault` above) commits
        // before any @Published mutations from async vault reads arrive.
        //
        // Root cause: VaultRepositoryImpl is an `actor`, so every refresh Task suspends
        // at a cross-actor hop; the continuations resume on @MainActor asynchronously.
        // If they land while SwiftUI is computing its first layout pass for VaultBrowserView,
        // SwiftUI emits "Publishing changes from within view updates is not allowed" →
        // undefined behaviour → heap corruption → z_ccm_xcma_malloc_freelist EXC_BREAKPOINT.
        //
        // DispatchQueue.main.async (not a Swift Task) is intentional: it guarantees
        // the block runs between run-loop iterations, after the current CATransaction
        // (which drives the SwiftUI layout commit) has flushed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let syncResult {
                    self.vaultBrowserVM.handleSyncCompleted(syncResult)
                } else {
                    self.vaultBrowserVM.handleVaultEnteredWithoutSync()
                }
            }
        }
    }

    func handleLoginFlow(_ state: LoginFlowState) {
        switch state {
        case .login:       screen = .login
        case .loading:     screen = .loading
        case .twoFactorPrompt(let provider):  screen = .twoFactorPrompt(provider)
        case .syncing(let msg): screen = .syncing(message: msg)
        case .vault:       transitionToVault(caller: "handleLoginFlow", syncResult: loginVM.lastSyncResult)
        }
        logger.info("Screen transition → \(String(describing: state))")
    }

    /// Whether the user has an active session (vault or unlock screen).
    var isSignedIn: Bool {
        switch screen {
        case .vault, .unlock, .syncing: return true
        default: return false
        }
    }

    /// Shows a confirmation alert before signing out (FR-014).
    ///
    /// `NSAlert` is built from plain `String`s, so every title has to be resolved
    /// through `L(…)` explicitly — nothing here is picked up by SwiftUI's
    /// `LocalizedStringKey` handling.
    func confirmSignOut() {
        let alert = NSAlert()
        alert.messageText = L("Sign Out")
        // Verified against `AuthRepositoryImpl.signOut()` before this was written, because the sentence
        // it replaces — "All local data will be cleared" — was not true. Sign-out removes the session
        // keys, tokens, the encrypted user key, the KDF params, the remembered 2FA device pair, the
        // PIN's wrapped key material, the biometric key, the cached vault, and then locks. What
        // survives on purpose: UserDefaults preferences, `bw.macos:deviceIdentifier` (an installation
        // identity, shared across accounts — deleting it would make the server see a new device on
        // every login), and the pinned certificate decisions in `KeychainServerTrustStore`, which are
        // per-server and not this session's to revoke.
        alert.informativeText = L(
            "Session keys, tokens and the cached vault are removed from this Mac. Your preferences, this device's identifier and any certificate you have pinned are kept."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Sign Out"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        signOut()
    }

    /// Clears all session data and returns to the login screen.
    func signOut() {
        Task {
            // Before anything else: a sync still in flight must see that its session is over, or it
            // will repopulate the store and the key caches while this teardown is clearing them.
            sessionEpoch.advance()
            do {
                try await container.authRepo.signOut()
            } catch {
                logger.error("Sign-out error: \(error.localizedDescription, privacy: .public)")
            }
            await container.vaultRepo.clearVault()
            await container.vaultKeyCache.clear()
            // Both caches, matching `lockVault()`. Clearing only the vault key here left the
            // unwrapped organisation keys in memory for the rest of the process's life, which is
            // what the plaintext-minimisation rule forbids -- and `AuthRepositoryImpl` holds no
            // cache of its own, so nothing else was clearing them.
            await container.orgKeyCache.clear()
            await container.accountKeyCache.clear()
            container.generatorHistory.clear()
            // The report lists decrypted item names, so it goes with the rest of the session state.
            healthReportVM = nil
            // A grant is permission to show what the key caches protect; it goes with them.
            repromptGrants.removeAll()
            // Same rule for the SSH agent: a signing grant must not survive the session that
            // issued it, and anything waiting on one has to be refused rather than left hanging.
            sshAgentAuthorizer.revokeAll()
            // The socket goes with the keys it signs with. Stopping it also ends any connection
            // still blocked on a prompt — after `revokeAll()` those requests are answered false,
            // so the client sees a refusal rather than a hang.
            sshAgentCoordinator.vaultDidLock()
            // The view model holds its own copy of everything the store just dropped — the item
            // list, the selection, the decrypted folder and organisation names. Leaving it there
            // kept the copy commands enabled on the unlock screen: `selectedLogin` is derived from
            // the selection, and nothing was clearing the selection.
            vaultBrowserVM.clearSessionState()
            unlockVM = nil
            screen   = .login
            logger.info("Sign out completed")
        }
    }

    // MARK: - Lock

    /// Zeros in-memory key material, clears the vault cache, and transitions to the unlock screen.
    /// No-op if the vault is not currently unlocked.
    func lockVault() {
        guard isVaultUnlocked else { return }
        Task {
            // Before anything else, and specifically before the first `await` of the teardown: a
            // sync completing mid-teardown must already see this session as over. Advancing at the
            // end would let a sync land between `clearVault()` and the advance, and repopulate a
            // store that had just been cleared.
            sessionEpoch.advance()
            await container.authRepo.lockVault()
            await container.vaultRepo.clearVault()
            // Clear all key caches in the same lock path as the vault store.
            // Key material must not outlive the vault session.
            await container.vaultKeyCache.clear()
            await container.orgKeyCache.clear()
            await container.accountKeyCache.clear()
            container.generatorHistory.clear()
            healthReportVM = nil
            // Both halves of "the user has already entered the master password for this item" go
            // here: the grant, and the reveals it produced. Leaving the second behind would show a
            // password on the unlock screen's return with no prompt.
            repromptGrants.removeAll()
            // The SSH agent's grants are permission to use key material, so they go with the
            // caches that hold it — and refusing everything still waiting is what stops a `git`
            // from hanging on a prompt that will never be answered.
            sshAgentAuthorizer.revokeAll()
            // The socket goes with the keys it signs with. Stopping it also ends any connection
            // still blocked on a prompt — after `revokeAll()` those requests are answered false,
            // so the client sees a refusal rather than a hang.
            sshAgentCoordinator.vaultDidLock()
            // See `signOut()`: the store is cleared above, and this is the second copy of the same
            // plaintext. Both paths call the same method so a property added later cannot be cleared
            // on one and missed on the other.
            vaultBrowserVM.clearSessionState()
            if let account = container.authRepo.storedAccount() {
                unlockVM = container.makeUnlockViewModel(account: account)
                screen = .unlock
            } else {
                screen = .login
            }
            logger.info("Vault locked")
        }
    }

    /// Whether the vault is currently unlocked (vault browser or sync in progress).
    var isVaultUnlocked: Bool {
        switch screen {
        case .vault, .syncing: return true
        default: return false
        }
    }

    // MARK: - Session monitoring

    /// Starts idle observation and background refresh while the vault is unlocked, and stops both
    /// otherwise.
    ///
    /// A locked vault has nothing to lock and nothing to refresh — and a refresh in particular would
    /// have to keep the user key resident to decrypt the response, which is the state `lockVault()`
    /// exists to destroy. A timer running against the unlock screen would be pure overhead.
    ///
    /// One method for both so a new transition cannot start one and forget the other.
    private func updateSessionMonitoring(for screen: Screen) {
        switch screen {
        case .vault, .syncing:
            idleMonitor.start()
            backgroundSyncMonitor.start()
        case .login, .loading, .twoFactorPrompt(_), .unlock:
            idleMonitor.stop()
            backgroundSyncMonitor.stop()
        }
    }

    /// Decides whether a background tick becomes a sync, and starts one if so.
    private func handleBackgroundTick(_ trigger: BackgroundSyncTrigger) {
        // The monitor is stopped whenever the vault is not unlocked, so this is a second lock on the
        // same door — kept because "never refresh a locked vault" is a security property, and a
        // security property should not rest solely on start/stop having been called correctly.
        guard isVaultUnlocked else { return }

        let vm = vaultBrowserVM
        let allowed = backgroundSyncMonitor.shouldSync(
            trigger:             trigger,
            isUnlocked:          isVaultUnlocked,
            isBusy:              vm.editSheetOpen || vm.isMutating,
            lastSuccessfulSyncAt: vm.lastSyncedAt
        )
        guard allowed else { return }
        vm.backgroundSync()
    }

    /// Applies the configured timeout action.
    ///
    /// Both cases reuse an existing teardown: `lockVault()` clears the vault and every key cache
    /// while keeping the stored session, `signOut()` additionally discards the session. Neither is
    /// new, so the timeout cannot introduce a third, less-audited way to tear down key material.
    func handleIdleTimeout(_ action: VaultTimeoutAction) {
        guard isVaultUnlocked else { return }
        logger.info("Idle timeout elapsed; action = \(action.rawValue, privacy: .public)")
        switch action {
        case .lock:    lockVault()
        case .signOut: signOut()
        }
    }

    func handleUnlockFlow(_ state: UnlockFlowState) {
        switch state {
        case .unlock:       screen = .unlock
        case .loading:      screen = .unlock   // stay on unlock screen with spinner
        case .syncing(let msg): screen = .syncing(message: msg)
        case .vault:        transitionToVault(caller: "handleUnlockFlow", syncResult: unlockVM?.lastSyncResult)
        case .login:
            // "Sign in with a different account" — reset to login.
            unlockVM = nil
            screen   = .login
        }
        logger.info("Screen transition → \(String(describing: state))")
    }

    // MARK: - Duplicate

    /// Duplicates the item selected in the list pane.
    ///
    /// The copy is created on the server and becomes the new selection, so the user can edit it
    /// straight away. Trashed items are excluded — see `menuBarCanDuplicate`.
    func duplicateSelectedItem() {
        guard let id = vaultBrowserVM.itemSelection?.id else { return }
        vaultBrowserVM.duplicateItem(id: id)
    }

    // MARK: - Copy field from selected item

    enum CopyableField {
        case username, password, totp, website

        /// Whether copying this field must be confirmed with the master password when the item
        /// carries re-prompt protection.
        ///
        /// The username is the interesting exclusion. The copy-username command exists precisely
        /// because it is the half that is safe to hand over, so gating it would remove the
        /// command's reason to exist (design D7). The website is not a secret at all.
        var isGated: Bool {
            switch self {
            case .username, .website: return false
            case .password, .totp:    return true
            }
        }
    }

    /// Copies `field` of the selected item, routing the password and the one-time code through the
    /// re-prompt gate.
    ///
    /// The work is deferred rather than the value: `performGated` re-runs
    /// `selectedFieldValue` after a successful prompt, so a one-time code is generated at the
    /// moment it is copied and not when the sheet opened.
    func copySelectedField(_ field: CopyableField) {
        guard let item = vaultBrowserVM.itemSelection, field.isGated else {
            copyFieldValue(field)
            return
        }
        vaultBrowserVM.performGated(itemId: item.id) { [weak self] in
            self?.copyFieldValue(field)
        }
    }

    private func copyFieldValue(_ field: CopyableField) {
        guard let value = selectedFieldValue(field) else { return }
        vaultBrowserVM.copy(value)
    }

    /// Whether the selected item can currently supply `field` to a copy command.
    ///
    /// Requires an unlocked vault, in addition to the selection holding the field. `clearSessionState()`
    /// already clears the selection on lock, which would make this redundant — it is kept because
    /// this is the gate the user actually touches, and "a locked vault yields no secrets" should not
    /// rest on a state-clearing routine having been called correctly at some earlier point.
    func selectedFieldAvailable(_ field: CopyableField) -> Bool {
        guard isVaultUnlocked else { return false }
        return selectedFieldValue(field) != nil
    }

    private func selectedFieldValue(_ field: CopyableField) -> String? {
        guard let login = selectedLogin else { return nil }

        switch field {
        case .username: return login.username
        case .password: return login.password
        // The stored `totp` is the long-lived shared secret, NOT a one-time code. Copying it would
        // hand the recipient a permanent second factor — and the clipboard is globally readable for
        // 30 seconds. Generate the code instead; when the stored value is unusable this returns nil
        // and the menu command stays disabled rather than copying something wrong.
        case .totp:     return container.totpGenerator.code(for: login.totp)
        case .website:  return login.uris.first?.uri
        }
    }

    // MARK: - Health report

    /// Whether the Tools ▸ Vault Health Report command should be enabled.
    ///
    /// Derived from `isVaultUnlocked` rather than mirrored into its own `@Published` flag: the phase 1
    /// ⌘R defect was exactly that pattern, and a derived property cannot go stale.
    var menuBarCanRunHealthReport: Bool { isVaultUnlocked }

    /// Opens the health report. No-op while the vault is locked — there is nothing decrypted to read.
    func presentHealthReport() {
        guard isVaultUnlocked else { return }
        healthReportVM = container.makeHealthReportViewModel()
    }

    func dismissHealthReport() {
        healthReportVM = nil
    }

    /// Closes the report and selects the item it pointed at.
    ///
    /// The order matters: the sheet has to be gone before the vault browser is asked to select,
    /// because `VaultBrowserViewModel.selectItem(id:)` waits for the item to appear in the *filtered*
    /// list, and the selection is only meaningful once the browser is the visible screen.
    func openItemFromHealthReport(id: String) {
        healthReportVM = nil
        vaultBrowserVM.selectItem(id: id)
    }
}
