import XCTest
import SwiftUI
@testable import Prizm

@MainActor
final class AccessibilityTier2Tests: XCTestCase {

    // MARK: - 7.1 ContrastAwareOpacity

    /// Every contrast-aware opacity must get *stronger*, never weaker, under Increase Contrast — and
    /// every one must be listed here.
    ///
    /// This was five separate near-identical tests, which is how three of the eight functions
    /// (`typeChip`, `hairline`, `authCardBorder`) went unasserted while `ui-redesign`'s contrast delta
    /// required them to respond. A table makes the omission visible: adding a function to `Opacity`
    /// without adding it here leaves the gap in one place instead of spread across five.
    func testOpacity_everyFunctionIsStrongerUnderIncreasedContrast() {
        let all: [(name: String, standard: Double, increased: Double)] = [
            ("bannerBackground", Opacity.bannerBackground(.standard), Opacity.bannerBackground(.increased)),
            ("cardBorder",       Opacity.cardBorder(.standard),       Opacity.cardBorder(.increased)),
            ("trashBanner",      Opacity.trashBanner(.standard),      Opacity.trashBanner(.increased)),
            ("errorBanner",      Opacity.errorBanner(.standard),      Opacity.errorBanner(.increased)),
            ("dropTarget",       Opacity.dropTarget(.standard),       Opacity.dropTarget(.increased)),
            ("typeChip",         Opacity.typeChip(.standard),         Opacity.typeChip(.increased)),
            ("hairline",         Opacity.hairline(.standard),         Opacity.hairline(.increased)),
            ("selectionFill",    Opacity.selectionFill(.standard),    Opacity.selectionFill(.increased)),
            ("controlHover",     Opacity.controlHover(.standard),     Opacity.controlHover(.increased)),
            ("authCardBorder",   Opacity.authCardBorder(.standard),   Opacity.authCardBorder(.increased)),
        ]

        for entry in all {
            XCTAssertGreaterThan(entry.increased, entry.standard,
                "Opacity.\(entry.name) does not get stronger under Increase Contrast")
            XCTAssertGreaterThan(entry.standard, 0, "Opacity.\(entry.name) is invisible at standard contrast")
            XCTAssertLessThanOrEqual(entry.increased, 1.0, "Opacity.\(entry.name) exceeds full opacity")
        }
    }

    // MARK: - 7.2 optionalAnimation

    func testOptionalAnimation_executesBody() {
        var executed = false
        optionalAnimation(.default) { executed = true }
        XCTAssertTrue(executed)
    }

    // MARK: - 7.3 Error strings include suggestions

    func testAuthError_invalidURL_includesHTTPS() {
        let msg = AuthError.invalidURL.errorDescription ?? ""
        XCTAssertTrue(msg.contains("https://"), "Should suggest including https://")
    }

    func testAuthError_invalidCredentials_includesSuggestion() {
        let msg = AuthError.invalidCredentials.errorDescription ?? ""
        XCTAssertTrue(msg.contains("Check your email"), "Should suggest checking credentials")
    }

    func testAuthError_serverUnreachable_includesSuggestion() {
        let msg = AuthError.serverUnreachable.errorDescription ?? ""
        XCTAssertTrue(msg.contains("Verify the URL"), "Should suggest verifying URL")
    }

    func testAuthError_networkUnavailable_includesSuggestion() {
        let msg = AuthError.networkUnavailable.errorDescription ?? ""
        XCTAssertTrue(msg.contains("Check your network"), "Should suggest checking network")
    }

    func testSyncError_unauthorized_includesSuggestion() {
        let msg = SyncError.unauthorized.errorDescription ?? ""
        XCTAssertTrue(msg.contains("signing out"), "Should suggest signing out and in")
    }

    func testSyncError_networkUnavailable_includesSuggestion() {
        let msg = SyncError.networkUnavailable.errorDescription ?? ""
        XCTAssertTrue(msg.contains("Check your network"), "Should suggest checking network")
    }

    func testSyncError_serverUnreachable_includesSuggestion() {
        let url = URL(string: "https://example.com")!
        let msg = SyncError.serverUnreachable(url).errorDescription ?? ""
        XCTAssertTrue(msg.contains("Verify the URL"), "Should suggest verifying URL")
    }
}
