import Foundation

// MARK: - HealthCheck

/// The five checks the health report runs.
///
/// All five are **local**: they read the already-decrypted vault in memory and make no request, so
/// the report works on a server with no internet access at all (design D6).
///
/// The sixth check every password manager offers — "has this password appeared in a breach?" — is
/// deliberately absent. It requires sending a hash prefix to a third party, which is the one thing a
/// self-hosted vault exists to avoid. The UI says so next to the five checks that did run, so the
/// omission is visible rather than assumed.
nonisolated enum HealthCheck: String, CaseIterable, Identifiable, Sendable {

    case weakPassword
    case reusedPassword
    case stalePassword
    case unsecuredSite
    case missingTwoFactor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weakPassword:     return L("Weak passwords")
        case .reusedPassword:   return L("Reused passwords")
        case .stalePassword:    return L("Stale passwords")
        case .unsecuredSite:    return L("Unsecured websites")
        case .missingTwoFactor: return L("Missing two-factor")
        }
    }

    /// What the check looks for, shown under the heading so the user does not have to infer it from
    /// the name. "Missing two-factor" in particular means something narrower than it sounds.
    var explanation: String {
        switch self {
        case .weakPassword:
            return L("Passwords that score weak or lower.")
        case .reusedPassword:
            return L("Passwords used by more than one item.")
        case .stalePassword:
            return L("Passwords not changed in over two years.")
        case .unsecuredSite:
            return L("Items whose website uses http:// instead of https://.")
        case .missingTwoFactor:
            return L("Logins with a password but no authenticator seed.")
        }
    }
}

// MARK: - HealthFinding

/// One item that failed one check, and why.
nonisolated struct HealthFinding: Identifiable, Equatable, Sendable {

    let itemId: String
    let itemName: String
    /// Why this item is listed: the score it received, the URL that is plaintext, the number of
    /// items sharing its password.
    let detail: String

    /// The item id, which is unique *within* a check. Findings are always presented grouped by
    /// check, so this is a safe list identity. It would collide across checks, and that is
    /// deliberate: an item failing three checks should appear under all three.
    var id: String { itemId }
}

// MARK: - VaultHealthReport

/// The result of running the five checks over a vault.
nonisolated struct VaultHealthReport: Equatable, Sendable {

    private let byCheck: [HealthCheck: [HealthFinding]]

    init(byCheck: [HealthCheck: [HealthFinding]]) {
        self.byCheck = byCheck
    }

    /// The findings for one check, in the order the items were supplied.
    func findings(for check: HealthCheck) -> [HealthFinding] {
        byCheck[check] ?? []
    }

    func count(for check: HealthCheck) -> Int {
        byCheck[check]?.count ?? 0
    }

    var totalFindings: Int {
        byCheck.values.reduce(0) { $0 + $1.count }
    }

    /// True when no check found anything. The UI adds a reassuring banner for this case, but keeps
    /// the five sections: a section that vanished when empty would make "checked, and clean"
    /// indistinguishable from "never checked".
    var isClean: Bool { totalFindings == 0 }

    // MARK: - Running the checks

    /// Runs all five checks over `items`.
    ///
    /// Pure and synchronous: the vault is already decrypted, so there is nothing to await and
    /// nothing to fetch. `now` and `calendar` are parameters rather than ambient state so the
    /// two-year staleness boundary is testable without waiting two years.
    static func make(from items: [VaultItem],
                     estimator: PasswordStrengthEstimator,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> VaultHealthReport {

        let logins = items.compactMap { item -> (item: VaultItem, content: LoginContent)? in
            guard case .login(let content) = item.content else { return nil }
            return (item, content)
        }

        return VaultHealthReport(byCheck: [
            .weakPassword:     weakFindings(logins, estimator: estimator),
            .reusedPassword:   reusedFindings(logins),
            .stalePassword:    staleFindings(logins, now: now, calendar: calendar),
            .unsecuredSite:    unsecuredFindings(logins),
            .missingTwoFactor: missingTwoFactorFindings(logins)
        ])
    }

    // MARK: - The checks
    //
    // Each one takes the same login projection and returns findings in vault order. A login with no
    // password is skipped by all four password-based checks: there is nothing to score, nothing to
    // share, nothing that can go stale, and nothing that would be protected by an authenticator.

    private typealias LoginProjection = [(item: VaultItem, content: LoginContent)]

    private static func weakFindings(_ logins: LoginProjection,
                                     estimator: PasswordStrengthEstimator) -> [HealthFinding] {
        logins.compactMap { entry in
            guard let password = entry.content.password, !password.isEmpty else { return nil }
            let estimate = estimator.estimate(password)
            guard estimate.score <= .weak else { return nil }
            return HealthFinding(itemId: entry.item.id,
                                 itemName: entry.item.name,
                                 detail: L("Scores %@", estimate.score.displayName))
        }
    }

    private static func reusedFindings(_ logins: LoginProjection) -> [HealthFinding] {
        var sharers: [String: Int] = [:]
        for entry in logins {
            guard let password = entry.content.password, !password.isEmpty else { continue }
            sharers[password, default: 0] += 1
        }

        return logins.compactMap { entry in
            guard let password = entry.content.password, !password.isEmpty,
                  let count = sharers[password], count >= 2 else { return nil }
            return HealthFinding(itemId: entry.item.id,
                                 itemName: entry.item.name,
                                 detail: L("Used by %d items", count))
        }
    }

    private static func staleFindings(_ logins: LoginProjection,
                                      now: Date,
                                      calendar: Calendar) -> [HealthFinding] {
        // Two years. Long enough that nothing legitimate lands here by accident, short enough that
        // the section is not permanently empty for someone who changes passwords on principle.
        guard let cutoff = calendar.date(byAdding: .year, value: -2, to: now) else { return [] }

        return logins.compactMap { entry in
            guard let password = entry.content.password, !password.isEmpty else { return nil }

            let detail: String
            if let raw = entry.item.preserved.passwordRevisionDate,
               let revised = VaultExportDocument.parseISO8601(raw) {
                guard revised < cutoff else { return nil }
                detail = L("Not changed in over two years")
            } else {
                // The server maintains this field and every official client writes it, so its
                // absence means the password predates the field — which makes it old by definition.
                detail = L("No revision date recorded")
            }

            return HealthFinding(itemId: entry.item.id,
                                 itemName: entry.item.name,
                                 detail: detail)
        }
    }

    private static func unsecuredFindings(_ logins: LoginProjection) -> [HealthFinding] {
        logins.compactMap { entry in
            guard let plain = entry.content.uris.first(where: { isPlainHTTP($0.uri) }) else {
                return nil
            }
            return HealthFinding(itemId: entry.item.id,
                                 itemName: entry.item.name,
                                 detail: plain.uri)
        }
    }

    private static func missingTwoFactorFindings(_ logins: LoginProjection) -> [HealthFinding] {
        logins.compactMap { entry in
            guard let password = entry.content.password, !password.isEmpty else { return nil }
            guard entry.content.totp?.isEmpty ?? true else { return nil }
            return HealthFinding(itemId: entry.item.id,
                                 itemName: entry.item.name,
                                 detail: L("No authenticator app configured"))
        }
    }

    /// Whether a URI would put credentials on the wire in plaintext.
    ///
    /// A URI with no scheme is **not** counted: the check is about the transport, and a bare
    /// hostname says nothing about it. Counting those would list most of a vault as unsecured.
    private static func isPlainHTTP(_ uri: String) -> Bool {
        URLComponents(string: uri)?.scheme?.lowercased() == "http"
    }
}
