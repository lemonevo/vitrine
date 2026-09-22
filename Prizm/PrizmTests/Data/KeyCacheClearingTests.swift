import Foundation
import XCTest
@testable import Prizm

/// The two key caches that had no tests, and what `Data.zeroize()` does and does not promise.
///
/// **What this file deliberately does not claim.** `VaultKeyCache` had coverage; `OrgKeyCache` and
/// `AccountKeyCache` had none, and `zeroize` had no test anywhere in the suite — so Constitution §III
/// ("key material must not outlive the vault session") was being checked only for *reach*: that
/// `clear()` gets called, not that it does what it says.
///
/// But "the bytes are gone" is not something safe Swift can assert about someone else's copy. A
/// `Data` is copy-on-write: `zeroize()` reaches this value's storage, and if another reference exists
/// the mutation copies first and leaves that other one holding the original bytes. `OrgKeyCache`'s own
/// comment says so. So these tests pin two things and no more:
///
///   1. after `clear()` nothing is reachable through the cache, and
///   2. the CoW boundary is what it is — stated as a test, so nobody later writes one that implies
///      more and reads the passing suite as proof of memory erasure.
final class KeyCacheClearingTests: XCTestCase {

    private let orgKeys = CryptoKeys(
        encryptionKey: Data(repeating: 0x11, count: 32),
        macKey:        Data(repeating: 0x22, count: 32)
    )

    // MARK: - OrgKeyCache

    func test_orgCache_snapshotCarriesWhatWasStored() async {
        let cache = OrgKeyCache()
        await cache.store(key: orgKeys, for: "org-1")

        let snapshot = await cache.snapshot()
        XCTAssertEqual(Array(snapshot.keys), ["org-1"])
        XCTAssertEqual(snapshot["org-1"]?.encryptionKey, orgKeys.encryptionKey)
    }

    func test_orgCache_clearMakesEveryOrgUnreachable() async {
        let cache = OrgKeyCache()
        await cache.store(key: orgKeys, for: "org-1")
        await cache.store(key: orgKeys, for: "org-2")
        let before = await cache.snapshot()
        XCTAssertEqual(before.count, 2)

        await cache.clear()
        let after = await cache.snapshot()
        XCTAssertTrue(after.isEmpty, "a locked vault must not be able to decrypt an org cipher")
    }

    /// Storing after a clear has to work, or the "fix" would be a cache that empties itself once and
    /// then silently ignores the next sync — which would present as items failing to decrypt.
    func test_orgCache_acceptsKeysAgainAfterClear() async {
        let cache = OrgKeyCache()
        await cache.store(key: orgKeys, for: "org-1")
        await cache.clear()

        let other = CryptoKeys(encryptionKey: Data(repeating: 0x33, count: 32),
                               macKey: Data(repeating: 0x44, count: 32))
        await cache.store(key: other, for: "org-1")
        let snapshot = await cache.snapshot()
        XCTAssertEqual(snapshot["org-1"]?.macKey, other.macKey)
    }

    func test_orgCache_clearOnAnEmptyCacheIsHarmless() async {
        let cache = OrgKeyCache()
        await cache.clear()
        let snapshot = await cache.snapshot()
        XCTAssertTrue(snapshot.isEmpty)
    }

    // MARK: - AccountKeyCache

    func test_accountCache_holdsThenDropsThePublicKey() async {
        let cache = AccountKeyCache()
        let der = Data(repeating: 0x30, count: 294)

        await cache.store(publicKey: der)
        let held = await cache.current()
        XCTAssertEqual(held, der)

        await cache.clear()
        let dropped = await cache.current()
        XCTAssertNil(dropped,
                     "the fingerprint phrase is derived from vault material; it goes with the session")
    }

    func test_accountCache_storingTwiceReplacesRatherThanAppending() async {
        let cache = AccountKeyCache()
        await cache.store(publicKey: Data([0x01]))
        await cache.store(publicKey: Data([0x02]))
        let current = await cache.current()
        XCTAssertEqual(current, Data([0x02]))
    }

    // MARK: - Data.zeroize

    /// The plain case: sole owner, storage really is overwritten.
    func test_zeroize_clearsEveryByteOfAnOwnedBuffer() {
        var buffer = Data(repeating: 0xFF, count: 64)
        buffer.zeroize()
        XCTAssertEqual(buffer, Data(count: 64))
    }

    /// **The regression the doc comment on `zeroize` is about.**
    ///
    /// A `Data` cut out of a larger one keeps the source's indices, so the tail of a 64-byte key is a
    /// 32-byte value whose `startIndex` is 32. The previous implementation,
    /// `resetBytes(in: 0..<count)`, treated that range as an offset from `startIndex` and wrote 32
    /// bytes past the end of the allocation. AddressSanitizer caught it in `OrgKeyCache.clear()` as
    /// `WRITE of size 32 ... 0 bytes after 32-byte region`, and the same shape appeared at roughly
    /// sixteen call sites — every one of them reachable whenever a key happened to be a slice.
    ///
    /// `CryptoKeys` is built from `keyData[32..<64]` and `data.suffix(32)`, so this is the normal case
    /// rather than an exotic one.
    func test_zeroize_onASlicedBuffer_isInBoundsAndCompletes() {
        let whole = Data(repeating: 0xAA, count: 64)
        var tail = whole[32..<64]

        // Asserting the trap still exists: if `Data` ever stops preserving slice indices, this test
        // says so rather than quietly becoming a test of the easy case.
        XCTAssertEqual(tail.startIndex, 32, "slices are expected to keep the source's indices")
        XCTAssertEqual(tail.count, 32)

        tail.zeroize()
        XCTAssertEqual(tail, Data(count: 32))
        _ = whole   // the source is untouched by a slice's zeroize; only `tail`'s own bytes are
    }

    func test_zeroize_onAnEmptyBufferDoesNotCrash() {
        var empty = Data()
        empty.zeroize()
        XCTAssertTrue(empty.isEmpty)
    }

    /// **The limitation, stated as a test so it cannot be mistaken for coverage.**
    ///
    /// Zeroing one `Data` does not reach a copy of it. That is guaranteed copy-on-write behaviour, not
    /// a bug — but it is the reason no test in this file, and none that should be added, claims that
    /// `clear()` erases key material from memory. It erases this value's storage and drops the
    /// reference; anything else still holding a copy keeps its bytes until it too goes away.
    ///
    /// `OrgKeyCache`'s comment says the same thing. If a future change makes that guarantee true by
    /// other means, this test is the one to delete.
    func test_zeroize_doesNotReachAnotherCopy() {
        var original = Data(repeating: 0xFF, count: 32)
        let copy = original

        original.zeroize()

        XCTAssertEqual(original, Data(count: 32))
        XCTAssertEqual(copy, Data(repeating: 0xFF, count: 32),
                       "copy-on-write leaves other references holding the original bytes")
    }
}
