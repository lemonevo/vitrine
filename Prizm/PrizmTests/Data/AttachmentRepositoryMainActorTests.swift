import XCTest
@testable import Prizm

/// The main actor must stay runnable while an attachment is being encrypted.
///
/// `AttachmentRepositoryImplTests` uses the real crypto service, and AES-NI gets through tens of
/// megabytes in well under a frame of anything observable — so a blocking bug there is invisible
/// there. This class uses the mock with a deliberate sleep in the bulk methods, which is the only
/// way to ask the question "who waits when this runs" and have the answer mean something.
@MainActor
final class AttachmentRepositoryMainActorTests: XCTestCase {

    private var sut:       AttachmentRepositoryImpl!
    private var apiClient: MockPrizmAPIClient!
    private var vaultRepo: MockVaultRepository!
    private var crypto:    MockPrizmCryptoService!

    private let cipherKey = Data(repeating: 0xAB, count: 32) + Data(repeating: 0xCD, count: 32)
    private let cipherId  = "cipher-abc"

    /// A counter the main actor can advance. A plain `var` cannot be captured by the polling task
    /// and read by the test without tripping the exclusivity rules, so it lives in a box.
    @MainActor private final class Ticks { var count = 0 }

    override func setUp() async throws {
        try await super.setUp()
        apiClient  = MockPrizmAPIClient()
        vaultRepo  = MockVaultRepository()
        crypto     = MockPrizmCryptoService()
        sut        = AttachmentRepositoryImpl(apiClient: apiClient,
                                              crypto: crypto,
                                              vaultRepository: vaultRepo)
        MockBulkWork.nanoseconds = 0
    }

    override func tearDown() async throws {
        MockBulkWork.nanoseconds = 0
        try await super.tearDown()
    }

    /// Polls the main actor every 40 ms while `body` runs.
    ///
    /// Returns how many times the main actor got control back. If `body` performs its bulk work on
    /// the main actor, this collapses to the two or three ticks that happened before the work
    /// started; if the work is elsewhere, the poller keeps running for the whole duration.
    private func ticksDuring(_ body: () async throws -> Void) async throws -> Int {
        let ticks = Ticks()
        let poller = Task { @MainActor in
            while !Task.isCancelled {
                ticks.count += 1
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 60_000_000)   // establish a baseline before the work
        try await body()
        poller.cancel()
        return ticks.count
    }

    func testUpload_doesNotHoldTheMainActorWhileEncrypting() async throws {
        apiClient.createAttachmentMetadataResponse = AttachmentMetadataResponse(
            attachmentId: "att-xyz",
            url:          "https://api.example.com/upload",
            fileUploadType: 0
        )
        MockBulkWork.nanoseconds = 600_000_000   // 0.6 s of "encryption"

        let ticks = try await ticksDuring {
            _ = try await self.sut.upload(cipherId: self.cipherId,
                                          fileName: "document.pdf",
                                          data: Data("payload".utf8),
                                          cipherKey: self.cipherKey)
        }

        // 0.6 s at a 40 ms interval is ~15 ticks if the main actor is free, ~2 if it is blocked.
        XCTAssertGreaterThanOrEqual(ticks, 8,
            "the main actor only ran \(ticks) times during a 0.6 s bulk encryption — "
            + "the UI cannot animate, answer a menu, or update a batch row while it waits")
    }

    /// The helper itself, independent of any caller: blocking work must not stall the main actor.
    /// `download` uses the same hop, and this is what covers that path without needing a stubbed
    /// blob fetch.
    func testOffMain_keepsTheActorRunnable() async throws {
        let ticks = try await ticksDuring {
            _ = try await offMain(0.6) { (interval: TimeInterval) -> Bool in
                Thread.sleep(forTimeInterval: interval)
                return true
            }
        }

        XCTAssertGreaterThanOrEqual(ticks, 8, "offMain ran the work on the caller after all")
    }

    /// The result has to come back typed, or the hop would be useless to any real caller.
    func testOffMain_returnsTheWorkResult() async throws {
        let doubled: Int = try await offMain(21) { $0 * 2 }
        XCTAssertEqual(doubled, 42)
    }

    func testOffMain_propagatesTheWorkError() async {
        do {
            _ = try await offMain(CryptoFailure()) { (failure: CryptoFailure) throws -> Int in
                throw failure
            }
            XCTFail("the error must reach the caller")
        } catch is CryptoFailure {
            // expected
        } catch {
            XCTFail("expected the work's own error, got \(error)")
        }
    }

    private struct CryptoFailure: Error {}
}
