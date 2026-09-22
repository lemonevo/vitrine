import AppKit
import Foundation
import os.log

// MARK: - AttachmentTempFileManager

/// Tracks temporary files written during attachment "Open" and cleans them up.
///
/// Placed in the App layer because it imports `AppKit` (`NSApplication`) per the
/// Clean Architecture constraint in CLAUDE.md (§II). `AttachmentRowViewModel` in the
/// Presentation layer depends on the `TempFileManaging` protocol, never this concrete type.
///
/// Cleanup strategy:
/// - Each registered file has a 30-second deletion deadline.
/// - `cleanup()` is called on every foreground transition (via `NSApplication.didBecomeActiveNotification`)
///   and by a scheduled Task inside `AttachmentRowViewModel` 30 s after registration.
/// - `removeAllForTermination()` runs on `NSApplication.willTerminateNotification` and ignores the
///   deadline — see that method for why only quitting makes that correct.
/// - On cleanup, the file is overwritten with zeros then deleted (Constitution §III).
///
/// Not guaranteed to run: a force-quit, a crash, or a power loss skips termination handlers, and the
/// files survive until the next launch's sweeps or the system's own temp-directory cleanup.
///
/// Thread safety: `entries` is protected by a `Lock` because `register` and `cleanup`
/// may be called from background Tasks or notification callbacks.
final class AttachmentTempFileManager: TempFileManaging, @unchecked Sendable {

    // MARK: - Types

    private struct Entry {
        let url:         URL
        let deleteAfter: Date
    }

    // MARK: - State

    private var entries: [Entry] = []
    private let lock = NSLock()

    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "attachments")

    // MARK: - Init

    init() {
        // Register for foreground notification to trigger cleanup whenever the app
        // comes to the front — catches the common case where the user switches back
        // to Prizm after opening an attachment in another app.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        // Quitting is a different job from the timed sweep: the deadline is enforced by a timer that
        // dies with the process, so any file still registered at termination is plaintext that would
        // outlive every mechanism meant to remove it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func appWillTerminate() {
        removeAllForTermination()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - TempFileManaging

    /// Records `url` with a 30-second deletion deadline.
    func register(url: URL) {
        register(url: url, deleteAfter: Date().addingTimeInterval(30))
    }

    /// Records `url` with a custom deletion deadline.
    ///
    /// Exposed for testing — allows tests to register a file with a deadline in the past
    /// without sleeping 30 seconds (Constitution §VI, YAGNI: no separate Clock injection).
    func register(url: URL, deleteAfter: Date) {
        lock.lock()
        entries.append(Entry(url: url, deleteAfter: deleteAfter))
        lock.unlock()
        logger.debug("tempFile registered: \(url.lastPathComponent, privacy: .public)")
    }

    /// Zeroes and deletes all entries whose deadline has passed.
    func cleanup() {
        let now = Date()
        var expired: [Entry] = []

        lock.lock()
        entries = entries.filter { entry in
            if entry.deleteAfter <= now {
                expired.append(entry)
                return false
            }
            return true
        }
        lock.unlock()

        for entry in expired {
            zeroAndDelete(entry.url)
        }
    }

    /// Zeroes and deletes **every** entry, deadline or not.
    ///
    /// Only correct at termination. The deadline exists so an attachment the user still has open in
    /// another app is not pulled out from under them; once this process is ending there is no timer
    /// left to honour it, and no caller either, so waiting would mean leaving plaintext behind.
    func removeAllForTermination() {
        lock.lock()
        let all = entries
        entries.removeAll()
        lock.unlock()

        for entry in all {
            zeroAndDelete(entry.url)
        }
        if !all.isEmpty {
            logger.info("Quit cleanup: removed \(all.count, privacy: .public) decrypted attachment temp file(s)")
        }
    }

    // MARK: - Private

    /// Overwrites the file at `url` with zeros then deletes it.
    ///
    /// - Security goal: reduces (but does not guarantee elimination of) plaintext attachment data on disk (APFS copy-on-write may retain original blocks; FileVault is recommended)
    ///   after the open action completes (Constitution §III).
    private func zeroAndDelete(_ url: URL) {
        do {
            // Overwrite with zero bytes of the same size.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                let zeros = Data(repeating: 0, count: size)
                try zeros.write(to: url)
            }
            try FileManager.default.removeItem(at: url)
            logger.debug("tempFile zeroed and deleted: \(url.lastPathComponent, privacy: .public)")
        } catch {
            // Best-effort: if we can't zero or delete, log and continue.
            logger.error("tempFile cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func appDidBecomeActive() {
        cleanup()
    }
}
