import Foundation
import Security
import LocalAuthentication
import os.log

/// Concrete Keychain implementation for biometric-gated secrets.
///
/// Items are stored as generic passwords. In the default `.systemEnforced` mode they
/// are protected by a `SecAccessControl` with `.biometryCurrentSet`, which means:
/// - Reading requires a successful biometric evaluation (Touch ID / Face ID).
/// - The item is invalidated if the user adds or removes a fingerprint.
///
/// That mode uses `kSecUseDataProtectionKeychain: true` so the access group is inferred
/// from the `keychain-access-groups` entitlement (`$(AppIdentifierPrefix)com.prizm`),
/// ensuring the item is not accessible to other apps or processes
/// (Constitution Security Requirement property 3).
///
/// A build without a real signing Team ID cannot carry that entitlement, and macOS then
/// refuses **every** biometric item write with `errSecMissingEntitlement` (-34018). Such
/// a build falls back to `.appEnforced`: the item moves to the legacy login Keychain and
/// Prizm evaluates the policy itself. The prompt is the same; only the enforcer changes.
/// See `preferred()`.
///
/// `kSecAttrSynchronizable` is never set in either mode — the item is device-only, never
/// backed up or synced to iCloud (Constitution Security Requirement property 1).
///
/// Standards: design Decision 2 (`.biometryCurrentSet`), Decision 3 (separate service).
final class BiometricKeychainServiceImpl: BiometricKeychainService {

    private let service = "com.prizm.biometric"
    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "BiometricKeychain")
    private let mode: BiometricStorageMode
    private let evaluator: any BiometricPolicyEvaluating

    init(
        mode: BiometricStorageMode = .systemEnforced,
        evaluator: any BiometricPolicyEvaluating = SystemBiometricPolicyEvaluator()
    ) {
        self.mode = mode
        self.evaluator = evaluator
    }

    // MARK: - Capability

    /// The strongest mode this build can actually use.
    ///
    /// System enforcement is tried first and is what a properly signed build gets. It is
    /// dropped only when macOS refuses the entitlement, which is the same reason a
    /// `.biometryCurrentSet` item cannot be created — so the probe below is the whole
    /// decision, and it never has to be revisited at runtime.
    static func preferred() -> BiometricKeychainServiceImpl {
        BiometricKeychainServiceImpl(
            mode: systemEnforcementAvailable ? .systemEnforced : .appEnforced
        )
    }

    /// Whether this build can create biometric-protected Keychain items at all.
    ///
    /// Biometric storage needs the `keychain-access-groups` entitlement twice over:
    /// once for `kSecUseDataProtectionKeychain` and again for a `.biometryCurrentSet`
    /// `SecAccessControl`. Only a build signed with a real Team ID can carry it. An
    /// ad-hoc signed build fails **every** write with `errSecMissingEntitlement`
    /// (-34018), which is why the fallback mode exists.
    ///
    /// The probe deliberately omits `kSecAttrAccessControl`. The entitlement check is
    /// what fails first, and a `.biometryCurrentSet` item cannot be created only to be
    /// deleted again — probing with the ACL risks raising a Touch ID prompt just for
    /// opening Settings.
    static var systemEnforcementAvailable: Bool {
        var probe: [CFString: Any] = [
            kSecClass:                     kSecClassGenericPassword,
            kSecAttrService:               "com.prizm.biometric",
            kSecAttrAccount:               "__entitlement-probe__",
            kSecAttrAccessible:            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
            kSecValueData:                 Data("probe".utf8),
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            return false
        }
        probe[kSecValueData] = nil
        SecItemDelete(probe as CFDictionary)
        return true
    }

    var isSystemEnforced: Bool { mode == .systemEnforced }

    // MARK: - Base query

    private func baseQuery(for key: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        if mode == .systemEnforced {
            query[kSecUseDataProtectionKeychain] = true
        }
        return query
    }

    /// Creates the `SecAccessControl` for `.biometryCurrentSet`.
    ///
    /// `.biometryCurrentSet` invalidates the item when biometric enrollment changes,
    /// preventing a newly added fingerprint from silently accessing the vault key
    /// (design Decision 2).
    private func makeBiometricAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            let cfError = error?.takeRetainedValue()
            logger.error("SecAccessControl creation failed: \(String(describing: cfError), privacy: .public)")
            throw KeychainError.unexpectedStatus(errSecParam)
        }
        return access
    }

    // MARK: - Write

    func writeBiometric(data: Data, key: String) throws {
        var query = baseQuery(for: key)
        switch mode {
        case .systemEnforced:
            query[kSecAttrAccessControl] = try makeBiometricAccessControl()
        case .appEnforced:
            // No access control — that is precisely what needs the entitlement we do not
            // have. Device-only and never synced, so the vault key still cannot leave
            // this Mac (Constitution Security Requirement property 1).
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        query[kSecValueData] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)

        if addStatus == errSecSuccess {
            logger.debug("Biometric keychain write: \(key, privacy: .public)")
            return
        }

        if addStatus == errSecDuplicateItem {
            // Delete + re-add because SecItemUpdate cannot change access control flags.
            try deleteBiometric(key: key)
            let retryStatus = SecItemAdd(query as CFDictionary, nil)
            guard retryStatus == errSecSuccess else {
                logger.error("Biometric keychain retry write failed: status \(retryStatus)")
                throw KeychainError.unexpectedStatus(retryStatus)
            }
            logger.debug("Biometric keychain write (replaced): \(key, privacy: .public)")
            return
        }

        logger.error("Biometric keychain write failed: status \(addStatus)")
        throw KeychainError.unexpectedStatus(addStatus)
    }

    // MARK: - Read

    func readBiometric(key: String) async throws -> Data {
        // Evaluating here rather than letting `SecItemCopyMatching` delegate to the
        // security-agent subprocess keeps the prompt and the read on one context: in
        // `.systemEnforced` mode that context is then handed to `SecItemCopyMatching` so
        // it does not ask a second time. In `.appEnforced` mode this evaluation *is* the
        // gate. Either way the dialog is the system's own, raised by `evaluatePolicy`.
        let context = try await evaluator.evaluate(reason: Self.promptReason)
        return try read(key: key, context: context)
    }

    /// The line the system prompt shows.
    ///
    /// Names the sensor, because the dialog appears over every other app and "Unlock" alone
    /// does not say what is asking. Sensor names are Apple product names and stay untranslated.
    static var promptReason: String {
        let sensor: String
        switch LAContext().biometryType {
        case .touchID: sensor = "Touch ID"
        case .faceID:  sensor = "Face ID"
        default:       sensor = L("Biometrics")
        }
        return L("Open your Vitrine vault with %@", sensor)
    }

    /// Shared read path. `context` has already been authenticated by the caller.
    private func read(key: String, context: LAContext) throws -> Data {
        var query = baseQuery(for: key)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        if mode == .systemEnforced {
            // Reuse the evaluation we just performed instead of letting the security
            // agent raise a second, modal prompt. Meaningless without an access control,
            // so it is omitted in `.appEnforced` mode.
            query[kSecUseAuthenticationContext] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            logger.error("Biometric keychain read failed: status \(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    func deleteBiometric(key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            logger.debug("Biometric keychain delete: \(key, privacy: .public)")
            return
        default:
            logger.error("Biometric keychain delete failed: status \(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
