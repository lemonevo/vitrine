import XCTest
@testable import Prizm

/// Unit tests for `AttachmentTempFileManager` (task 7.2c).
///
/// Uses `register(url:deleteAfter:)` to control cleanup timing without sleeping.
@MainActor
final class AttachmentTempFileManagerTests: XCTestCase {

    private var sut: AttachmentTempFileManager!
    private var createdURLs: [URL] = []

    override func setUp() async throws {
        sut = AttachmentTempFileManager()
    }

    override func tearDown() async throws {
        for url in createdURLs { try? FileManager.default.removeItem(at: url) }
        createdURLs.removeAll()
    }

    // MARK: - Helpers

    /// Creates a real temp file on disk and records it for teardown.
    private func makeTempFile(content: String = "sensitive content") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prizm-tmptest-\(UUID().uuidString).txt")
        try? content.data(using: .utf8)!.write(to: url)
        createdURLs.append(url)
        return url
    }

    // MARK: - register

    func test_register_fileStillExistsBeforeCleanup() {
        let url = makeTempFile()
        sut.register(url: url)
        // cleanup() not called yet — file should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - cleanup — expired deadline

    func test_cleanup_deletesFilesPastDeadline() {
        let url = makeTempFile()
        // Register with a deadline 1 second in the past
        sut.register(url: url, deleteAfter: Date().addingTimeInterval(-1))

        sut.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
            "File should be deleted after its deadline passes")
    }

    func test_cleanup_zerosAndDeletesExpiredFile() throws {
        let sensitiveContent = "sensitive data that should be zeroed"
        let url = makeTempFile(content: sensitiveContent)
        sut.register(url: url, deleteAfter: Date().addingTimeInterval(-1))

        sut.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
            "File should not exist after cleanup")
    }

    /// The overwrite, actually observed. The test above checks only that the file is gone, which is
    /// true whether or not a single byte was written — its name promises more than it asserts.
    /// Nothing can see the zeroed bytes through the normal path, because the same call removes the
    /// file. Making the containing directory unwritable is what makes them visible: the write
    /// succeeds, the unlink does not, and the file is still there to read.
    ///
    /// **Larger than the 1 MiB chunk**, so this also pins the loop that writes the file in chunks
    /// instead of allocating a second copy of it. A loop that stopped after one chunk, or that
    /// miscounted the tail, leaves readable bytes here.
    func test_zeroAndDelete_overwritesEveryByteOfAFileLargerThanOneChunk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prizm-zero-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        createdURLs.append(directory)

        let size    = (1 << 20) + 4096          // one chunk, plus a tail
        let url     = directory.appendingPathComponent("large.bin")
        // `| 1` keeps every byte non-zero: a fixture that is already partly zero could not show
        // whether the overwrite reached it.
        let payload = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 | 1) })
        try payload.write(to: url)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        sut.register(url: url, deleteAfter: Date().addingTimeInterval(-1))
        sut.cleanup()
        // Restored before the assertions so a failure cannot leave an unwritable directory behind
        // for the teardown to trip over. This does not touch the file's contents.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        let remaining = try Data(contentsOf: url)
        XCTAssertEqual(remaining.count, size, "the overwrite must not change the file's length")
        XCTAssertTrue(remaining.allSatisfy { $0 == 0 },
                      "every byte must be zero, including the tail past the first chunk")
    }

    // MARK: - cleanup — unexpired deadline

    func test_cleanup_leavesFilesNotYetExpired() {
        let url = makeTempFile()
        // Register with a deadline 30 seconds in the future
        sut.register(url: url, deleteAfter: Date().addingTimeInterval(30))

        sut.cleanup()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
            "File should remain until its deadline passes")
    }

    func test_cleanup_mixedDeadlines_onlyDeletesExpired() {
        let expiredURL  = makeTempFile(content: "expired")
        let freshURL    = makeTempFile(content: "fresh")

        sut.register(url: expiredURL, deleteAfter: Date().addingTimeInterval(-1))
        sut.register(url: freshURL,   deleteAfter: Date().addingTimeInterval(30))

        sut.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredURL.path),
            "Expired file should be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshURL.path),
            "Fresh file should remain")
    }

    // MARK: - Multiple cleanups

    func test_cleanup_idempotent_doesNotCrashOnMissingFile() {
        let url = makeTempFile()
        sut.register(url: url, deleteAfter: Date().addingTimeInterval(-1))

        sut.cleanup()
        sut.cleanup()  // second call — file already gone, should not throw/crash

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Register + cleanup lifecycle

    func test_registeredFile_isDeletedOnCleanupAfterDeadline() {
        let url = makeTempFile()
        sut.register(url: url)
        // Manually expire by re-registering with past deadline
        sut.register(url: url, deleteAfter: Date().addingTimeInterval(-1))

        sut.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Quit

    /// The deadline exists so an attachment open in another app is not pulled away mid-use. Quitting is
    /// the one moment where waiting for it is wrong: the timer that would have honoured it is going
    /// away with the process, and the plaintext would be left behind forever.
    func test_removeAllForTermination_deletesFilesWhoseDeadlineHasNotArrived() {
        let stillLive = makeTempFile(content: "plaintext that outlives nothing")
        sut.register(url: stillLive, deleteAfter: Date().addingTimeInterval(600))

        sut.removeAllForTermination()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stillLive.path),
                       "A temp file with ten minutes left on its deadline must still go at quit")
    }

    func test_removeAllForTermination_drainsEveryEntry() {
        let first  = makeTempFile()
        let second = makeTempFile()
        sut.register(url: first,  deleteAfter: Date().addingTimeInterval(600))
        sut.register(url: second, deleteAfter: Date().addingTimeInterval(600))

        sut.removeAllForTermination()
        sut.removeAllForTermination()   // idempotent — nothing left to delete, nothing thrown

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }
}
