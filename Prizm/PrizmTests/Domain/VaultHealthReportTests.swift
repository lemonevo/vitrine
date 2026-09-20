import Foundation
import XCTest
@testable import Prizm

// MARK: - VaultHealthReportTests

/// Tests for the five health checks.
///
/// `now` and `calendar` are pinned so the two-year staleness boundary is a date the test chooses
/// rather than whatever the machine's clock says. Everything else about the report is a pure
/// function of the items, so there is nothing else to inject.
///
/// **The "no network request" scenario is not tested here.** There is no client in scope to assert
/// on — `make(from:)` takes items and returns a report — so the property is structural rather than
/// behavioural, and a test would only be asserting that Swift has no `URLSession` literal in it.
@MainActor
final class VaultHealthReportTests: XCTestCase {

    // 2023-11-14, a fixed instant. Every date below is stated relative to it.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // MARK: - Fixtures

    /// A login item, defaulting to one that fails nothing.
    private func login(id: String = "item-1",
                       name: String = "GitHub",
                       password: String? = "correct-horse-battery-staple-47!$",
                       uri: String = "https://github.com",
                       totp: String? = "JBSWY3DPEHPK3PXP",
                       passwordRevised: Date? = nil) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .login(LoginContent(
                username: "octocat", password: password,
                uris: [LoginURI(uri: uri, matchType: .domain)],
                totp: totp, notes: nil, customFields: []
            )),
            organizationId: nil,
            collectionIds: [],
            preserved: PreservedCipherFields(passwordRevisionDate: iso(passwordRevised))
        )
    }

    private func note(id: String = "note-1") -> VaultItem {
        VaultItem(
            id: id, name: "A note", isFavorite: false, isDeleted: false,
            creationDate: now, revisionDate: now,
            content: .secureNote(SecureNoteContent(notes: "hello", customFields: [])),
            organizationId: nil, collectionIds: [], preserved: .empty
        )
    }

    private func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    private func yearsAgo(_ value: Int) -> Date {
        calendar.date(byAdding: .year, value: -value, to: now)!
    }

    private func monthsAgo(_ value: Int) -> Date {
        calendar.date(byAdding: .month, value: -value, to: now)!
    }

    private func report(_ items: [VaultItem]) -> VaultHealthReport {
        VaultHealthReport.make(from: items,
                               estimator: .application,
                               now: now,
                               calendar: calendar)
    }

    private func ids(_ report: VaultHealthReport, _ check: HealthCheck) -> Set<String> {
        Set(report.findings(for: check).map(\.itemId))
    }

    // MARK: - Weak passwords

    func test_weakPassword_isReported() {
        let item = login(id: "weak-1", password: "aaa")

        let result = report([item])

        XCTAssertEqual(result.count(for: .weakPassword), 1)
        XCTAssertEqual(ids(result, .weakPassword), ["weak-1"])
    }

    func test_strongPassword_isNotReportedAsWeak() {
        let result = report([login()])

        XCTAssertEqual(result.count(for: .weakPassword), 0)
    }

    // MARK: - Reused passwords

    /// Both sharers are listed. Naming only one would let the user fix the copy they were shown and
    /// walk away believing the reuse was gone.
    func test_reusedPassword_reportsEverySharer() {
        let result = report([
            login(id: "a", password: "shared-secret-1"),
            login(id: "b", password: "shared-secret-1")
        ])

        XCTAssertEqual(result.count(for: .reusedPassword), 2)
        XCTAssertEqual(ids(result, .reusedPassword), ["a", "b"])
    }

    func test_uniquePasswords_areNotReportedAsReused() {
        let result = report([
            login(id: "a", password: "correct-horse-battery-staple-47!$"),
            login(id: "b", password: "triumph-pliers-oxygen-92#Q")
        ])

        XCTAssertEqual(result.count(for: .reusedPassword), 0)
    }

    // MARK: - Stale passwords

    func test_stalePassword_isReported() {
        let item = login(id: "old-1", passwordRevised: yearsAgo(3))

        let result = report([item])

        XCTAssertEqual(result.count(for: .stalePassword), 1)
        XCTAssertEqual(ids(result, .stalePassword), ["old-1"])
    }

    func test_recentPassword_isNotReportedAsStale() {
        let item = login(id: "fresh-1", passwordRevised: monthsAgo(1))

        let result = report([item])

        XCTAssertEqual(result.count(for: .stalePassword), 0)
    }

    /// No revision date means the password predates the field, which makes it old by definition.
    func test_missingRevisionDate_isReportedAsStale() {
        let item = login(id: "undated-1", passwordRevised: nil)

        let result = report([item])

        XCTAssertEqual(result.count(for: .stalePassword), 1)
        XCTAssertEqual(result.findings(for: .stalePassword).first?.detail,
                       L("No revision date recorded"))
    }

    // MARK: - Unsecured websites

    func test_plainHTTP_isReported() {
        let item = login(id: "http-1", uri: "http://example.com")

        let result = report([item])

        XCTAssertEqual(result.count(for: .unsecuredSite), 1)
        XCTAssertEqual(result.findings(for: .unsecuredSite).first?.detail, "http://example.com")
    }

    func test_https_isNotReportedAsUnsecured() {
        let result = report([login(uri: "https://example.com")])

        XCTAssertEqual(result.count(for: .unsecuredSite), 0)
    }

    /// A bare hostname says nothing about the transport. Counting it would list most of a vault.
    func test_schemeLessURI_isNotReportedAsUnsecured() {
        let result = report([login(uri: "example.com")])

        XCTAssertEqual(result.count(for: .unsecuredSite), 0)
    }

    // MARK: - Missing two-factor

    func test_loginWithoutTOTP_isReported() {
        let item = login(id: "no-2fa", totp: nil)

        let result = report([item])

        XCTAssertEqual(result.count(for: .missingTwoFactor), 1)
        XCTAssertEqual(ids(result, .missingTwoFactor), ["no-2fa"])
    }

    func test_loginWithTOTP_isNotReported() {
        let result = report([login(totp: "JBSWY3DPEHPK3PXP")])

        XCTAssertEqual(result.count(for: .missingTwoFactor), 0)
    }

    /// The check is narrower than its name: it is about a password with no second factor, not about
    /// every item missing an authenticator.
    func test_loginWithoutPassword_isNotReportedAsMissingTwoFactor() {
        let item = login(id: "no-password", password: nil, totp: nil)

        let result = report([item])

        XCTAssertEqual(result.count(for: .missingTwoFactor), 0)
        XCTAssertEqual(result.count(for: .weakPassword), 0)
        XCTAssertEqual(result.count(for: .stalePassword), 0)
    }

    // MARK: - Whole reports

    func test_cleanVault_hasNoFindings() {
        let result = report([
            login(id: "a", password: "correct-horse-battery-staple-47!$", passwordRevised: monthsAgo(1)),
            login(id: "b", password: "triumph-pliers-oxygen-92#Q", passwordRevised: monthsAgo(2))
        ])

        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.totalFindings, 0)
        for check in HealthCheck.allCases {
            XCTAssertEqual(result.count(for: check), 0, "\(check.rawValue) should be clean")
        }
    }

    /// An item failing several checks has to appear under each of them: fixing it for one check and
    /// finding it still listed under another is only surprising if the report hid the overlap.
    func test_oneItemFailingEverything_appearsUnderAllFive() {
        let shared = "aaa"
        let items = [
            login(id: "bad", name: "Everything wrong", password: shared,
                  uri: "http://example.com", totp: nil, passwordRevised: yearsAgo(3)),
            // Exists only to make `shared` a reused password. Its own revision date is recent so it
            // lands under exactly two checks: weak and reused.
            login(id: "accomplice", password: shared, passwordRevised: monthsAgo(1))
        ]

        let result = report(items)

        for check in HealthCheck.allCases {
            XCTAssertTrue(ids(result, check).contains("bad"),
                          "expected 'bad' under \(check.rawValue)")
        }
        // 5 for "bad" + weak and reused for "accomplice". Spelled out so a change in any one check
        // is visible as a number rather than as a silently passing containment loop.
        XCTAssertEqual(result.totalFindings, 7)
        XCTAssertEqual(result.count(for: .reusedPassword), 2)
    }

    func test_nonLoginItems_areIgnored() {
        let result = report([note()])

        XCTAssertTrue(result.isClean)
    }
}
