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
    ///
    /// **Written in chunks rather than as one buffer.** The direct form —
    /// `Data(repeating: 0, count: size)` followed by `write(to:)` — allocates a second copy of the
    /// entire file. For the 500 MB this app permits that is a several-hundred-megabyte allocation,
    /// and it happens on the main thread: this runs from `willTerminate` as well as from the sweep
    /// and the foreground hook. The bytes written are identical; the allocation is what changes.
    ///
    /// **Why this is still synchronous.** The remaining cost is writing `size` bytes, and moving it
    /// off the main thread would mean the quit path could return before the overwrite finished —
    /// trading a guarantee this type exists to make, on the one path where the process is about to
    /// end and nothing can be retried, for responsiveness. The allocation was the part that turned
    /// "a large write" into "a large write plus a second copy of the file in memory"; it is gone,
    /// and the write itself is left where it can be awaited.
    private func zeroAndDelete(_ url: URL) {
        do {
            // Overwrite with zero bytes of the same size.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }

                // Opens at offset zero without truncating, so writing `size` bytes replaces the
                // whole file. The buffer is a fixed chunk regardless of how large the file is.
                let chunk = Data(repeating: 0, count: Self.zeroChunkSize)
                var remaining = size
                while remaining > 0 {
                    let count = min(remaining, chunk.count)
                    try handle.write(contentsOf: chunk.prefix(count))
                    remaining -= count
                }
            }
            try FileManager.default.removeItem(at: url)
            logger.debug("tempFile zeroed and deleted: \(url.lastPathComponent, privacy: .public)")
        } catch {
            // Best-effort: if we can't zero or delete, log and continue.
            logger.error("tempFile cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The zero-overwrite buffer. 1 MiB: large enough that the syscall count for a 500 MB file is
    /// 500 rather than millions, small enough that the allocation is not worth thinking about.
    private static let zeroChunkSize = 1 << 20

    @objc private func appDidBecomeActive() {
        cleanup()
    }
}
