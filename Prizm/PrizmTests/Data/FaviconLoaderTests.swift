import AppKit
import XCTest
@testable import Prizm

// MARK: - RecordingURLProtocol

/// Records every request that reaches the transport.
///
/// The point of the "Show website icons" setting is that turning it off makes **no** request at
/// all, and the point of §2.5 is that the request goes to the user's own server rather than to a
/// third party. Both claims are about requests that do or do not happen, so the transport has to be
/// observable — asserting on the returned image would prove nothing.
final class RecordingURLProtocol: URLProtocol {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    /// A 1×1 PNG, so the happy path can be asserted on the decoded image as well as the request.
    private static let png = Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """)!

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static var requestedURLs: [URL] { requests.compactMap(\.url) }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        Self.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.png)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - FaviconLoaderTests

/// Tests for `FaviconLoader` and `WebsiteIconsPreference` — FEATURE-GAP-ANALYSIS.md §2.5.
///
/// Before this change the loader defaulted to a hardcoded `https://icons.bitwarden.net`, so opening
/// any login item sent its domain to a third party. A self-hosted Vaultwarden user's reason for
/// self-hosting is usually exactly that.
@MainActor
final class FaviconLoaderTests: XCTestCase {

    private var sut: FaviconLoader!
    private var defaults: UserDefaults!
    private let suiteName = "FaviconLoaderTests"

    override func setUp() async throws {
        try await super.setUp()
        RecordingURLProtocol.reset()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        sut = FaviconLoader(
            iconsBase: URL(string: "https://vault.example.com/icons"),
            session: URLSession(configuration: configuration),
            defaults: defaults
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        RecordingURLProtocol.reset()
        try await super.tearDown()
    }

    // MARK: - Request target

    func test_faviconRequestsTheConfiguredBase() async {
        _ = await sut.favicon(for: "github.com")

        XCTAssertEqual(RecordingURLProtocol.requestedURLs.count, 1)
        XCTAssertEqual(
            RecordingURLProtocol.requestedURLs.first?.absoluteString,
            "https://vault.example.com/icons/github.com/icon.png"
        )
    }

    func test_faviconIsLoadedWhenTheServerResponds() async {
        let image = await sut.favicon(for: "github.com")
        XCTAssertNotNil(image)
    }

    func test_officialIconServiceIsNeverContacted() async {
        // The regression this change exists to prevent.
        _ = await sut.favicon(for: "github.com")
        _ = await sut.favicon(for: "example.org")

        for url in RecordingURLProtocol.requestedURLs {
            XCTAssertNotEqual(url.host, "icons.bitwarden.net")
        }
    }

    func test_perServiceOverrideIsHonoured() async {
        await sut.configure(iconsBase: URL(string: "https://icons.example.com"))

        _ = await sut.favicon(for: "github.com")

        XCTAssertEqual(
            RecordingURLProtocol.requestedURLs.first?.absoluteString,
            "https://icons.example.com/github.com/icon.png"
        )
    }

    // MARK: - No account, no request

    func test_noConfiguredBaseMakesNoRequest() async {
        let loader = FaviconLoader(defaults: defaults)
        let image  = await loader.favicon(for: "github.com")

        XCTAssertNil(image)
        XCTAssertTrue(RecordingURLProtocol.requests.isEmpty)
    }

    // MARK: - The setting

    func test_iconsEnabledByDefault() {
        XCTAssertTrue(WebsiteIconsPreference.isEnabled(in: defaults))
    }

    func test_disablingStopsRequestsImmediately() async {
        // Load once so the image is in the in-memory cache — turning the setting off must still
        // stop the image being shown, not merely stop new fetches.
        _ = await sut.favicon(for: "github.com")
        XCTAssertEqual(RecordingURLProtocol.requests.count, 1)

        WebsiteIconsPreference.setEnabled(false, in: defaults)
        RecordingURLProtocol.reset()

        let image = await sut.favicon(for: "github.com")
        XCTAssertNil(image)
        XCTAssertTrue(RecordingURLProtocol.requests.isEmpty, "a disabled loader must not reach the network")
    }

    func test_disablingBlocksADomainThatWasNeverFetched() async {
        WebsiteIconsPreference.setEnabled(false, in: defaults)

        let image = await sut.favicon(for: "never-seen.example")
        XCTAssertNil(image)
        XCTAssertTrue(RecordingURLProtocol.requests.isEmpty)
    }

    func test_reEnablingResumesFetching() async {
        WebsiteIconsPreference.setEnabled(false, in: defaults)
        _ = await sut.favicon(for: "github.com")
        XCTAssertTrue(RecordingURLProtocol.requests.isEmpty)

        WebsiteIconsPreference.setEnabled(true, in: defaults)
        _ = await sut.favicon(for: "github.com")

        XCTAssertEqual(RecordingURLProtocol.requests.count, 1)
    }

    func test_preferencePersistsInTheInjectedStore() {
        WebsiteIconsPreference.setEnabled(false, in: defaults)

        // A fresh read of the same store must see the value — this is what survives a relaunch.
        XCTAssertFalse(WebsiteIconsPreference.isEnabled(in: defaults))
        XCTAssertEqual(defaults.object(forKey: WebsiteIconsPreference.key) as? Bool, false)
    }

    // MARK: - Caching

    func test_repeatedRequestsForTheSameDomainUseTheCache() async {
        _ = await sut.favicon(for: "github.com")
        _ = await sut.favicon(for: "github.com")

        XCTAssertEqual(RecordingURLProtocol.requests.count, 1)
    }

    func test_reconfiguringClearsTheCache() async {
        _ = await sut.favicon(for: "github.com")
        XCTAssertEqual(RecordingURLProtocol.requests.count, 1)

        await sut.configure(iconsBase: URL(string: "https://other.example.com"))
        _ = await sut.favicon(for: "github.com")

        XCTAssertEqual(RecordingURLProtocol.requests.count, 2)
        XCTAssertEqual(
            RecordingURLProtocol.requestedURLs.last?.absoluteString,
            "https://other.example.com/github.com/icon.png"
        )
    }

    func test_configuringTheSameBaseTwiceDoesNotClearTheCache() async {
        _ = await sut.favicon(for: "github.com")
        await sut.configure(iconsBase: URL(string: "https://vault.example.com/icons"))
        _ = await sut.favicon(for: "github.com")

        XCTAssertEqual(RecordingURLProtocol.requests.count, 1)
    }
}
