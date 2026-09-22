import XCTest
@testable import Prizm

/// Pins the two properties `fetchSyncPayload()` exists for: it hands back the server's bytes
/// **unmodified**, and it fails in a way that distinguishes "the server answered" from "nobody
/// answered" — the distinction the offline cache's fallback rule is built on.
@MainActor
final class PrizmAPIClientSyncPayloadTests: XCTestCase {

    private var sut: PrizmAPIClientImpl!

    /// A sync response with a field this client has no model for. The point of the fixture: if the
    /// payload were ever produced by re-encoding `SyncResponse` instead of keeping the bytes, this
    /// key would vanish — which is the bug class that has already cost this project passkeys,
    /// password history and folder organisation ids.
    private static let fixture = """
    {
      "profile": {
        "id": "user-1",
        "email": "alice@example.com",
        "name": null,
        "key": "2.encrypted-user-key==",
        "privateKey": null,
        "fieldTheClientDoesNotModel": { "nested": [1, 2, 3], "keep": "me" }
      },
      "ciphers": [],
      "folders": [],
      "collections": [],
      "anotherUnmodelledTopLevelField": "survives"
    }
    """

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        sut = PrizmAPIClientImpl(session: URLSession(configuration: configuration),
                                 trustDelegate: nil)
        await sut.setBaseURL(URL(string: "https://vault.example.com")!)
        await sut.setAccessToken("access-token")
    }

    // MARK: - The bytes are the server's

    /// The body handed back is byte-for-byte the body received.
    func testFetchSyncPayload_bodyIsTheResponseBytes() async throws {
        StubURLProtocol.respond(statusCode: 200, body: Data(Self.fixture.utf8))

        let (response, body) = try await sut.fetchSyncPayload()

        XCTAssertEqual(
            body, Data(Self.fixture.utf8),
            "The cached payload must be the response bytes, not a re-serialisation of the model"
        )
        XCTAssertEqual(response.profile.email, "alice@example.com")
    }

    /// A field the client does not decode is still in the bytes it caches.
    func testFetchSyncPayload_keepsFieldsTheModelDoesNotDecode() async throws {
        StubURLProtocol.respond(statusCode: 200, body: Data(Self.fixture.utf8))

        let (_, body) = try await sut.fetchSyncPayload()
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(
            text.contains("anotherUnmodelledTopLevelField"),
            "A field with no model must survive into the cache; re-encoding would have dropped it"
        )
        XCTAssertTrue(
            text.contains("fieldTheClientDoesNotModel"),
            "A field inside the profile that has no model must survive too"
        )
    }

    /// `fetchSync()` and `fetchSyncPayload()` decode the same body the same way, so nothing can be
    /// accepted by one and rejected by the other.
    func testFetchSyncPayload_decodesToTheSameResponseAsFetchSync() async throws {
        StubURLProtocol.respond(statusCode: 200, body: Data(Self.fixture.utf8))
        let viaPayload = try await sut.fetchSyncPayload().response

        StubURLProtocol.reset()
        StubURLProtocol.respond(statusCode: 200, body: Data(Self.fixture.utf8))
        let viaFetch = try await sut.fetchSync()

        XCTAssertEqual(viaPayload.profile.id,    viaFetch.profile.id)
        XCTAssertEqual(viaPayload.profile.email, viaFetch.profile.email)
        XCTAssertEqual(viaPayload.profile.key,   viaFetch.profile.key)
        XCTAssertEqual(viaPayload.ciphers.count, viaFetch.ciphers.count)
        XCTAssertEqual(viaPayload.folders.count, viaFetch.folders.count)
        XCTAssertEqual(viaPayload.collections.count, viaFetch.collections.count)
    }

    // MARK: - What a failure looks like

    /// A rejection from the server is an `APIError`, carrying the status the server chose.
    func testFetchSyncPayload_rejection_throwsHTTPError() async throws {
        StubURLProtocol.respond(statusCode: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))

        do {
            _ = try await sut.fetchSyncPayload()
            XCTFail("Expected a 401 to throw")
        } catch let error as APIError {
            guard case .httpError(let statusCode, _) = error else {
                return XCTFail("Expected APIError.httpError, got \(error)")
            }
            XCTAssertEqual(statusCode, 401)
        }
    }

    /// A server failure is an `APIError` too — still an answer, so the cache must not be preferred
    /// over it silently. (`SyncRepositoryImpl` decides that, not the client; this pins the shape.)
    func testFetchSyncPayload_serverError_throwsHTTPErrorWithStatus() async throws {
        StubURLProtocol.respond(statusCode: 503, body: Data())

        do {
            _ = try await sut.fetchSyncPayload()
            XCTFail("Expected a 503 to throw")
        } catch let error as APIError {
            guard case .httpError(let statusCode, _) = error else {
                return XCTFail("Expected APIError.httpError, got \(error)")
            }
            XCTAssertEqual(statusCode, 503)
        }
    }

    /// Silence is not an `APIError`. That is the whole basis of the fallback: `SyncRepositoryImpl`
    /// serves the cache only for failures that are not `APIError.httpError`, so if a transport
    /// failure ever started arriving as an HTTP error, offline unlock would quietly stop working.
    func testFetchSyncPayload_transportFailure_isNotAnHTTPError() async throws {
        StubURLProtocol.fail(with: URLError(.notConnectedToInternet))

        do {
            _ = try await sut.fetchSyncPayload()
            XCTFail("Expected a transport failure to throw")
        } catch is APIError {
            XCTFail("A transport failure must not be reported as an answer from the server")
        } catch {
            // Expected: the URLError propagates with its domain intact.
            XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
        }
    }
}

// MARK: - StubURLProtocol

/// Answers every request from a scripted response, so the client can be exercised without a server.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var statusCode: Int = 200
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var failure: Error?

    static func respond(statusCode: Int, body: Data) {
        lock.lock(); defer { lock.unlock() }
        self.statusCode = statusCode
        self.body       = body
        self.failure    = nil
    }

    static func fail(with error: Error) {
        lock.lock(); defer { lock.unlock() }
        self.failure = error
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        statusCode = 200
        body       = Data()
        failure    = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let failure = Self.failure
        let status  = Self.statusCode
        let body    = Self.body
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
