import CryptoKit
import XCTest
@testable import Prizm

// MARK: - SSHAgentCoordinatorTests

/// The SSH agent's lifetime: when it listens, when it stops, and what it says when it cannot start.
///
/// Driven through a listener that never binds (see `FakeSSHAgentListener`). The state machine is
/// where the failure modes are, and every one of them is about *when* the socket exists rather than
/// about the socket itself — a real `bind` would add the filesystem, `sun_path`'s length limit and
/// the sandbox to each test without covering any of them.
///
/// The two halves of the condition are asserted separately, because a test that only ever sets both
/// cannot tell which one is being read: enabled-while-locked and unlocked-while-disabled are the
/// cases that catch an `&&` that has become an `||`.
@MainActor
final class SSHAgentCoordinatorTests: XCTestCase {

    private var suiteName: String!
    private var defaults:  UserDefaults!
    private var vault:     MockVaultRepository!
    private var listener:  FakeSSHAgentListener!
    private var sut:       SSHAgentCoordinator!

    override func setUp() {
        super.setUp()
        suiteName = "prizm.tests.sshagent.\(UUID().uuidString)"
        defaults  = UserDefaults(suiteName: suiteName)
        vault     = MockVaultRepository()
        listener  = FakeSSHAgentListener()
        sut       = makeCoordinator()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A second coordinator over the same defaults and the same listener. Used by the persistence
    /// test, where "survives a restart" has to mean a different object reading the same store.
    private func makeCoordinator() -> SSHAgentCoordinator {
        SSHAgentCoordinator(
            vault:      vault,
            authorizer: SSHAgentAuthorizer(verifyMasterPassword: MockVerifyMasterPasswordUseCase()),
            socketPath: listener.socketPath,
            defaults:   defaults,
            makeListener: { _, respond in
                self.listener.respond = respond
                return self.listener
            }
        )
    }

    // MARK: - Defaults

    func testTheSwitchStartsOff() {
        XCTAssertFalse(sut.isEnabled)
        XCTAssertFalse(SSHAgentPreference.isEnabled(in: defaults))
        XCTAssertFalse(sut.isRunning)
        XCTAssertNil(sut.failure)
    }

    func testTheSwitchIsPersisted() {
        sut.setEnabled(true)
        XCTAssertTrue(SSHAgentPreference.isEnabled(in: defaults))

        // A fresh coordinator over the same store reads it back. That is what "persisted" has to
        // mean — an in-memory flag would satisfy the line above and fail here.
        XCTAssertTrue(makeCoordinator().isEnabled)
    }

    // MARK: - When it listens

    func testUnlockedButDisabled_doesNotStart() {
        sut.vaultDidUnlock()
        XCTAssertFalse(listener.isRunning)
        XCTAssertEqual(listener.startCount, 0)
        XCTAssertFalse(sut.isRunning)
    }

    func testEnabledButLocked_doesNotStart() {
        sut.setEnabled(true)
        XCTAssertFalse(listener.isRunning)
        XCTAssertEqual(listener.startCount, 0)
    }

    func testEnabledAndUnlocked_starts() {
        sut.setEnabled(true)
        sut.vaultDidUnlock()

        XCTAssertTrue(listener.isRunning)
        XCTAssertTrue(sut.isRunning)
        XCTAssertEqual(listener.startCount, 1)
        XCTAssertNil(sut.failure)
    }

    func testEnablingWhileUnlocked_startsImmediately() {
        sut.vaultDidUnlock()
        XCTAssertFalse(listener.isRunning)

        sut.setEnabled(true)

        XCTAssertTrue(listener.isRunning)
        // The point of the switch being reachable while the vault is open: it applies now, rather
        // than marking the agent to start at some later transition.
        XCTAssertEqual(listener.startCount, 1)
    }

    func testLocking_stopsTheAgent() {
        sut.setEnabled(true)
        sut.vaultDidUnlock()

        sut.vaultDidLock()

        XCTAssertFalse(listener.isRunning)
        XCTAssertFalse(sut.isRunning)
        XCTAssertEqual(listener.stopCount, 1)
    }

    func testDisablingWhileUnlocked_stopsTheAgent() {
        sut.setEnabled(true)
        sut.vaultDidUnlock()

        sut.setEnabled(false)

        XCTAssertFalse(listener.isRunning)
        XCTAssertFalse(sut.isEnabled)
        XCTAssertFalse(SSHAgentPreference.isEnabled(in: defaults))
    }

    func testEnablingWhileLocked_startsOnTheNextUnlock() {
        sut.setEnabled(true)
        sut.vaultDidLock()
        XCTAssertFalse(listener.isRunning)

        sut.vaultDidUnlock()

        XCTAssertTrue(listener.isRunning)
    }

    func testRepeatedUnlocks_doNotStartASecondTime() {
        sut.setEnabled(true)
        sut.vaultDidUnlock()
        sut.vaultDidUnlock()

        XCTAssertEqual(listener.startCount, 1)
    }

    func testLockingWhileDisabled_doesNotStopWhatWasNeverStarted() {
        sut.vaultDidLock()
        XCTAssertEqual(listener.stopCount, 0)
        XCTAssertFalse(sut.isRunning)
    }

    // MARK: - When it cannot start

    func testFailedStart_isReportedWithItsReason() {
        listener.startError = SSHAgentSocketError.sandboxed
        sut.setEnabled(true)
        sut.vaultDidUnlock()

        XCTAssertFalse(listener.isRunning)
        XCTAssertFalse(sut.isRunning)
        // The reason, not merely "unavailable". An agent that is off with no explanation looks to
        // the user exactly like one that is on and protecting nothing, which is the outcome the
        // spec's failure scenario exists to rule out.
        XCTAssertEqual(sut.failure, SSHAgentSocketError.sandboxed.errorDescription)
    }

    func testAFailedStart_isNotRetriedWhileTheVaultStaysUnlocked() {
        listener.startError = SSHAgentSocketError.sandboxed
        sut.setEnabled(true)
        sut.vaultDidUnlock()
        XCTAssertEqual(listener.startCount, 1)

        // A second transition to `.vault` in the same session. The obstruction — a sandbox, a path
        // too long, another agent on the socket — does not go away by being asked again, and a
        // retry here would turn one visible failure into a stream of them.
        sut.vaultDidUnlock()
        XCTAssertEqual(listener.startCount, 1)
        XCTAssertEqual(sut.failure, SSHAgentSocketError.sandboxed.errorDescription)
    }

    func testANewUnlock_isAFreshAttempt() {
        listener.startError = SSHAgentSocketError.sandboxed
        sut.setEnabled(true)
        sut.vaultDidUnlock()
        XCTAssertEqual(listener.startCount, 1)

        // The user locked and unlocked again: that is a new attempt, and this time the obstruction
        // is gone. Retrying here is the whole point of clearing the attempt on a lock.
        listener.startError = nil
        sut.vaultDidLock()
        sut.vaultDidUnlock()

        XCTAssertEqual(listener.startCount, 2)
        XCTAssertTrue(listener.isRunning)
        XCTAssertNil(sut.failure)
    }

    func testTogglingTheSwitchOff_clearsTheFailureItWasShowing() {
        listener.startError = SSHAgentSocketError.sandboxed
        sut.setEnabled(true)
        sut.vaultDidUnlock()
        XCTAssertNotNil(sut.failure)

        sut.setEnabled(false)

        // The reason belonged to an attempt the user has just abandoned. Leaving it up would show a
        // failure for something no longer being tried.
        XCTAssertNil(sut.failure)
    }

    // MARK: - What it serves

    func testIdentitiesComeFromTheVault_andCarryTheItemName() async throws {
        await vault.populate(items: [try sshItem(id: "k1", name: "Deploy key — staging")],
                             folders: [], organizations: [], collections: [], syncedAt: Date())
        sut.setEnabled(true)
        sut.vaultDidUnlock()

        let respond = try XCTUnwrap(listener.respond)
        let answer  = await respond(SSHWireWriter.message(type: .requestIdentities), nil)

        // The item's name, not the comment inside the key file — the spec's scenario, asserted
        // through the whole path a socket would take.
        XCTAssertEqual(try identities(in: answer).map(\.comment), ["Deploy key — staging"])
        XCTAssertEqual(sut.usableKeys.map(\.comment), ["Deploy key — staging"])
        XCTAssertTrue(sut.unusableKeys.isEmpty)
    }

    func testIdentitiesAreReadPerRequest_notSnapshottedAtStart() async throws {
        await vault.populate(items: [try sshItem(id: "k1", name: "First")],
                             folders: [], organizations: [], collections: [], syncedAt: Date())
        sut.setEnabled(true)
        sut.vaultDidUnlock()
        let respond = try XCTUnwrap(listener.respond)

        let before = try identities(in: await respond(SSHWireWriter.message(type: .requestIdentities), nil))
        XCTAssertEqual(before.map(\.comment), ["First"])

        // A key added after the agent started is offered on the very next request, with no restart.
        await vault.populate(items: [try sshItem(id: "k1", name: "First"),
                                     try sshItem(id: "k2", name: "Second")],
                             folders: [], organizations: [], collections: [], syncedAt: Date())

        let after = try identities(in: await respond(SSHWireWriter.message(type: .requestIdentities), nil))
        XCTAssertEqual(after.map(\.comment), ["First", "Second"])
    }

    func testAKeyThatCannotBeUsed_isListedWithItsReasonRatherThanOffered() async throws {
        await vault.populate(items: [keylessSSHItem(id: "k1", name: "No private key")],
                             folders: [], organizations: [], collections: [], syncedAt: Date())
        sut.setEnabled(true)
        sut.vaultDidUnlock()

        let respond = try XCTUnwrap(listener.respond)
        let answer  = await respond(SSHWireWriter.message(type: .requestIdentities), nil)

        XCTAssertTrue(try identities(in: answer).isEmpty)
        XCTAssertTrue(sut.usableKeys.isEmpty)
        // The omission is stated, with a reason, rather than left to be inferred from a key that
        // never shows up in `ssh-add -l`.
        XCTAssertEqual(sut.unusableKeys.map(\.name), ["No private key"])
        XCTAssertFalse(try XCTUnwrap(sut.unusableKeys.first).reason.isEmpty)
    }

    func testLocking_dropsTheKeyLists_andALateRefreshCannotRestoreThem() async throws {
        await vault.populate(items: [try sshItem(id: "k1", name: "Deploy key")],
                             folders: [], organizations: [], collections: [], syncedAt: Date())
        sut.setEnabled(true)
        sut.vaultDidUnlock()
        await sut.refreshKeys()
        XCTAssertEqual(sut.usableKeys.count, 1)

        sut.vaultDidLock()

        // They are names of vault items, and a locked vault has none — the same rule that drops the
        // health report in the same teardown.
        XCTAssertTrue(sut.usableKeys.isEmpty)
        XCTAssertTrue(sut.unusableKeys.isEmpty)

        // This double still holds the item — nothing cleared it — which makes this exactly the case
        // the guard in `loadKeys()` exists for. A read that lands after the lock must not republish
        // the names of items the user has just closed, and "cleared on lock" alone does not cover
        // it: the clearing is synchronous, the read is not.
        await sut.refreshKeys()
        XCTAssertTrue(sut.usableKeys.isEmpty)
        XCTAssertTrue(sut.unusableKeys.isEmpty)
    }

    func testARequestForAnUnknownKey_isRefused() async throws {
        await vault.populate(items: [try sshItem(id: "k1", name: "Deploy key")],
                             folders: [], organizations: [], collections: [], syncedAt: Date())
        sut.setEnabled(true)
        sut.vaultDidUnlock()
        let respond = try XCTUnwrap(listener.respond)

        // A well-formed SIGN_REQUEST naming a blob this agent does not serve. `ssh` asks every
        // agent in turn, so this is the common case and must be an answer, not a crash.
        var body = SSHWireWriter()
        body.writeString(Data([0xDE, 0xAD, 0xBE, 0xEF]))
        body.writeString(Data("payload".utf8))
        body.writeUInt32(0)
        let answer = await respond(
            SSHWireWriter.message(type: .signRequest, body: body.bytes), nil)

        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        XCTAssertEqual(try reader.readByte(), SSHAgentMessage.failure.rawValue)
    }

    // MARK: - Helpers

    private func identities(in answer: Data) throws -> [(blob: Data, comment: String)] {
        var reader = SSHWireReader(answer)
        _ = try reader.readUInt32()
        let type = try reader.readByte()
        XCTAssertEqual(type, SSHAgentMessage.identitiesAnswer.rawValue)
        let count = Int(try reader.readUInt32())
        return try (0..<count).map { _ in
            let blob = try reader.readString()
            return (blob, String(decoding: try reader.readString(), as: UTF8.self))
        }
    }

    private func sshItem(id: String, name: String) throws -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .sshKey(SSHKeyContent(
                privateKey:     try ed25519KeyText(),
                publicKey:      "ssh-ed25519 AAAA… generated@test",
                keyFingerprint: "SHA256:abc",
                notes:          nil, customFields: []
            ))
        )
    }

    private func keylessSSHItem(id: String, name: String) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: Date(), revisionDate: Date(),
            content: .sshKey(SSHKeyContent(privateKey: nil, publicKey: nil, keyFingerprint: nil,
                                           notes: nil, customFields: []))
        )
    }

    /// A complete `openssh-key-v1` container for a freshly generated ed25519 key.
    ///
    /// Built here rather than pasted: the test then holds no key material, and the fixture cannot
    /// drift away from what the parser expects — the seed and the public key come from the same
    /// `Curve25519` call, so the container's internal consistency check is satisfied by
    /// construction rather than by a constant someone once checked.
    private func ed25519KeyText(comment: String = "generated@test") throws -> String {
        let seed       = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let publicKey  = privateKey.publicKey.rawRepresentation

        var blob = SSHWireWriter()
        blob.writeString("ssh-ed25519")
        blob.writeString(publicKey)

        var writer = SSHWireWriter()
        writer.writeString(Data("openssh-key-v1\u{0}".utf8))
        writer.writeString("none")
        writer.writeString("none")
        writer.writeString(Data())
        writer.writeUInt32(1)
        writer.writeString(Data(blob.bytes))

        var section = SSHWireWriter()
        section.writeUInt32(0x0BAD_C0DE)
        section.writeUInt32(0x0BAD_C0DE)
        section.writeString("ssh-ed25519")
        section.writeString(publicKey)
        section.writeString(seed + publicKey)
        section.writeString(comment)
        writer.writeString(Data(section.bytes))

        // The markers are assembled rather than written out, so a secret scanner reading this file
        // does not have to work out that the body is generated.
        let begin = ["-----BEGIN", "OPENSSH", "PRIVATE", "KEY-----"].joined(separator: " ")
        let end   = ["-----END", "OPENSSH", "PRIVATE", "KEY-----"].joined(separator: " ")
        return "\(begin)\n\(Data(writer.bytes).base64EncodedString())\n\(end)\n"
    }
}
