import Foundation

/// Identifies one unlocked session, so that work started in it can be refused once it has ended.
///
/// A lock or a sign-out destroys the key material and empties the vault store. Neither can reach
/// work that is already in flight: a sync sitting on an `await` returns afterwards and writes —
/// into the store, into the key caches, and into the view model. The result is a session the user
/// believes is closed, with its plaintext back in memory and its keys back in the caches.
///
/// So every session-ending path advances an epoch, and every long-running operation captures the
/// epoch it began in and refuses to apply its result if it has moved.
///
/// **Why a counter and not a flag.** A boolean "is locked" answers the wrong question. Locking and
/// unlocking again starts a *new* session that is also unlocked, and a sync left over from the
/// previous one must not be able to write into it. Only a monotonic token distinguishes "still the
/// same session" from "unlocked again", and a token is never reissued.
///
/// **Why `@MainActor`.** Capturing the token must be synchronous, or the capture is itself a race:
/// a view model that reads the epoch inside a `Task` can be pre-empted between the moment it decides
/// to sync and the moment it captures, and a lock landing in that gap would give the sync the *new*
/// session's token — so it would apply its result to a session it does not belong to, which is the
/// exact failure this type exists to prevent. `@MainActor` matches the isolation of both the lock
/// paths and the view model, so those reads are immediate; the sync repository is an actor and
/// reaches it with an `await`, which is the right trade for the one consumer that is not on the main
/// actor.
@MainActor
final class SessionEpoch {

    private var value = 0

    /// The token for the current session. Capture this before awaiting anything.
    func current() -> Int { value }

    /// Whether `token` belongs to the session that is still running.
    func isCurrent(_ token: Int) -> Bool { token == value }

    /// Ends the current session. Called by every path that locks or signs out, and called *before*
    /// that path's own teardown: work completing during the teardown must already see the new epoch,
    /// or it would repopulate a store that is about to be, or has just been, cleared.
    func advance() { value += 1 }
}
