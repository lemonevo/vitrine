import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// Dependency injection container — wires together all Data-layer implementations
/// and exposes the Domain-layer protocols used by the Presentation layer.
///
/// Created once at app launch and passed down via `@StateObject` / environment.
/// All types are instantiated eagerly; nothing is lazy in Phase 4.
@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Data layer

    let apiClient:     PrizmAPIClientImpl
    let crypto:        PrizmCryptoServiceImpl
    let keychain:      KeychainServiceImpl
    let biometricKeychain: BiometricKeychainServiceImpl
    let vaultStore:    VaultRepositoryImpl
    let faviconLoader: FaviconLoader
    /// Derives one-time codes for `Item ▸ Copy Code`. Stateless — no key material is retained.
    /// Declared as the protocol type (not `TOTPGeneratorImpl`) so it satisfies
    /// `RootViewModelDependencies` directly; Swift has no property covariance for witnesses.
    let totpGenerator: any TOTPGenerator
    /// In-memory cache mapping cipher ID → 64-byte effective key.
    /// Populated at sync time by `SyncRepositoryImpl`; cleared on vault lock alongside
    /// `vaultStore` so key material does not outlive the vault session (Constitution §III).
    let vaultKeyCache: VaultKeyCache
    /// In-memory cache mapping organization ID → unwrapped 64-byte symmetric key.
    /// Populated at sync time; cleared on vault lock alongside `vaultKeyCache` (Constitution §III).
    let orgKeyCache: OrgKeyCache
    /// The account's own RSA public key, SPKI DER, for the fingerprint phrase. Unlike the two
    /// caches above it holds no secret — it is cleared on lock so the phrase disappears with the
    /// session, not because the bytes are sensitive.
    let accountKeyCache: AccountKeyCache

    // MARK: - Domain repositories (Data implementations)

    let authRepository: AuthRepositoryImpl
    let syncRepository: SyncRepositoryImpl

    // MARK: - Domain use cases

    let syncUseCase:                     SyncUseCaseImpl
    let loginUseCase:                    LoginUseCaseImpl
    let unlockUseCase:                   UnlockUseCaseImpl
    let searchVaultUseCase:              SearchVaultUseCaseImpl
    let editVaultItemUseCase:            EditVaultItemUseCaseImpl
    let createVaultItemUseCase:          CreateVaultItemUseCaseImpl
    let duplicateVaultItemUseCase:       DuplicateVaultItemUseCaseImpl
    let emptyTrashUseCase:               EmptyTrashUseCaseImpl
    let deleteVaultItemUseCase:          DeleteVaultItemUseCaseImpl
    let permanentDeleteVaultItemUseCase: PermanentDeleteVaultItemUseCaseImpl
    let restoreVaultItemUseCase:         RestoreVaultItemUseCaseImpl
    let createFolderUseCase:             CreateFolderUseCaseImpl
    let renameFolderUseCase:             RenameFolderUseCaseImpl
    let deleteFolderUseCase:             DeleteFolderUseCaseImpl
    let moveItemToFolderUseCase:         MoveItemToFolderUseCaseImpl
    let createCollectionUseCase:         CreateCollectionUseCaseImpl
    let renameCollectionUseCase:         RenameCollectionUseCaseImpl
    let deleteCollectionUseCase:         DeleteCollectionUseCaseImpl
    let syncTimestampRepository:         SyncTimestampRepositoryImpl
    let getLastSyncDateUseCase:          any GetLastSyncDateUseCase

    // MARK: - Backup use cases

    /// Serialises the vault into Bitwarden's unencrypted JSON format. Returns bytes; never writes.
    let exportVaultUseCase: ExportVaultUseCaseImpl
    /// Creates items from such a file. Additive only — see `ImportVaultUseCase`.
    let importVaultUseCase: ImportVaultUseCaseImpl

    // MARK: - Health report

    /// Runs the five local checks over the decrypted vault. Makes no request of any kind — see
    /// design D6 for why the sixth check every password manager offers is refused.
    let generateVaultHealthReportUseCase: GenerateVaultHealthReportUseCaseImpl
    /// Reads one item's previous passwords, on demand and without keeping them (design D10).
    let getPasswordHistoryUseCase:        GetPasswordHistoryUseCaseImpl
    let getPasskeysUseCase:               GetPasskeysUseCaseImpl
    let verifyMasterPasswordUseCase:      VerifyMasterPasswordUseCaseImpl
    let getAccountFingerprintUseCase:     GetAccountFingerprintUseCaseImpl

    // MARK: - Server trust

    /// Where the trusted authority and the recorded fingerprint are kept, per host (design D8).
    let serverTrustStore:    KeychainServerTrustStore
    /// Evaluates the TLS handshake for the configured server. Owned here as well as by the
    /// `URLSession` so the API client can turn a refusal into the error the user reads.
    let serverTrustDelegate: ServerTrustDelegate

    // MARK: - Attachment use cases

    let uploadAttachmentUseCase:   UploadAttachmentUseCaseImpl
    let downloadAttachmentUseCase: DownloadAttachmentUseCaseImpl
    let deleteAttachmentUseCase:   DeleteAttachmentUseCaseImpl

    // MARK: - Temp file lifecycle

    /// Singleton temp-file manager — injected into `AttachmentRowViewModel` via the
    /// `TempFileManaging` protocol to keep Presentation decoupled from AppKit (Constitution §II).
    let tempFileManager: AttachmentTempFileManager

    /// Drives the configurable idle timeout. Owns an `NSEvent` local monitor while the vault is
    /// unlocked; injected into `RootViewModel` through `RootViewModelDependencies` so tests never
    /// install one.
    let idleMonitor: any VaultIdleMonitoring

    /// Refreshes the vault on a timer, and when the app or the machine comes back.
    ///
    /// Injected into `RootViewModel` through `RootViewModelDependencies` alongside `idleMonitor`, so
    /// tests substitute a double rather than installing a `Timer` and two notification observers.
    let backgroundSyncMonitor: any BackgroundSyncMonitoring

    /// The identity of the current unlocked session.
    ///
    /// One instance, shared by everything that has to notice a lock: the sync repository refuses to
    /// write for a session that has ended, the browser view model refuses to show its result, and
    /// the lock and sign-out paths advance it. A second instance anywhere would be a second answer
    /// to "is this session still running", and it would be the copy that says yes.
    let sessionEpoch = SessionEpoch()

    /// Which credential the unlock screen asks for first, for as long as this process runs.
    ///
    /// One instance because the answer belongs to the launch, not to a screen: `RootViewModel` builds
    /// a fresh `UnlockViewModel` every time the vault locks (`PrizmApp.swift:803`), so a shortcut the
    /// user earned with a successful PIN would be forgotten at the next lock if it lived in the view
    /// model. Deliberately never written to disk — see `UnlockCredentialPreference`.
    let unlockCredentialPreference = UnlockCredentialPreference()

    // MARK: - Session-scoped, memory-only state

    /// The values generated and used during this session, newest first.
    ///
    /// Held here rather than inside the generator's view model so `lockVault()` and `signOut()` can
    /// clear it: the popover that produced a value is long gone by the time the vault locks, and a
    /// value that was generated but never saved is still a credential (design D9).
    let generatorHistory: GeneratorHistory

    /// The master-password gate in front of every SSH signature.
    ///
    /// Built here rather than by the agent so there is exactly one instance: the app presents the
    /// sheet, and the lock and sign-out teardowns revoke its grants. A second instance would be a
    /// second answer to "how long does a grant last", and it would be the copy that survives a lock.
    let sshAgentAuthorizer: SSHAgentAuthorizer

    /// Owns the SSH agent: the listening socket, and whether it should be listening at all.
    ///
    /// Held by the container rather than by `RootViewModel` because it has two callers with no
    /// relationship to each other — the screen state machine that knows when the vault unlocks, and
    /// the Settings pane that flips the switch — and because it outlives both the settings window
    /// and any one vault session.
    let sshAgentCoordinator: SSHAgentCoordinator

    // MARK: - Init

    init() {
        let crypto        = PrizmCryptoServiceImpl()
        let keychain      = KeychainServiceImpl()

        // The trust delegate has to exist before the session that owns it, and the session before
        // the client — so the host it asks about is supplied once the client exists, below.
        let trustStore    = KeychainServerTrustStore(keychain: keychain)
        let trustDelegate = ServerTrustDelegate(store: trustStore)
        let session       = URLSession(configuration: .default,
                                       delegate: trustDelegate,
                                       delegateQueue: nil)

        let api           = PrizmAPIClientImpl(session: session, trustDelegate: trustDelegate)
        trustDelegate.setConfiguredHost { await api.baseURL?.host }

        let biometricKeychain = BiometricKeychainServiceImpl.preferred()
        let keyCache      = VaultKeyCache()
        let orgKeyCache   = OrgKeyCache()
        let accountKeys   = AccountKeyCache()
        let vaultCache    = VaultCacheStoreImpl()
        let vault         = VaultRepositoryImpl(apiClient: api, crypto: crypto, orgKeyCache: orgKeyCache)
        let vaultKeyService = VaultKeyServiceImpl(cache: keyCache, crypto: crypto)

        let pinUnlock = KeychainPinUnlockService(keychain: keychain, crypto: crypto)
        let auth = AuthRepositoryImpl(
            apiClient: api,
            crypto:    crypto,
            keychain:  keychain,
            biometricKeychain: biometricKeychain,
            vaultCache: vaultCache,
            pinUnlock: pinUnlock
        )
        let sync = SyncRepositoryImpl(
            apiClient:       api,
            crypto:          crypto,
            vaultRepository: vault,
            vaultKeyCache:   keyCache,
            orgKeyCache:     orgKeyCache,
            accountKeyCache: accountKeys,
            vaultCache:      vaultCache,
            sessionEpoch:    sessionEpoch,
            // Resolved per use rather than captured, so the id that names the cache directory is
            // always the signed-in account's. Read from the Keychain (the authority for the active
            // session) instead of being mirrored into a second variable that could fall behind.
            currentUserId:   { await auth.storedAccount()?.userId }
        )

        let attachmentRepo = AttachmentRepositoryImpl(
            apiClient:       api,
            crypto:          crypto,
            vaultRepository: vault
        )

        // Resolve the stored account email for per-account timestamp scoping.
        // Falls back to an empty string if no account is stored yet (first launch before login);
        // the timestamp will be recorded under the correct key after login completes.
        let accountEmail = auth.storedAccount()?.email ?? ""
        let syncTimestamp = SyncTimestampRepositoryImpl(email: accountEmail)

        self.apiClient       = api
        self.serverTrustStore    = trustStore
        self.serverTrustDelegate = trustDelegate
        self.crypto          = crypto
        self.keychain        = keychain
        self.biometricKeychain = biometricKeychain
        self.vaultStore      = vault
        // The same session the API client uses, deliberately. The icon endpoint is on the account's
        // own host, so a request to it needs the certificate trust that host was configured with;
        // `FaviconLoader`'s default used to be `URLSession.shared`, which has no delegate, and every
        // favicon then failed TLS silently — the symptom was just "no site icons, everywhere".
        self.faviconLoader   = FaviconLoader(session: session)
        self.totpGenerator   = TOTPGeneratorImpl()
        self.vaultKeyCache   = keyCache
        self.orgKeyCache     = orgKeyCache
        self.accountKeyCache = accountKeys
        self.authRepository  = auth
        self.syncRepository  = sync
        self.syncUseCase                     = SyncUseCaseImpl(sync: sync)
        self.loginUseCase                    = LoginUseCaseImpl(auth: auth, sync: sync)
        self.unlockUseCase                   = UnlockUseCaseImpl(auth: auth, sync: sync)
        self.searchVaultUseCase              = SearchVaultUseCaseImpl(vault: vault)
        self.editVaultItemUseCase            = EditVaultItemUseCaseImpl(repository: vault)
        self.createVaultItemUseCase          = CreateVaultItemUseCaseImpl(repository: vault)
        self.duplicateVaultItemUseCase       = DuplicateVaultItemUseCaseImpl(repository: vault)
        self.emptyTrashUseCase               = EmptyTrashUseCaseImpl(repository: vault)
        self.deleteVaultItemUseCase          = DeleteVaultItemUseCaseImpl(repository: vault)
        self.permanentDeleteVaultItemUseCase = PermanentDeleteVaultItemUseCaseImpl(repository: vault)
        self.restoreVaultItemUseCase         = RestoreVaultItemUseCaseImpl(repository: vault)
        self.createFolderUseCase             = CreateFolderUseCaseImpl(repository: vault)
        self.renameFolderUseCase             = RenameFolderUseCaseImpl(repository: vault)
        self.deleteFolderUseCase             = DeleteFolderUseCaseImpl(repository: vault)
        self.moveItemToFolderUseCase         = MoveItemToFolderUseCaseImpl(repository: vault)
        self.createCollectionUseCase         = CreateCollectionUseCaseImpl(repository: vault)
        self.renameCollectionUseCase         = RenameCollectionUseCaseImpl(repository: vault)
        self.deleteCollectionUseCase         = DeleteCollectionUseCaseImpl(repository: vault)
        self.syncTimestampRepository         = syncTimestamp
        self.getLastSyncDateUseCase          = GetLastSyncDateUseCaseImpl(repository: syncTimestamp)
        self.exportVaultUseCase              = ExportVaultUseCaseImpl(vault: vault)
        self.importVaultUseCase              = ImportVaultUseCaseImpl(vault: vault)
        self.generateVaultHealthReportUseCase = GenerateVaultHealthReportUseCaseImpl(vault: vault)
        self.getPasswordHistoryUseCase        = GetPasswordHistoryUseCaseImpl(vault: vault)
        self.getPasskeysUseCase               = GetPasskeysUseCaseImpl(vault: vault)
        self.verifyMasterPasswordUseCase      = VerifyMasterPasswordUseCaseImpl(auth: authRepository)
        // The same word list the passphrase generator uses. It is Bitwarden's EFF long list, and
        // the fingerprint only matches another client while it stays that one — if it is ever
        // swapped for the generator's sake, the phrase changes silently into something that
        // matches nothing. `AccountFingerprintPhraseTests` pins the published vectors.
        self.getAccountFingerprintUseCase     = GetAccountFingerprintUseCaseImpl(
            auth:            authRepository,
            accountKeyCache: accountKeys,
            wordList:        PasswordGenerator.effWordList
        )
        // Attachment use cases — Upload and Download inject VaultKeyService;
        // Delete does NOT (no key material required, Constitution §VI).
        self.uploadAttachmentUseCase   = UploadAttachmentUseCaseImpl(repository: attachmentRepo, vaultKeyService: vaultKeyService)
        self.downloadAttachmentUseCase = DownloadAttachmentUseCaseImpl(repository: attachmentRepo, vaultKeyService: vaultKeyService)
        self.deleteAttachmentUseCase   = DeleteAttachmentUseCaseImpl(repository: attachmentRepo)
        self.tempFileManager           = AttachmentTempFileManager()
        // Reads the timeout settings on every poll, so changing them in Settings takes effect
        // immediately without recreating the monitor.
        self.idleMonitor               = VaultIdleMonitor(settings: { VaultTimeoutSettings.load() })
        self.backgroundSyncMonitor     = BackgroundSyncMonitor()
        self.generatorHistory          = GeneratorHistory()
        // Built as a local first: the coordinator needs the same authorizer instance, and reading
        // the stored property back mid-init to hand it over is the kind of thing that stops
        // compiling the moment the property order changes.
        let sshAuthorizer      = SSHAgentAuthorizer(verifyMasterPassword: verifyMasterPasswordUseCase)
        self.sshAgentAuthorizer = sshAuthorizer
        self.sshAgentCoordinator = SSHAgentCoordinator(vault: vault, authorizer: sshAuthorizer)
    }

    // MARK: - Factories

    /// Points the favicon loader at the signed-in account's icon service.
    ///
    /// Called once the account's server is known (at the vault transition). Before that the loader
    /// has no base and fetches nothing, so an item's domain cannot leave the device before the
    /// account that owns it is known.
    ///
    /// `ServerEnvironment.iconsURL` is `{base}/icons` — the endpoint both Bitwarden and Vaultwarden
    /// serve at `/icons/{domain}/icon.png`. Using the account's own server instead of a hardcoded
    /// third-party icon host is the whole point: a self-hosted user's item domains stay on their own
    /// infrastructure (FEATURE-GAP-ANALYSIS.md §2.5).
    ///
    /// Turning website icons off in Settings needs no call here: `FaviconLoader` reads
    /// `WebsiteIconsPreference` on every request.
    func refreshWebsiteIcons() async {
        guard WebsiteIconsPreference.isEnabled() else {
            await faviconLoader.configure(iconsBase: nil)
            return
        }
        await faviconLoader.configure(iconsBase: authRepository.serverEnvironment?.iconsURL)
    }

    /// Returns a fresh `SyncTimestampRepository` and matching `GetLastSyncDateUseCase`
    /// scoped to the given account email.
    ///
    /// Called by `RootViewModel` after a successful login or unlock to ensure the
    /// `VaultBrowserViewModel` is always scoped to the correct account — not the
    /// fallback empty-email instance created before any account was known.
    func makeSyncTimestampDependencies(for email: String) -> (repository: any SyncTimestampRepository, useCase: any GetLastSyncDateUseCase) {
        let repo = SyncTimestampRepositoryImpl(email: email)
        return (repo, GetLastSyncDateUseCaseImpl(repository: repo))
    }

    /// Creates a `LoginViewModel` pre-wired with the container's login use case.
    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(loginUseCase: loginUseCase)
    }

    /// Creates an `UnlockViewModel` for a returning user with a stored session.
    func makeUnlockViewModel(account: Account) -> UnlockViewModel {
        UnlockViewModel(auth: authRepository,
                        sync: syncUseCase,
                        account: account,
                        credentialPreference: unlockCredentialPreference)
    }

    /// Creates a `VaultBrowserViewModel` backed by the live vault store.
    func makeVaultBrowserViewModel() -> VaultBrowserViewModel {
        VaultBrowserViewModel(
            vault:            vaultStore,
            search:           searchVaultUseCase,
            delete:           deleteVaultItemUseCase,
            permanentDelete:  permanentDeleteVaultItemUseCase,
            restore:          restoreVaultItemUseCase,
            duplicate:        duplicateVaultItemUseCase,
            emptyTrash:       emptyTrashUseCase,
            sync:             syncUseCase,
            createFolder:     createFolderUseCase,
            renameFolder:     renameFolderUseCase,
            deleteFolder:     deleteFolderUseCase,
            moveItem:         moveItemToFolderUseCase,
            createCollection: createCollectionUseCase,
            renameCollection: renameCollectionUseCase,
            deleteCollection: deleteCollectionUseCase,
            syncTimestamp:    syncTimestampRepository,
            getLastSyncDate:  getLastSyncDateUseCase,
            export:           exportVaultUseCase,
            importVault:      importVaultUseCase,
            verifyMasterPassword: verifyMasterPasswordUseCase,
            fileSaver:        Self.defaultExportSaver,
            filePicker:       Self.defaultImportPicker,
            sessionEpoch:     sessionEpoch
        )
    }

    /// Creates an `ItemEditViewModel` for the given item, wired with the live edit use case.
    /// The caller is responsible for setting `onSaveSuccess` to update the UI after a save.
    /// Pass the cached `folders`, `organizations`, and `collections` from `VaultBrowserViewModel`
    /// — these are pre-fetched on the actor so no additional async call is needed here.
    func makeItemEditViewModel(for item: VaultItem,
                               folders: [Folder] = [],
                               organizations: [Organization] = [],
                               collections: [OrgCollection] = []) -> ItemEditViewModel {
        ItemEditViewModel(item: item, useCase: editVaultItemUseCase,
                          folders: folders, organizations: organizations, collections: collections)
    }

    /// Creates an `ItemEditViewModel` in create mode for the given item type.
    /// Pass `collectionId` to pre-fill the collection when creating from a collection context (task 5.9 / 7.2).
    /// Pass the cached `folders`, `organizations`, and `collections` from `VaultBrowserViewModel`.
    func makeItemCreateViewModel(for type: ItemType, folderId: String? = nil,
                                 collectionId: String? = nil,
                                 folders: [Folder] = [],
                                 organizations: [Organization] = [],
                                 collections: [OrgCollection] = []) -> ItemEditViewModel {
        // Pre-populate org and collection when creating in a collection context.
        var orgId: String? = nil
        var colIds: [String] = []
        if let colId = collectionId,
           let col = collections.first(where: { $0.id == colId }) {
            orgId  = col.organizationId
            colIds = [colId]
        }
        return ItemEditViewModel(
            type: type, useCase: createVaultItemUseCase, folders: folders,
            folderId: folderId, organizationId: orgId, collectionIds: colIds,
            organizations: organizations, collections: collections
        )
    }

    // MARK: - AppKit panel defaults (App layer — Constitution §II)
    //
    // These closures wrap AppKit classes (NSOpenPanel, NSSavePanel, NSWorkspace) and are
    // injected into Presentation-layer ViewModels so the Presentation layer never imports
    // AppKit directly.

    /// Default multi-file picker using `NSOpenPanel`.
    @MainActor
    private static func defaultNSOpenPanel() -> [(url: URL, bytes: Int)] {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = true
        panel.message                 = "Choose files to attach"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { url in
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return (url, bytes)
        }
    }

    /// Default save panel using `NSSavePanel`.
    @MainActor
    private static func defaultSavePanel(suggestedName: String) -> URL? {
        let panel                  = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.message              = "Choose where to save the attachment"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Default single-file picker for retry using `NSOpenPanel`.
    @MainActor
    private static func defaultRetryOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        panel.message                 = "Select the file to re-upload"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Default certificate picker using `NSOpenPanel`.
    ///
    /// Restricted to the types a server certificate actually comes in. Leaving it unrestricted
    /// would let the user pick any file and receive a parsing error for it — which is the same
    /// outcome as a wrong file, reached with more confidence.
    @MainActor
    static func defaultCertificateOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        panel.message                 = "Choose the certificate to trust"
        var types: [UTType]           = [.x509Certificate]
        // `.pem` has no UTType constant, but it is the form most self-signed guides produce.
        if let pem = UTType(filenameExtension: "pem") { types.append(pem) }
        panel.allowedContentTypes     = types
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Default file opener using `NSWorkspace`.
    @MainActor
    private static func defaultFileOpener(url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Save panel for a vault export, writing the bytes with owner-only permissions.
    ///
    /// **The permission fix-up is not optional.** `Data.write(options: .atomic)` writes to a
    /// temporary file and renames it into place, so the destination ends up with whatever mode the
    /// temporary got — which honours the process umask and is commonly `0644`, i.e. readable by
    /// every account on the machine. The file contains every password in the vault in plaintext,
    /// so `0600` is the minimum. Setting it after the write closes that window; it cannot be set
    /// before, because the file does not exist yet.
    ///
    /// The write is *not* the security boundary — the consent sheet is. This only keeps the file
    /// from being readable by other local accounts while it exists.
    ///
    /// - Returns: the written URL, or nil if the user cancelled the panel.
    /// - Throws: the underlying file-system error, so the caller can tell the user the export
    ///   failed rather than showing a completion message for a file that was never written.
    @MainActor
    private static func defaultExportSaver(suggestedName: String, data: Data) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories  = true
        panel.allowedContentTypes   = [.json]
        panel.message = L("The exported file is not encrypted. Store it somewhere safe.")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: url.path)
        return url
    }

    /// Open panel for choosing a vault export to import.
    @MainActor
    private static func defaultImportPicker() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes     = [.json]
        panel.message = L("Choose an unencrypted Bitwarden JSON export")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Creates an `AttachmentAddViewModel` for the given cipher ID.
    @MainActor
    func makeAddAttachmentViewModel(for cipherId: String) -> AttachmentAddViewModel {
        AttachmentAddViewModel(
            cipherId:      cipherId,
            uploadUseCase: uploadAttachmentUseCase,
            filePicker:    Self.defaultNSOpenPanel
        )
    }

    /// Creates an `AttachmentBatchViewModel` for the given cipher ID.
    @MainActor
    func makeBatchAttachmentViewModel(for cipherId: String) -> AttachmentBatchViewModel {
        AttachmentBatchViewModel(cipherId: cipherId, uploadUseCase: uploadAttachmentUseCase)
    }

    /// Creates a `HealthReportViewModel` backed by the container's health use case.
    ///
    /// The use case is injected rather than the repository: the view model should not be able to
    /// reach past the analysis into the vault.
    @MainActor
    func makeHealthReportViewModel() -> HealthReportViewModel {
        HealthReportViewModel(useCase: generateVaultHealthReportUseCase)
    }

    /// Creates a `PasswordHistoryViewModel` for one item.
    ///
    /// Per item rather than shared: the entries belong to one cipher, and the view model drops them
    /// when its section collapses, so a shared instance would keep one item's previous passwords
    /// alive while the user is looking at a different item.
    @MainActor
    func makePasswordHistoryViewModel(itemId: String) -> PasswordHistoryViewModel {
        PasswordHistoryViewModel(itemId: itemId, useCase: getPasswordHistoryUseCase)
    }

    /// Creates a `PasskeysViewModel` for one item.
    ///
    /// Per item for the same reason as the history one, and the values it holds are discarded when
    /// its section collapses.
    @MainActor
    func makePasskeysViewModel(itemId: String) -> PasskeysViewModel {
        PasskeysViewModel(itemId: itemId, useCase: getPasskeysUseCase)
    }

    /// Creates a `TOTPCodeViewModel` for one item's stored authenticator key.
    ///
    /// The secret is passed in rather than looked up, because the caller already holds the
    /// decrypted login: reading it again by id would decrypt the item a second time to learn
    /// something that is already in hand. Per item rather than shared — the view model's clock
    /// belongs to the row that is on screen, and a shared one would keep ticking for an item the
    /// user has moved away from.
    /// The verification-codes list, over the live vault and the browser view model's gate.
    ///
    /// `gateFor` is the browser's own `revealGate(for:)` rather than a second builder here: a list that
    /// decided for itself what "gated" means is exactly how a convenience screen becomes a bypass of the
    /// gate the detail pane still shows.
    @MainActor
    func makeVerificationCodesViewModel(browser: VaultBrowserViewModel) -> VerificationCodesViewModel {
        VerificationCodesViewModel(
            vault:     vaultStore,
            generator: totpGenerator,
            gateFor:   { [weak browser] item in browser?.revealGate(for: item) ?? .none }
        )
    }

    @MainActor
    func makeTOTPCodeViewModel(itemId: String, secret: String?) -> TOTPCodeViewModel {
        TOTPCodeViewModel(itemId: itemId, secret: secret, generator: totpGenerator)
    }

    /// Creates an `AttachmentRowViewModel` for the given cipher + attachment pair.
    @MainActor
    func makeAttachmentRowViewModel(cipherId: String, attachment: Attachment) -> AttachmentRowViewModel {
        AttachmentRowViewModel(
            cipherId:        cipherId,
            attachment:      attachment,
            downloadUseCase: downloadAttachmentUseCase,
            deleteUseCase:   deleteAttachmentUseCase,
            uploadUseCase:   uploadAttachmentUseCase,
            tempFileManager: tempFileManager,
            fileSaver:       Self.defaultSavePanel,
            retryFilePicker: Self.defaultRetryOpenPanel,
            fileOpener:      Self.defaultFileOpener
        )
    }
}
