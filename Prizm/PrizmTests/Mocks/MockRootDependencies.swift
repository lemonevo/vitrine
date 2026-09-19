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
    let totpGenerator: any TOTPGenerator

    private let mockLoginUseCase = MockLoginUseCase()
    private let mockSyncUseCase = MockSyncUseCase()
    private let mockVault: MockVaultRepository

    init(auth: MockAuthRepository,
         vault: MockVaultRepository,
         totpGenerator: any TOTPGenerator = TOTPGeneratorImpl()) {
        self.authRepo      = auth
        self.vaultRepo     = vault
        self.mockVault     = vault
        self.totpGenerator = totpGenerator
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
            search:          StubSearchUseCase(),
            delete:          StubDeleteUseCase(),
            permanentDelete: StubPermanentDeleteUseCase(),
            restore:         StubRestoreUseCase(),
            createFolder:     StubCreateFolder(),
            renameFolder:     StubRenameFolder(),
            deleteFolder:     StubDeleteFolder(),
            moveItem:         StubMoveItem(),
            createCollection: StubCreateCollection(),
            renameCollection: StubRenameCollection(),
            deleteCollection: StubDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo)
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
@MainActor private final class StubDeleteUseCase: DeleteVaultItemUseCase {
    func execute(id: String) async throws {}
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

    init(code: String? = "654321") {
        self.code = code
    }

    func code(for secret: String?, at date: Date) -> String? {
        // Mirror the real contract: no usable secret, no code.
        guard let secret, !secret.isEmpty else { return nil }
        return code
    }
}
