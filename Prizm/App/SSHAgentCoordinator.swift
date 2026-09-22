import Combine
import Foundation
import os.log

// MARK: - SSHAgentListening

/// The listening half of the agent, as the coordinator needs it.
///
/// A protocol rather than `SSHAgentServer` directly, so the lifecycle can be tested without a
/// socket. Everything with a failure mode lives in the state machine — enabled × unlocked →
/// running, and the reason when it cannot start — and driving that through a real `bind` would make
/// each test depend on the filesystem, on the socket path's length, and on not being sandboxed,
/// while covering nothing that the state machine's own tests do not.
nonisolated protocol SSHAgentListening: AnyObject {

    /// Where the socket is, or would be.
    var socketPath: String { get }

    /// Whether it is listening right now.
    var isRunning: Bool { get }

    /// Binds and listens. Idempotent.
    func start() throws

    /// Stops listening, wakes every client, and removes the socket file. Idempotent.
    func stop()
}

nonisolated extension SSHAgentServer: SSHAgentListening {}

// MARK: - SSHAgentCoordinator

/// Owns the SSH agent's lifetime, and the answer to "why is it not running".
///
/// The agent runs when — and only when — the user has switched it on **and** the vault is unlocked.
/// Both halves are load-bearing. Enabled alone would serve keys out of a locked vault; unlocked
/// alone would start a signing service nobody asked for, which is the state the off-by-default
/// preference exists to prevent. Every transition goes through `reconcile()`, so the condition is
/// written once rather than at each of the four call sites that can change it.
///
/// **A failed start is recorded, not retried.** The reason is kept in `failure` for Settings to
/// show, and nothing here tries again until something actually changes — the user toggles the
/// switch, or the vault is unlocked again. A retry loop would turn a visible failure into a
/// background one, and a socket that cannot be bound does not become bindable by being asked twice.
///
/// It holds no key material. The identities are public blobs; the private key is parsed inside the
/// signing closure and dies with it.
@MainActor
final class SSHAgentCoordinator: ObservableObject {

    // MARK: - Observable state

    /// Whether the user has switched the agent on. Persisted; off unless the user said otherwise.
    @Published private(set) var isEnabled: Bool

    /// Whether the socket is listening.
    @Published private(set) var isRunning = false

    /// Why the agent is not running, when it was asked to run and could not. `nil` while it is up,
    /// while it is switched off, and before it has ever been asked to start.
    ///
    /// A `String` rather than an `Error` because this is what Settings renders, and because the
    /// errors that can arrive here are already `LocalizedError`s whose description is the whole of
    /// what can be said. The spec's scenario is "reports unavailable **and why**" — an agent that is
    /// off with no explanation is indistinguishable from one that is on and protecting nothing.
    @Published private(set) var failure: String?

    /// The keys the agent serves, as of the last read of the vault.
    @Published private(set) var usableKeys:   [SSHAgentIdentity]    = []

    /// The keys it cannot serve, each with the reason. Shown in Settings so a key that never
    /// appears in `ssh-add -l` has an explanation next to it.
    @Published private(set) var unusableKeys: [SSHAgentUnusableKey] = []

    /// The socket path, for Settings to display and for the user to export as `SSH_AUTH_SOCK`.
    ///
    /// Taken from the listener once one exists so what is shown is what was bound, rather than what
    /// would have been bound.
    var socketPath: String { listener?.socketPath ?? configuredPath }

    // MARK: - Dependencies

    private let vault:      any VaultRepository
    private let authorizer: SSHAgentAuthorizer
    private let defaults:   UserDefaults
    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "SSHAgent")

    private let configuredPath: String

    /// Builds the listener on first use. Injectable so tests can drive the lifecycle without a
    /// socket; see `SSHAgentListening`.
    ///
    /// `@MainActor` because everything that builds one is on the main actor — this class, and the
    /// test doubles that hand back a listener they keep a reference to. A nonisolated type here
    /// would force those doubles to guard their own state for no reason.
    /// `@escaping` on the second parameter is required, not decoration: in a *function type* a
    /// function-typed parameter is non-escaping unless marked, and the listener keeps the responder
    /// for its whole life. Without it the default below cannot even pass its own parameter on.
    private let makeListener: @MainActor (String, @escaping @Sendable (Data, SSHAgentPeer?) async -> Data) -> any SSHAgentListening

    /// Created on the first start rather than in `init`, because its `respond` closure captures
    /// `self` and a partially-initialised `self` cannot be captured.
    private var listener: (any SSHAgentListening)?

    /// Whether the vault is unlocked. Set by `RootViewModel` at the vault transitions, because the
    /// coordinator deliberately does not observe the screen: there is one place that knows when the
    /// vault became usable, and it is the state machine that owns the screen.
    private var vaultIsUnlocked = false

    /// Whether a start has already been attempted since the running condition was last left.
    ///
    /// A failed start is **not** retried while the vault stays unlocked. The obstructions this can
    /// hit — a sandbox, a path past `sun_path`'s limit, another agent already on the socket — do not
    /// become untrue by being asked again, so retrying would turn one visible failure into a stream
    /// of them. Cleared in `stopIfRunning()`, which every exit from the running condition passes
    /// through, so locking and switching the feature off both give the next attempt a clean slate
    /// without either having to remember to.
    private var attemptedStart = false

    // MARK: - Init

    init(vault: any VaultRepository,
         authorizer: SSHAgentAuthorizer,
         socketPath: String = SSHAgentSocketLocation.defaultPath(),
         defaults: UserDefaults = .standard,
         makeListener: @escaping @MainActor (String, @escaping @Sendable (Data, SSHAgentPeer?) async -> Data) -> any SSHAgentListening
            = { path, respond in SSHAgentServer(socketPath: path, respond: respond) }) {
        self.vault          = vault
        self.authorizer     = authorizer
        self.configuredPath = socketPath
        self.defaults       = defaults
        self.makeListener   = makeListener
        self.isEnabled      = SSHAgentPreference.isEnabled(in: defaults)
    }

    // MARK: - Lifecycle

    /// The vault reached its unlocked state.
    ///
    /// Called on every transition to `.vault`, including the second and later ones in a session. A
    /// repeat is a no-op while the agent is up; after a failed start it is a fresh attempt, which is
    /// a retry the user caused rather than one this class decided on.
    func vaultDidUnlock() {
        vaultIsUnlocked = true
        reconcile()
    }

    /// The vault was locked, or the user signed out.
    ///
    /// The key lists go with it. They are names of vault items, and a locked vault has none — the
    /// same reason `RootViewModel` drops the health report in the same teardown.
    func vaultDidLock() {
        vaultIsUnlocked = false
        usableKeys   = []
        unusableKeys = []
        reconcile()
    }

    /// Switches the agent on or off, and applies it immediately rather than at the next unlock.
    ///
    /// Applying it now is the whole point of the switch being reachable while the vault is open:
    /// turning it off should stop the agent, not mark it to stop later.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        SSHAgentPreference.setEnabled(enabled, in: defaults)
        isEnabled = enabled
        // The reason a start failed belongs to the attempt that failed. Leaving it up after the
        // user switches the feature off would show a failure for something no longer being tried.
        if !enabled { failure = nil }
        reconcile()
    }

    /// Re-reads the vault's SSH keys and republishes the two lists.
    ///
    /// Called by Settings when the pane appears. The agent itself re-reads per request, so this is
    /// only about showing the current state — including while the agent is switched off, which is
    /// when a user is most likely to be looking at which keys they would get.
    func refreshKeys() async {
        _ = await loadKeys()
    }

    // MARK: - State machine

    /// Starts or stops the agent so it matches `isEnabled && vaultIsUnlocked`.
    private func reconcile() {
        if isEnabled && vaultIsUnlocked {
            startIfNeeded()
        } else {
            stopIfRunning()
        }
    }

    private func startIfNeeded() {
        // Already up: nothing to do, but `isRunning` is republished because a listener that was
        // stopped out from under the coordinator would otherwise leave this flag lying.
        if listener?.isRunning == true {
            isRunning = true
            return
        }
        // Already tried since the condition last changed, and it did not work. See `attemptedStart`.
        guard !attemptedStart else { return }
        attemptedStart = true

        let listener = self.listener ?? makeListener(configuredPath) { [weak self] message, peer in
            guard let self else { return SSHWireWriter.failure() }
            return await self.respond(to: message, peer: peer)
        }
        self.listener = listener

        do {
            try listener.start()
            failure   = nil
            isRunning = true
            logger.info("SSH agent listening at \(listener.socketPath, privacy: .public)")
            Task { await refreshKeys() }
        } catch {
            // Kept, not merely logged. The spec's failure scenario is that Prizm reports the agent
            // as unavailable *and why*; a reason that only reaches the log is a reason the user
            // never sees, and "the agent is off" with no explanation is the one presentation this
            // feature must not have.
            failure   = error.localizedDescription
            isRunning = false
            logger.error("SSH agent could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopIfRunning() {
        // Before the early return, so switching the feature off while the vault is locked — a path
        // where no listener exists yet — still clears the next attempt.
        attemptedStart = false
        guard let listener else { return }
        if listener.isRunning { listener.stop() }
        isRunning = false
    }

    // MARK: - Answering requests

    /// Answers one agent message.
    ///
    /// The identities are read from the vault **per request**, not snapshotted when the agent
    /// started. Two reasons, and the second is the one that matters: adding a key takes effect on
    /// the next `ssh-add -l` instead of requiring the user to toggle the agent off and on, and a key
    /// the user has just deleted stops being offered immediately rather than at the next restart.
    /// An agent still offering a key that is no longer in the vault is a signing service for
    /// something the user believes they removed.
    private func respond(to message: Data, peer: SSHAgentPeer?) async -> Data {
        let keys = await loadKeys()
        return await SSHAgentResponder.response(
            to:         message,
            identities: keys.usable,
            authorize:  { [authorizer] identity in
                // The peer's name is passed, not just its pid: the prompt is the only place the
                // user can find out *what* is asking, and a prompt they cannot answer is one they
                // learn to dismiss.
                await authorizer.authorize(identity, requestedBy: peer?.name)
            },
            sign: { [vault] identity, data, flags in
                try await Self.signature(for: identity, data: data, flags: flags, vault: vault)
            }
        )
    }

    /// Reads the vault and classifies its SSH keys, publishing the result.
    ///
    /// Publishing only on a change: this runs on every request, and assigning an equal array would
    /// make Settings re-render each time `ssh` asks for a signature.
    private func loadKeys() async -> (usable: [SSHAgentIdentity], unusable: [SSHAgentUnusableKey]) {
        // A locked vault has no keys to describe, and this is checked here as well as in
        // `vaultDidLock()` because the two are not the same guarantee: the lists are cleared
        // synchronously on lock, but a read that started before it lands after, and without this
        // it would republish the names of items the user has just closed. The lists must never
        // describe a locked vault, whether they were filled before the lock or after it.
        guard vaultIsUnlocked else { return ([], []) }

        let items: [VaultItem]
        do {
            items = try await vault.allItems()
        } catch {
            // Not surfaced as `failure`: the agent is running, and this is one request that could
            // not be answered — the client is told `FAILURE`, which is the truthful answer. Turning
            // it into the agent's failure state would claim the listener is down when it is not.
            logger.error("SSH agent could not read the vault: \(error.localizedDescription, privacy: .public)")
            return ([], [])
        }

        let keys = SSHAgentKeyStore.load(items: items)
        if keys.usable   != usableKeys   { usableKeys   = keys.usable }
        if keys.unusable != unusableKeys { unusableKeys = keys.unusable }
        return keys
    }

    /// Produces one signature, parsing the key at this moment and dropping it with the call.
    ///
    /// `nonisolated` and static so the parse and the RSA sign run off the main actor — the key
    /// material's lifetime is this call either way, and there is no reason for the main thread to
    /// be the one holding it.
    private nonisolated static func signature(
        for identity: SSHAgentIdentity,
        data:  Data,
        flags: SSHAgentSignFlags,
        vault: any VaultRepository
    ) async throws -> (algorithm: String, signature: Data) {
        let item = try await vault.itemDetail(id: identity.itemId)
        let key  = try SSHAgentKeyStore.key(for: item)
        return try SSHSigner.signature(for: key, data: data, flags: flags)
    }
}
