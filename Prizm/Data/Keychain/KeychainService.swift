import Foundation
import Security
import os.log

// MARK: - Errors

/// Errors that can be thrown by KeychainService operations.
nonisolated enum KeychainError: Error, Equatable {
    /// No item exists for the requested key.
    case itemNotFound
    /// The Keychain returned an unexpected status code.
    case unexpectedStatus(OSStatus)
    /// Keychain returned data in an unexpected format.
    case invalidData
}

// Worded, with the status number kept in the message. `itemNotFound` is control flow rather than a
// report — callers probe with `try?` — but `unexpectedStatus` reaches a settings screen when the
// server-trust store cannot be read, and there the number is the only thing a user can quote.
nonisolated extension KeychainError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return L("The stored item was not found in the Keychain.")
        case .unexpectedStatus(let status):
            return L("The Keychain returned an unexpected result (%d).", Int(status))
        case .invalidData:
            return L("The stored Keychain data could not be read.")
        }
    }
}

// MARK: - Protocol

/// Provides read, write, and delete access to the macOS Keychain.
///
/// Keys are stored as generic passwords (`kSecClassGenericPassword`) scoped to the
/// `com.prizm` service, accessible only when the device is unlocked and
/// not backed up to iCloud (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
///
/// The protocol exposes a per-key API, but the implementation deliberately does not
/// map keys to Keychain items one-to-one — see `KeychainServiceImpl`.
///
/// All operations are synchronous and throw `KeychainError` on failure.
///
/// `Sendable` because a TLS challenge is evaluated off the main actor and reads trust material
/// through this protocol. `KeychainServiceImpl` earns it: every stored property is immutable and
/// it serialises its own read-modify-write cycle behind an `NSLock`.
protocol KeychainService: Sendable {
    /// Write `data` for `key`, replacing any existing value.
    func write(data: Data, key: String) throws
    /// Read and return the data stored for `key`.
    /// - Throws: `KeychainError.itemNotFound` if no item exists.
    func read(key: String) throws -> Data
    /// Delete the item for `key`.  No-ops silently when the item does not exist.
    func delete(key: String) throws
}

// MARK: - Implementation

/// Concrete Keychain implementation using Security.framework SecItem APIs.
///
/// ## One item, many keys
///
/// Every logical key lives in a **single** generic-password item: a JSON object whose
/// values are base64-encoded blobs. `write` / `read` / `delete` are therefore
/// read-modify-write operations over that one record.
///
/// This is not an optimisation — it is a correctness requirement on the legacy login
/// keychain. macOS grants access per *(binary code signature × individual item)*, so an
/// app that spreads its state over N items raises N separate authorisation dialogs on
/// first launch after a rebuild, each demanding the **login keychain password** (the
/// macOS account password — *not* the vault master password). Prizm used to store nine
/// items and asked nine times. One item means at most one prompt.
///
/// The trade-off is that a single record now holds everything: it is written whole, so
/// a partially-written store is impossible, and losing it costs the cached session
/// (device ID, tokens, email, KDF params) — never vault data, which lives on the server.
///
/// ## Keychain selection
///
/// Items go to the **data protection keychain** (`kSecUseDataProtectionKeychain: true`)
/// when available, which uses entitlement-based access control instead of per-binary
/// code-signature ACLs: any build signed with the same Team ID and the
/// `keychain-access-groups` entitlement can read existing items, so no prompt ever
/// appears. Ad-hoc signed builds have no Team ID, and `keychain-access-groups` is a
/// *restricted* entitlement that makes AMFI kill the process, so they fall back to the
/// legacy login keychain, where the prompt is unavoidable — just now at most once.
///
/// The item carries:
/// - `kSecAttrService`: `"com.prizm"` — scopes items to this app.
/// - `kSecAttrAccount`: `KeychainServiceImpl.storeAccount` — the single store.
/// - `kSecAttrAccessible`: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — secrets
///   are available only while the device is unlocked and are not backed up to iCloud
///   or migrated to new devices (per Bitwarden Security Whitepaper §5: Keychain Storage).
final class KeychainServiceImpl: KeychainService {

    /// Account name of the single generic-password item that holds every key.
    ///
    /// Changing this value orphans the existing store: the app would start at the
    /// sign-in screen and write a fresh one. Kept stable on purpose.
    static let storeAccount = "store"

    private let service: String
    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "KeychainService")

    /// When `true`, routes all queries through the modern data protection keychain
    /// (`kSecUseDataProtectionKeychain`), which requires the `keychain-access-groups`
    /// entitlement. Auto-detected at init: unsigned builds (e.g. Homebrew) receive
    /// `false` and fall back to the legacy login keychain.
    /// Pass an explicit value in tests to bypass the probe.
    private let useDataProtectionKeychain: Bool

    /// Serialises read-modify-write cycles on the shared store.
    ///
    /// The store is a single record, so two concurrent `write` calls that each
    /// read-modify-write would silently drop one of the two keys. `KeychainService` is
    /// called from `@MainActor` code today, but the protocol makes no isolation promise,
    /// and a lost token would be an unpleasant failure to debug.
    private let lock = NSLock()

    /// In-memory view of the store: `key` → base64-encoded value.
    private typealias Store = [String: String]

    /// - Parameters:
    ///   - service: Keychain service name. Override in tests to keep test data out of
    ///     the app's real store (a shared store means a test run would otherwise
    ///     rewrite the live session).
    ///   - useDataProtectionKeychain: `nil` probes the entitlement; pass an explicit
    ///     value to skip the probe.
    init(service: String = "dev.lemonevo.vitrine", useDataProtectionKeychain: Bool? = nil) {
        self.service = service
        if let explicit = useDataProtectionKeychain {
            self.useDataProtectionKeychain = explicit
            return
        }
        // Probe whether the data protection keychain is *writable*. Unsigned builds
        // (Homebrew, teamless local builds) lack the `keychain-access-groups`
        // entitlement and must fall back to the legacy login keychain — #60.
        //
        // The probe must be a write, not a read: as of macOS 26.5,
        // SecItemCopyMatching no longer enforces the entitlement and returns
        // errSecItemNotFound where SecItemAdd fails with -34018
        // (errSecMissingEntitlement). A read probe therefore arms the
        // data-protection path on unsigned builds and the first real write —
        // storing the device identifier during sign-in — fails with the exact
        // error #60 was meant to prevent.
        //
        // The probe item mirrors the attributes of real writes (same service and
        // kSecAttrAccessible) so it exercises the same policy checks, and is
        // deleted immediately on success.
        var probe: [CFString: Any] = [
            kSecClass:                     kSecClassGenericPassword,
            kSecAttrService:               service,
            kSecAttrAccount:               "__entitlement-probe__",
            kSecAttrAccessible:            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
            kSecValueData:                 Data("probe".utf8),
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        // Only known-good statuses confirm the entitlement: errSecSuccess, or
        // errSecDuplicateItem from a probe item a previous crashed run left behind.
        // Any other code (e.g. errSecInteractionNotAllowed while the keychain is
        // locked) selects the legacy fallback rather than risking -34018 on real
        // writes.
        let entitled = (status == errSecSuccess || status == errSecDuplicateItem)
        self.useDataProtectionKeychain = entitled
        if entitled {
            probe[kSecValueData] = nil
            let deleteStatus = SecItemDelete(probe as CFDictionary)
            if deleteStatus != errSecSuccess {
                logger.error("Failed to delete entitlement probe item: status \(deleteStatus)")
            }
        } else {
            logger.info("Data protection keychain unavailable (status \(status)) — falling back to login keychain")
        }
    }

    /// Returns the base Keychain query dictionary for `account`.
    ///
    /// `kSecUseDataProtectionKeychain: true` routes all queries to the modern data
    /// protection keychain. The access group is not set explicitly — for sandboxed apps,
    /// Security.framework automatically uses the first entry in the `keychain-access-groups`
    /// entitlement (`$(AppIdentifierPrefix)com.prizm`). Setting it explicitly here
    /// would require embedding the resolved Team ID in source code.
    private func baseQuery(for account: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain] = true
        }
        return query
    }

    // MARK: - Store primitives

    /// Reads and decodes the store, returning an empty store when no item exists yet.
    ///
    /// Must be called with `lock` held.
    private func loadStore() throws -> Store {
        var query = baseQuery(for: Self.storeAccount)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            do {
                return try JSONDecoder().decode(Store.self, from: data)
            } catch {
                // A store we cannot decode is not recoverable in place — surfacing it
                // loudly beats silently returning `[:]`, which would make every key
                // look absent and quietly sign the user out.
                logger.error("Keychain store is unreadable: \(String(describing: error), privacy: .public)")
                throw KeychainError.invalidData
            }
        case errSecItemNotFound:
            return [:]
        default:
            logger.error("Keychain error: status \(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Encodes and writes the store as the single item.
    ///
    /// Must be called with `lock` held.
    private func saveStore(_ store: Store) throws {
        let data = try JSONEncoder().encode(store)
        try upsert(data: data, account: Self.storeAccount)
    }

    // MARK: Write

    /// Upserts `data` for `account` using SecItemAdd, or SecItemUpdate on a duplicate.
    ///
    /// Uses an upsert pattern: attempt to add first; if `errSecDuplicateItem` is returned,
    /// update the existing item.  This avoids a read-before-write and is the recommended
    /// pattern per Apple's "Storing Keys in the Keychain" technical note.
    private func upsert(data: Data, account: String) throws {
        var query = baseQuery(for: account)
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData]      = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)

        if addStatus == errSecSuccess {
            logger.debug("Keychain write: \(account, privacy: .public)")
            return
        }

        if addStatus == errSecDuplicateItem {
            let updateAttributes: [CFString: Any] = [
                kSecValueData:      data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(
                baseQuery(for: account) as CFDictionary,
                updateAttributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                logger.error("Keychain error: status \(updateStatus)")
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            logger.debug("Keychain write: \(account, privacy: .public)")
            return
        }

        logger.error("Keychain error: status \(addStatus)")
        throw KeychainError.unexpectedStatus(addStatus)
    }

    /// Stores `data` under `key` in the shared store, creating the item on first write.
    func write(data: Data, key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var store = try loadStore()
        store[key] = data.base64EncodedString()
        try saveStore(store)
    }

    // MARK: Read

    /// Returns the data stored for `key`, or throws `KeychainError.itemNotFound`.
    func read(key: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let store = try loadStore()
        guard let encoded = store[key] else {
            throw KeychainError.itemNotFound
        }
        guard let data = Data(base64Encoded: encoded) else {
            throw KeychainError.invalidData
        }
        return data
    }

    // MARK: Delete

    /// Removes `key` from the shared store.  If the key does not exist
    /// (`errSecItemNotFound`), this method returns silently — callers do not need to
    /// check existence first.
    ///
    /// When the last key is removed the backing item is deleted outright, so a signed-out
    /// app leaves no trace in the keychain.
    func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var store = try loadStore()
        guard store.removeValue(forKey: key) != nil else {
            return
        }

        if store.isEmpty {
            let status = SecItemDelete(baseQuery(for: Self.storeAccount) as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                logger.debug("Keychain delete: \(Self.storeAccount, privacy: .public) (last key removed)")
                return
            default:
                logger.error("Keychain error: status \(status)")
                throw KeychainError.unexpectedStatus(status)
            }
        }

        try saveStore(store)
    }
}
