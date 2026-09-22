import Foundation

// MARK: - offMain

/// Runs synchronous, bulk work on the global concurrent executor and awaits its result.
///
/// **Why this exists.** The app target is compiled with `-default-isolation MainActor`, so every
/// type in it is main-actor isolated unless it says otherwise — including the repository that
/// handles attachments. And `PrizmCryptoService.encryptData(_:)` is declared `nonisolated` on an
/// actor, which means *any* caller may invoke it, synchronously, **on the caller's own thread**.
/// `nonisolated` describes who is allowed to call; it does not move the work. So calling it from the
/// repository ran AES-256-CBC plus HMAC-SHA256 over the entire file on the thread drawing the
/// interface — for the 500 MB this app permits, tens of seconds of a frozen UI with a spinner that
/// could not even animate.
///
/// **Why the buffers are arguments, not captures.** Attachment plaintext and per-attachment keys are
/// `Data`, which is copy-on-write, and `Data.zeroize()` runs `withUnsafeMutableBytes` — so if a
/// second reference exists when it is called, the buffer is copied first and the memset erases the
/// copy while the original survives intact. A closure that *captures* a buffer keeps a second
/// reference alive for as long as the task object that owns it does, which is not a lifetime this
/// file can promise anything about. Passing the value in as a parameter makes the reference die at a
/// call boundary — the same boundary the synchronous call it replaced had. Callers must not hold a
/// `let` of the buffer alongside the hop for the same reason.
///
/// **What this is not.** It does not make the work interruptible: a one-shot `CommonCrypto` call
/// cannot be abandoned mid-buffer. Callers still check for cancellation at their own boundaries, and
/// the batch flow's `cancel()` still zeroes what it owns. Chunking the encryption would make it
/// interruptible and would also make a real progress percentage measurable — that is a change to the
/// crypto layout, not to this helper.
///
/// - Parameters:
///   - input: The value the work runs on. Owned by this call, released when it returns.
///   - work: The blocking computation. Runs off the main actor; must not touch main-actor state.
@concurrent func offMain<Input: Sendable, Result: Sendable>(
    _ input: Input,
    _ work: @Sendable (Input) throws -> Result
) async throws -> Result {
    try work(input)
}

/// The two-buffer form, for the crypto calls that need a file and the key that encrypts it.
@concurrent func offMain<First: Sendable, Second: Sendable, Result: Sendable>(
    _ first: First,
    _ second: Second,
    _ work: @Sendable (First, Second) throws -> Result
) async throws -> Result {
    try work(first, second)
}
