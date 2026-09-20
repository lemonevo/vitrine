import Foundation

// MARK: - Data.zeroize

nonisolated extension Data {

    /// Overwrites every byte this value owns with zero.
    ///
    /// **Not `resetBytes(in: 0..<count)`.** That range is an offset from `startIndex`, and a `Data`
    /// produced by `suffix(_:)`, `dropFirst(_:)` or a range subscript *keeps the indices of the
    /// buffer it was cut from*. The tail half of a 64-byte key is therefore a 32-byte `Data` whose
    /// `startIndex` is 32, and `resetBytes(in: 0..<32)` writes bytes 32…63 of a 32-byte allocation
    /// — 32 bytes past the end.
    ///
    /// That is not a hypothetical. `CryptoKeys` is built from `keyData[32..<64]` and from
    /// `data.suffix(32)`, so every "zero the MAC key" call site was a heap-buffer-overflow waiting
    /// on heap layout: AddressSanitizer caught it in `OrgKeyCache.clear()` as
    /// `WRITE of size 32 ... 0 bytes after 32-byte region`, and the same call appeared in sixteen
    /// other places, all of them reachable whenever a `Data` happened to be a slice.
    ///
    /// `withUnsafeMutableBytes` hands back a buffer spanning exactly this value's own bytes, so
    /// there is no range to get wrong and no index space to confuse.
    mutating func zeroize() {
        withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, buffer.count > 0 else { return }
            memset(base, 0, buffer.count)
        }
    }
}
