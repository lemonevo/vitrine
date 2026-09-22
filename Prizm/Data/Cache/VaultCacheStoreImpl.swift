import Foundation
import os.log

// MARK: - VaultCacheStoreImpl

/// File-backed `VaultCacheStore`.
///
/// Layout, one directory per account:
///
/// ```
/// <Application Support>/Prizm/vault-cache/<userId>/sync.json        the response body, verbatim
/// <Application Support>/Prizm/vault-cache/<userId>/sync.meta.json   schemaVersion, writtenAt, serverURL
/// ```
///
/// **The body is written first and the metadata second.** Its absence means the cache is unusable,
/// so the only outcome an interrupted write can produce is a fresh body carrying a stale timestamp,
/// which costs nothing. The reverse order would produce a stale body carrying a fresh timestamp — a
/// cache that lies about its own age, which is the one thing the reader depends on.
///
/// **`schemaVersion` is a hard gate.** A future format change must invalidate the file rather than
/// be misparsed by it, and an unreadable cache has to degrade to "no cache" — never to a crash and
/// never to a partly-populated vault.
///
/// **The user id comes from the caller, not the file.** `read` is asked for a specific account and
/// only ever looks in that account's directory, so one account cannot be served another's data even
/// if the files were moved around. The recorded server URL is checked as a second condition: the
/// same user id on a different server is a different vault.
actor VaultCacheStoreImpl: VaultCacheStore {

    // MARK: - Constants

    /// Bumped when the on-disk format changes in a way an older reader would misinterpret.
    ///
    /// A file written by a version this reader does not know is treated as absent.
    static let schemaVersion = 1

    private static let bodyFileName     = "sync.json"
    private static let metadataFileName = "sync.meta.json"
    private static let rootDirectoryName = "vault-cache"

    // MARK: - Dependencies

    private let directory: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.prizm", category: "VaultCacheStore")

    // MARK: - Init

    /// - Parameter directory: The cache root. Defaults to the app's Application Support container;
    ///   tests pass a temporary directory so they never touch a real user's cache.
    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        // Under the App Sandbox this resolves inside the app's own container. If the system will
        // not report a directory the cache is simply disabled: every write fails and logs, every
        // read misses, and the vault behaves exactly as it did before this type existed.
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Prizm", isDirectory: true)
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    // MARK: - VaultCacheStore

    func write(identity: VaultCacheIdentity, payload: VaultCachePayload) async {
        guard let accountDirectory = directoryIfSafe(for: identity) else { return }

        let bodyURL     = accountDirectory.appendingPathComponent(Self.bodyFileName)
        let metadataURL = accountDirectory.appendingPathComponent(Self.metadataFileName)

        let metadata = Metadata(
            schemaVersion: Self.schemaVersion,
            writtenAt:     payload.writtenAt,
            serverURL:     identity.serverURL.absoluteString
        )

        guard let metadataData = try? JSONEncoder().encode(metadata) else {
            // Unreachable for a struct of Int/Double/String, but a silent no-op here would look
            // exactly like a successful write to the caller.
            logger.error("Cache metadata could not be encoded; cache not written")
            return
        }

        do {
            try fileManager.createDirectory(
                at: accountDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // Body first: see the type comment. `.atomic` writes to a sibling temporary file and
            // renames it into place, so a reader never observes a half-written body.
            try writeAtomically(payload.body, to: bodyURL)
            try writeAtomically(metadataData, to: metadataURL)
            logger.info("Vault payload cached (\(payload.body.count, privacy: .public) bytes)")
        } catch {
            // Deliberately not rethrown: the sync that produced this payload succeeded, and it must
            // not be turned into a failure by a disk problem. The previous cache, if any, is
            // untouched — both writes are atomic and the failing one left its file as it was.
            logger.error("Vault payload could not be cached: \(error.localizedDescription, privacy: .public)")
        }
    }

    func read(identity: VaultCacheIdentity) async -> VaultCachePayload? {
        guard let accountDirectory = directoryIfSafe(for: identity) else { return nil }

        let metadataURL = accountDirectory.appendingPathComponent(Self.metadataFileName)
        let bodyURL     = accountDirectory.appendingPathComponent(Self.bodyFileName)

        guard let metadataData = try? Data(contentsOf: metadataURL) else { return nil }

        let metadata: Metadata
        do {
            metadata = try JSONDecoder().decode(Metadata.self, from: metadataData)
        } catch {
            logger.error("Cached payload has unreadable metadata; treating as absent")
            return nil
        }

        guard metadata.schemaVersion == Self.schemaVersion else {
            logger.info("Cached payload was written by schema \(metadata.schemaVersion, privacy: .public); treating as absent")
            return nil
        }
        guard metadata.serverURL == identity.serverURL.absoluteString else {
            logger.info("Cached payload was written for a different server; treating as absent")
            return nil
        }
        guard let body = try? Data(contentsOf: bodyURL) else {
            logger.error("Cached payload body is missing; treating as absent")
            return nil
        }

        return VaultCachePayload(body: body, writtenAt: metadata.writtenAtDate)
    }

    func delete(userId: String) async {
        guard let accountDirectory = safeAccountDirectory(for: userId) else { return }
        guard fileManager.fileExists(atPath: accountDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: accountDirectory)
            logger.info("Cached vault payload deleted for the signed-out account")
        } catch {
            logger.error("Cached vault payload could not be deleted: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    /// Metadata as stored. Dates are `timeIntervalSince1970` rather than an encoded `Date`: a
    /// `Double` round-trips exactly, so a payload read back is `==` to the payload written, which
    /// is what lets tests compare them directly.
    private struct Metadata: Codable {
        let schemaVersion: Int
        let writtenAt:     Double
        let serverURL:     String

        init(schemaVersion: Int, writtenAt: Date, serverURL: String) {
            self.schemaVersion = schemaVersion
            self.writtenAt     = writtenAt.timeIntervalSince1970
            self.serverURL     = serverURL
        }

        var writtenAtDate: Date { Date(timeIntervalSince1970: writtenAt) }
    }

    /// The account directory, or `nil` when the user id is not safe to use as a path component.
    ///
    /// The user id comes from the server, so it is untrusted input that must not be able to escape
    /// the cache root (`../`) or address another account. UUIDs are the only shape Bitwarden
    /// issues, so anything outside that alphabet is refused rather than percent-encoded — a
    /// mangled path would silently become a cache that never hits.
    private func directoryIfSafe(for identity: VaultCacheIdentity) -> URL? {
        safeAccountDirectory(for: identity.userId)
    }

    private func safeAccountDirectory(for userId: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        guard !userId.isEmpty,
              userId.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              userId != ".", userId != ".." else {
            logger.error("Refusing to use an unusable user id as a cache directory name")
            return nil
        }
        return directory.appendingPathComponent(userId, isDirectory: true)
    }

    /// Writes `data` to `url` atomically and restricts it to the owner.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        // `Data.write` creates with the process umask applied; the cache holds the user's whole
        // vault (as ciphertext), so it is narrowed to owner-only explicitly rather than assumed.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
