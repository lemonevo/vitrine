import Combine
import Foundation
import os.log

// MARK: - SSHAgentAuthorizer

/// The master-password gate in front of every SSH signature.
///
/// **Why a gate at all.** The agent answers anyone who can reach its socket, and the socket is
/// reachable by any process running as this user — `git`, an editor's remote extension, and equally
/// a script someone was talked into running. "The vault is unlocked" therefore cannot mean "these
/// processes may sign", or the agent is an unattended key-extraction path.
///
/// **What the gate returns.** Not a fresh prompt per signature. It grants per key per unlock
/// session: the first request for a key asks, later requests for that key do not. Prompting on
/// every signature would make any `git` operation that signs more than once unusable, and an agent
/// the user turns off protects nothing — which is the outcome this exists to prevent. The grant is
/// still consulted on every request, so there is no signature that skips the gate.
///
/// **What it is not.** The master password here is a *consent* boundary, not a cryptographic one.
/// A `true` answer changes nothing about the vault: same keys, same session, no unlock. An attacker
/// who can read this process's memory bypasses the gate by reading memory, not by answering it.
/// Saying so is the point — a gate described as stronger than it is gets relied on for the wrong
/// thing.
///
/// **Why the grants live here and not in `RootViewModel`.** They have to die with the session, in
/// the same teardown that clears the reprompt grants. Keeping them next to the thing that issues
/// them, and giving `RootViewModel` one call to make — `revokeAll()` — means there is one answer to
/// "how long does a grant last" rather than two that can drift.
@MainActor
final class SSHAgentAuthorizer: ObservableObject {

    // MARK: - Request

    /// One signature waiting on the master password.
    ///
    /// `id` is not decoration: two clients can ask for the same key before either is answered, and
    /// resolving by key would then resume the wrong continuation. The continuation itself is
    /// deliberately **not** a field here — this value is published state, and an action in
    /// published state outlives the request if the sheet is dismissed another way.
    struct Request: Identifiable, Equatable {
        let id: UUID
        let itemId: String
        let itemName: String
        /// The requesting process's name, when the kernel would say. Nil is shown as "an
        /// application" rather than guessed at.
        let process: String?
    }

    /// The request currently on screen, if any.
    @Published private(set) var pending: Request?
    /// A wrong password, or a check that could not run. Shown in the sheet, which stays open.
    @Published private(set) var error: String?
    @Published private(set) var isVerifying = false

    private var granted: Set<String> = []
    private var queue: [(request: Request, continuation: CheckedContinuation<Bool, Never>)] = []

    private let verifyMasterPassword: any VerifyMasterPasswordUseCase
    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "SSHAgent")

    /// How long the request **on screen** may go unanswered.
    ///
    /// Without a deadline an ignored prompt parks the agent's connection thread forever: the responder
    /// is suspended on this continuation, `SSHAgentServer.awaitResponse(to:)` is suspended on the
    /// responder, and the `git` that asked hangs until the app is quit. Two minutes is long enough to
    /// notice the sheet, read which key is being asked for and type a master password, and short
    /// enough that a terminal someone walked away from is released before they come back.
    ///
    /// Timed from promotion, not arrival: a request queued behind one the user is still reading has
    /// not been shown yet, and refusing it unseen would be the app timing out its own prompt queue.
    /// Injected for the same reason — a test cannot wait two minutes.
    private let answerWindow: TimeInterval

    init(verifyMasterPassword: any VerifyMasterPasswordUseCase, answerWindow: TimeInterval = 120) {
        self.verifyMasterPassword = verifyMasterPassword
        self.answerWindow         = answerWindow
    }

    // MARK: - Asking

    /// Whether signing with `itemId` still requires the master password.
    func needsAuthorization(for itemId: String) -> Bool { !granted.contains(itemId) }

    /// How many requests are waiting, including the one on screen.
    ///
    /// Exposed rather than left private because the interesting queue property — a second request
    /// *arrived and is waiting* — is invisible in `pending`, which deliberately still shows the
    /// first one. A test that asserted on a timer instead would pass whether or not the second
    /// request ever reached the queue.
    var waitingCount: Int { queue.count }

    /// Whether one signature may be made with `identity`, asking for the master password if this
    /// session has not already been given it for that key.
    ///
    /// Called from the agent's connection thread, which is not the main actor — hence `async` and
    /// the hop. Returns `false` for a refusal **and** for a cancellation: the two are the same
    /// answer to the caller, and the protocol has no way to tell them apart anyway.
    func authorize(_ identity: SSHAgentIdentity, requestedBy process: String?) async -> Bool {
        // The common case on a second `git push`: no prompt, and no queue entry either.
        guard !granted.contains(identity.itemId) else { return true }

        let request = Request(id: UUID(),
                              itemId: identity.itemId,
                              itemName: identity.comment,
                              process: process)

        return await withCheckedContinuation { continuation in
            queue.append((request, continuation))
            promoteNextIfIdle()
            logger.info("SSH agent asked for the master password for \(identity.itemId, privacy: .public)")
        }
    }

    // MARK: - Answering

    /// Checks `password` and, when it is the master password, grants the key it was asked for.
    ///
    /// A wrong password is not thrown and does not close the sheet: closing on a wrong answer would
    /// be indistinguishable from a cancel, and the user would not know which happened.
    func submit(_ password: Data) {
        guard let request = pending else { return }
        isVerifying = true
        error       = nil
        let useCase = verifyMasterPassword

        Task { @MainActor [weak self] in
            // A local copy so these bytes can be zeroed here; the caller zeroes its own. Capturing
            // the parameter directly would be a mutable capture in concurrently-executing code.
            var buffer = password
            defer {
                buffer.zeroize()
                self?.isVerifying = false
            }
            do {
                guard try await useCase.execute(buffer) else {
                    self?.error = L("That is not the master password for this account.")
                    return
                }
                // The request may have been refused while the password was being checked — a lock
                // can land in the middle of this `await`. Granting then would hand out permission
                // the lock had already taken back, which is the one thing this type must not do.
                guard let self, self.queue.contains(where: { $0.request.id == request.id }) else {
                    self?.logger.info("SSH agent dropped a grant: the request was refused while the password was checked")
                    return
                }
                self.grant(request.itemId)
            } catch {
                // "Could not check" is shown, not swallowed: a sheet that stays open with no
                // message is indistinguishable from one that is broken.
                self?.error = error.localizedDescription
            }
        }
    }

    /// Closes the sheet having granted nothing.
    func cancel() {
        guard let request = pending else { return }
        refuse(id: request.id)
    }

    /// Refuses everything waiting and forgets every grant.
    ///
    /// Called from `lockVault()` and `signOut()`, in the same teardown that clears the reprompt
    /// grants. A grant is permission to use key material, so it must not outlive the caches that
    /// hold that material.
    ///
    /// Resuming every continuation is not tidiness: a request left suspended is a socket thread
    /// blocked forever and a prompt that can never be answered, on top of a `git` that hangs.
    func revokeAll() {
        granted.removeAll()
        let waiting = queue
        queue.removeAll()
        pending     = nil
        error       = nil
        isVerifying = false
        for entry in waiting { entry.continuation.resume(returning: false) }
    }

    // MARK: - Queue

    /// Shows the next request if the sheet is free, and starts its answer window.
    private func promoteNextIfIdle() {
        guard pending == nil, let first = queue.first else { return }
        pending     = first.request
        error       = nil
        isVerifying = false
        armDeadline(for: first.request.id)
    }

    /// Refuses the request if it is still the one on screen when the window closes.
    ///
    /// No task handle is kept, because none is needed: the expiry re-checks `pending?.id`, so a task
    /// whose request was answered, replaced or revoked simply finds nothing to do. Cancelling tasks on
    /// every transition would be a second bookkeeping trail that can disagree with the first.
    private func armDeadline(for id: UUID) {
        let window = answerWindow
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard let self, self.pending?.id == id else { return }
            self.logger.info("SSH agent prompt went unanswered; the request was refused")
            self.refuse(id: id)
        }
    }

    /// Grants one key for the rest of the session, and answers every request already waiting on it.
    ///
    /// The second half matters: two clients can ask for the same key before either is answered, and
    /// making the user answer twice for one key would be a prompt they cannot tell apart from a
    /// bug.
    private func grant(_ itemId: String) {
        granted.insert(itemId)

        let answered = queue.filter { $0.request.itemId == itemId }
        queue.removeAll { $0.request.itemId == itemId }
        pending     = nil
        error       = nil
        promoteNextIfIdle()
        for entry in answered { entry.continuation.resume(returning: true) }
    }

    private func refuse(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.request.id == id }) else { return }
        let entry = queue.remove(at: index)
        // Only the request on screen owns the sheet. Refusing one that is still queued behind it must
        // not close the prompt the user is reading — which is reachable now that a timeout can fire on
        // a request nobody has seen yet, and was not before `refuse` had a single caller.
        if pending?.id == id {
            pending = nil
            error   = nil
        }
        promoteNextIfIdle()
        entry.continuation.resume(returning: false)
    }
}
