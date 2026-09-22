import AppKit
import os

// MARK: - SecretClipboard

/// The one place this app puts a secret on the system clipboard, and the one place that knows whether
/// what is there now is still ours.
///
/// **Why a shared instance rather than an injected collaborator.** The pasteboard is a process-global
/// resource; giving each view model its own guard would mean two views each believing they still own
/// it. The vault browser and the password generator both copy secrets, and the second copy invalidates
/// the first one's claim — which is only visible from a single point.
///
/// **What this is for.** Every copy schedules a timed clear, and that clear checks "is our value still
/// there" before wiping, so it never destroys something the user copied afterwards. The same rule has
/// to hold when the app quits: the timer dies with the process, so a password copied a moment before
/// ⌘Q would otherwise sit on the clipboard indefinitely. `clearIfStillOurs()` is that check, run from
/// the termination hook instead of from a timer.
@MainActor
final class SecretClipboard {

    static let shared = SecretClipboard()

    /// The value we last wrote. Only the most recent one can still be on the clipboard — every write
    /// clears the pasteboard first — so one slot is enough, and it is the whole truth.
    private(set) var ours: String?

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "SecretClipboard")

    /// Injectable so tests do not fight the real clipboard.
    ///
    /// `NSPasteboard.general` is shared by every process on the login session, and the suite runs test
    /// classes in parallel processes — asserting on it from here would be the same cross-process
    /// coupling that made the `UserDefaults` sort-key tests flaky. Tests pass a named pasteboard
    /// instead, which is a real pasteboard the rest of the system never sees.
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        // The timed clear in each view model is a Task, and Tasks do not survive ⌘Q. Without this the
        // last secret copied before quitting stays on the clipboard indefinitely.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main thread; `assumeIsolated` states that rather than re-dispatching,
            // because a `Task { @MainActor }` here would be queued behind the exit it is meant to
            // happen before.
            MainActor.assumeIsolated {
                self?.clearIfStillOurs()
            }
        }
    }

    /// Writes `value` to the pasteboard and records it as ours.
    func write(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        ours = value
    }

    /// Whether the clipboard still holds exactly this value — the check the timed clear uses, and the
    /// one a caller must make before wiping.
    func stillHolds(_ value: String) -> Bool {
        pasteboard.string(forType: .string) == value
    }

    /// Clears the clipboard if and only if the last thing we wrote is still on it.
    ///
    /// Returns whether it cleared, so the caller can log the difference between "nothing of ours was
    /// there" and "we removed it". A value the user copied from another app is theirs to keep; wiping
    /// it on our exit would be the app destroying unrelated data.
    @discardableResult
    func clearIfStillOurs() -> Bool {
        guard let ours, stillHolds(ours) else {
            logger.debug("Quit cleanup: clipboard holds nothing we put there")
            return false
        }
        pasteboard.clearContents()
        self.ours = nil
        logger.info("Quit cleanup: cleared the secret we had left on the clipboard")
        return true
    }

    deinit {
        // Not the observation token: a `deinit` is nonisolated and cannot read a main-actor-isolated
        // property, and `removeObserver(self)` drops every observation this object registered.
        NotificationCenter.default.removeObserver(self)
    }
}
