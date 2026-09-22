import Foundation
@testable import Prizm

// MARK: - MockRootDependencies

/// Shared `RootViewModelDependencies` double.
///
/// Lives here rather than inside a single test file because more than one suite needs to build a
/// real `RootViewModel` (lock behaviour, copy commands). Keeping one copy means a new protocol
/// requirement is added in one place instead of being missed by a stale duplicate.
///
/// The `totpGenerator` is injectable so a test can pin the value the copy commands hand out.
@MainActor
final class MockRootDependencies: RootViewModelDependencies {
    let authRepo: any AuthRepository
    let vaultRepo: any VaultRepository
    let vaultKeyCache = VaultKeyCache()
    let orgKeyCache   = OrgKeyCache()
    let accountKeyCache = AccountKeyCache()
    /// Real, not a double: the ring buffer has no I/O and no dependencies, so a suite can assert
    /// against the actual implementation and the lock path is exercised end to end.
    let generatorHistory = GeneratorHistory()
    let totpGenerator: any TOTPGenerator
    /// Records start/stop and lets a suite fire the idle timeout on demand.
    ///
    /// Held at the concrete type, with the protocol requirement satisfied by an explicitly typed
    /// accessor below. A stored `let` infers the concrete type, which the compiler refuses to accept
    /// as a witness for an `any VaultIdleMonitoring` requirement; and the concrete type is the whole
    /// point here, because `fire(_:)` is a test-only affordance that the protocol does not declare.
    let mockIdleMonitor = MockVaultIdleMonitor()
    var idleMonitor: any VaultIdleMonitoring { mockIdleMonitor }
    /// Same shape as the idle monitor above, and for the same reason: the real monitor's `Timer` and
    /// notification observers have no place in a unit test, but the wiring that starts and stops it
    /// does.
    let mockBackgroundSyncMonitor = MockBackgroundSyncMonitor()
    var backgroundSyncMonitor: any BackgroundSyncMonitoring { mockBackgroundSyncMonitor }

    /// The real epoch, not a double: it has no I/O and no dependencies, the suite asserts on the
    /// lock paths advancing it, and a stub would only be asked the same question it was told to
    /// answer.
    let sessionEpoch = SessionEpoch()

    /// The search used to build the browser view model.
    ///
    /// Defaults to a stub that returns nothing, which is what most suites want: they assert on
    /// commands and lock behaviour, not on the item list. A suite that *does* need the list — the
    /// session-teardown tests, which assert that loaded items are cleared — sets a real one here
    /// **before** constructing `RootViewModel`, since that is what builds the view model.
    var searchUseCase: any SearchVaultUseCase = StubSearchUseCase()

    private let mockLoginUseCase = MockLoginUseCase()
    /// Not private: a suite can set `stubbedDelay` to hold a sync in flight.
    let mockSyncUseCase = MockSyncUseCase()
    private let mockVault: MockVaultRepository

    /// Handed to the browser view model and exposed so a suite can assert *which* id was duplicated.
    /// Created once rather than inline in `makeVaultBrowserViewModel()` for that reason.
    let duplicateUseCase = NoopDuplicateUseCase()

    /// Same reasoning, plus one: a suite can hold a delete open to observe the browser's `isMutating`
    /// state, which is what the background decision reads as "busy".
    let deleteUseCase = HoldableDeleteUseCase()

    /// Same reasoning as `duplicateUseCase`: a suite needs to set the stubbed outcome and read back
    /// whether it was invoked.
    let emptyTrashUseCase = StubEmptyTrashUseCase()

    /// Handed to the browser view model so a suite can decide the master-password answer. The
    /// browser asks the gate through `RootViewModel`, and `RootViewModel` is the thing under test,
    /// so the answer has to be controllable from outside both of them.
    let verifyMasterPasswordUseCase = MockVerifyMasterPasswordUseCase()

    /// The SSH agent's gate, over the same controllable password answer.
    ///
    /// Built here rather than inside a suite so the lock and sign-out tests exercise the real
    /// instance the agent would use — the property under test is that a grant does not survive a
    /// lock, and a fresh authorizer per assertion would not show that.
    lazy var sshAgentAuthorizer = SSHAgentAuthorizer(
        verifyMasterPassword: verifyMasterPasswordUseCase)

    /// The agent's listener, held at the concrete type so a suite can assert it was started and
    /// stopped. Never binds anything — see `FakeSSHAgentListener`.
    let sshAgentListener = FakeSSHAgentListener()

    /// The agent itself, over the mock vault and the fake listener above.
    ///
    /// Real rather than a double: the property under test is that the socket follows the vault's
    /// lock state, and that has to be the same instance `RootViewModel` drives.
    lazy var sshAgentCoordinator = SSHAgentCoordinator(
        vault:        mockVault,
        authorizer:   sshAgentAuthorizer,
        socketPath:   sshAgentListener.socketPath,
        defaults:     Self.sshAgentDefaults,
        makeListener: { _, respond in
            self.sshAgentListener.respond = respond
            return self.sshAgentListener
        }
    )

    /// The defaults the agent's switch is read from and written to.
    ///
    /// A private suite rather than `.standard`, for two reasons: the switch is persisted, so a value
    /// left behind by an earlier run would make this mock start in a state no test asked for; and
    /// writing to `.standard` from a test would change the developer's own Prizm preferences.
    private static let sshAgentDefaults = UserDefaults(suiteName: "prizm.tests.sshagent") ?? .standard

    init(auth: MockAuthRepository,
         vault: MockVaultRepository,
         totpGenerator: any TOTPGenerator = TOTPGeneratorImpl()) {
        self.authRepo      = auth
        self.vaultRepo     = vault
        self.mockVault     = vault
        self.totpGenerator = totpGenerator
        // Cleared here rather than in each test: `sshAgentCoordinator` is lazy, so this runs before
        // it reads the switch, and no suite has to remember that the default is persisted.
        Self.sshAgentDefaults.removeObject(forKey: SSHAgentPreference.key)
    }

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(loginUseCase: mockLoginUseCase)
    }

    func makeUnlockViewModel(account: Account) -> UnlockViewModel {
        UnlockViewModel(auth: authRepo as! MockAuthRepository, sync: mockSyncUseCase, account: account)
    }

    func makeVaultBrowserViewModel() -> VaultBrowserViewModel {
        let syncRepo = MockSyncTimestampRepository(storedDate: nil)
        return VaultBrowserViewModel(
            vault:           mockVault,
            search:          searchUseCase,
            delete:          deleteUseCase,
            permanentDelete: StubPermanentDeleteUseCase(),
            restore:         StubRestoreUseCase(),
            duplicate:       duplicateUseCase,
            emptyTrash:      emptyTrashUseCase,
            sync:            mockSyncUseCase,
            createFolder:     StubCreateFolder(),
            renameFolder:     StubRenameFolder(),
            deleteFolder:     StubDeleteFolder(),
            moveItem:         StubMoveItem(),
            createCollection: StubCreateCollection(),
            renameCollection: StubRenameCollection(),
            deleteCollection: StubDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo),
            export:           MockExportVaultUseCase(),
            importVault:      MockImportVaultUseCase(),
            verifyMasterPassword: verifyMasterPasswordUseCase,
            fileSaver:        { _, _ in nil },
            filePicker:       { nil },
            sessionEpoch:     sessionEpoch
        )
    }

    /// The real use case over the mock vault, rather than a stub: the report then runs against
    /// whatever items a suite put in the vault, which is what the lock and sign-out tests assert on.
    /// A stub would only buy a way to force a failure, and `HealthReportViewModelTests` gets that
    /// from a use case double of its own.
    func makeHealthReportViewModel() -> HealthReportViewModel {
        HealthReportViewModel(useCase: GenerateVaultHealthReportUseCaseImpl(vault: mockVault))
    }

    /// A real list over the mock vault, so a suite that opens it sees whatever items it put there.
    /// The browser is passed in so the gate is the browser's own — the same reason production passes it.
    func makeVerificationCodesViewModel(browser: VaultBrowserViewModel) -> VerificationCodesViewModel {
        VerificationCodesViewModel(
            vault:     mockVault,
            generator: StubTOTPGenerator(),
            gateFor:   { [weak browser] item in browser?.revealGate(for: item) ?? .none }
        )
    }

    func makeSyncTimestampDependencies(for email: String) -> (repository: any SyncTimestampRepository, useCase: any GetLastSyncDateUseCase) {
        let repo = MockSyncTimestampRepository(storedDate: nil)
        return (repo, GetLastSyncDateUseCaseImpl(repository: repo))
    }

    /// No-op: this mock has no favicon loader to point at a server.
    func refreshWebsiteIcons() async {}
}

// MARK: - Minimal stubs for VaultBrowserViewModel dependencies
//
// `private` on purpose: several other suites declare same-named stubs for the same protocols, and
// top-level `private` is file-scoped in Swift. These are only referenced from `MockRootDependencies`
// in this file, so widening them would buy nothing and break those suites.

@MainActor private final class StubSearchUseCase: SearchVaultUseCase {
    func execute(query: String, in selection: SidebarSelection) throws -> [VaultItem] { [] }
}
@MainActor private final class StubPermanentDeleteUseCase: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class StubRestoreUseCase: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct StubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
@MainActor private struct StubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
@MainActor private struct StubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct StubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
@MainActor private struct StubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
@MainActor private struct StubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
@MainActor private struct StubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}

// MARK: - StubTOTPGenerator

/// Returns a fixed, recognisable code so a test can prove the *generated* value is what gets
/// copied — and, more importantly, that the stored seed never is.
nonisolated struct StubTOTPGenerator: TOTPGenerator {
    let code: String?

    /// The step the stub reports. Fixed rather than derived, so a test asserting on the countdown is
    /// asserting on the row rather than on the stub's arithmetic.
    let period: TimeInterval

    init(code: String? = "654321", period: TimeInterval = 30) {
        self.code   = code
        self.period = period
    }

    func window(for secret: String?, at date: Date) -> TOTPWindow? {
        // Mirror the real contract: no usable secret, no code.
        guard let secret, !secret.isEmpty, let code else { return nil }
        // Aligned to the step boundary exactly as the real generator is, so a caller that reads
        // `expiresAt` gets a plausible instant rather than one that depends on when the test ran.
        let step    = max(1, period)
        let counter = floor(date.timeIntervalSince1970 / step)
        return TOTPWindow(value:     code,
                          expiresAt: Date(timeIntervalSince1970: (counter + 1) * step),
                          period:    step)
    }
}
