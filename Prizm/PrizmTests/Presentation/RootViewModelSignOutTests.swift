import XCTest
@testable import Prizm

/// Unit tests for `RootViewModel.signOut()`.
///
/// Kept separate from `RootViewModelLockTests` because the two teardown paths are deliberately
/// different — locking keeps the stored session, signing out discards it — and a suite named after
/// one of them asserting on the other would be misleading.
@MainActor
final class RootViewModelSignOutTests: XCTestCase {

    private var mockAuth: MockAuthRepository!
    private var mockVault: MockVaultRepository!
    private var deps: MockRootDependencies!
    private var sut: RootViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockAuth = MockAuthRepository()
        mockVault = MockVaultRepository()
        deps = MockRootDependencies(auth: mockAuth, vault: mockVault)
        sut = RootViewModel(container: deps)
    }

    /// Yields to the main actor run loop until `condition` returns true or timeout.
    private func waitUntil(
        timeout: Duration = .milliseconds(500),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// A value generated but never saved is still a credential. Signing out destroys every other
    /// piece of session state, and the history has to go with it (design D9).
    func testSignOut_clearsTheGeneratorHistory() async throws {
        sut.screen = .vault
        deps.generatorHistory.append("generated-but-unsaved")
        XCTAssertEqual(deps.generatorHistory.entries.count, 1)

        sut.signOut()
        try await waitUntil { self.deps.generatorHistory.entries.isEmpty }

        XCTAssertTrue(deps.generatorHistory.entries.isEmpty)
        XCTAssertTrue(mockAuth.signOutCalled)
    }

    /// Both key caches, not just the vault one.
    ///
    /// `lockVault()` cleared both and `signOut()` cleared one, so the unwrapped organisation keys
    /// survived a sign-out for the life of the process — the exact thing Constitution §III
    /// forbids. `AuthRepositoryImpl` holds no cache, so nothing downstream was clearing them.
    func testSignOut_clearsTheOrgKeyCache() async throws {
        let keys = CryptoKeys(encryptionKey: Data(repeating: 0x11, count: 32),
                              macKey: Data(repeating: 0x22, count: 32))
        await deps.orgKeyCache.store(key: keys, for: "org-1")
        let before = await deps.orgKeyCache.snapshot()
        XCTAssertEqual(before.count, 1)

        sut.signOut()

        // The clear lands after `authRepo.signOut()` and `clearVault()`, so poll rather than assume
        // an ordering — and `waitUntil` takes a synchronous predicate, so this loop is hand-rolled.
        var after = await deps.orgKeyCache.snapshot()
        let deadline = ContinuousClock.now + .milliseconds(500)
        while !after.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
            after = await deps.orgKeyCache.snapshot()
        }

        XCTAssertTrue(after.isEmpty)
    }
}
