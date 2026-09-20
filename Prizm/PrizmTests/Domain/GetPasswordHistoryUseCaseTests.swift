import XCTest
@testable import Prizm

// MARK: - GetPasswordHistoryUseCaseTests

/// Tests for the use case's contract: it hands back what the repository decrypted, changes nothing
/// about it, and lets a failure through.
///
/// **The decryption itself is not tested here.** `MockVaultRepository` holds no key material, so it
/// returns entries it was handed rather than deriving them. The real round trip — including the
/// per-item key resolution and the malformed-entry skipping — is covered in
/// `VaultRepositoryPasswordHistoryTests`, against the real actor.
@MainActor
final class GetPasswordHistoryUseCaseTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var sut: GetPasswordHistoryUseCaseImpl!

    override func setUp() async throws {
        try await super.setUp()
        vault = MockVaultRepository()
        sut   = GetPasswordHistoryUseCaseImpl(vault: vault)
    }

    private func populatedItem(id: String = "item-1") async -> VaultItem {
        let item = VaultItem(
            id: id, name: "GitHub", isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .login(LoginContent(
                username: "octocat", password: "hunter2", uris: [],
                totp: nil, notes: nil, customFields: []
            )),
            organizationId: nil, collectionIds: [], preserved: .empty
        )
        await vault.populate(items: [item], folders: [], organizations: [],
                             collections: [], syncedAt: .now)
        return item
    }

    func test_execute_returnsTheDecryptedEntries() async throws {
        let item = await populatedItem()
        let entries = [
            PasswordHistoryEntry(password: "older-password", lastUsedDate: Date()),
            PasswordHistoryEntry(password: "oldest-password", lastUsedDate: nil)
        ]
        vault.stubbedPasswordHistory = [item.id: entries]

        let result = try await sut.execute(itemId: item.id)

        XCTAssertEqual(result, entries)
        XCTAssertEqual(vault.lastPasswordHistoryId, item.id)
    }

    func test_execute_emptyHistory_returnsEmpty() async throws {
        let item = await populatedItem()

        let result = try await sut.execute(itemId: item.id)

        XCTAssertTrue(result.isEmpty)
    }

    /// A failure is propagated, not converted into an empty list. "This item has no previous
    /// passwords" and "they could not be read" are different claims.
    func test_execute_propagatesFailures() async throws {
        let item = await populatedItem()
        vault.stubbedPasswordHistoryError = VaultError.vaultLocked

        do {
            _ = try await sut.execute(itemId: item.id)
            XCTFail("Expected the failure to propagate")
        } catch VaultError.vaultLocked {
            // Expected: the failure reaches the caller unchanged.
        } catch {
            XCTFail("Expected vaultLocked, got \(error)")
        }
    }
}
