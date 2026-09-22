# Offline vault cache — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`. Until the test target compiles,
> none of the tests below can run, and the Constitution's Red→Green order cannot be followed. Tasks
> are written test-first for that reason.

## 1. Raw payload out of the network layer

- [x] 1.1 Failing test: `fetchSyncPayload()` returns bytes that decode to the same `SyncResponse` as
      `fetchSync()`, and the bytes are the body as sent (no re-serialisation). Assert on a fixture with
      a field the model does not decode, to pin "verbatim".
      → `PrizmAPIClientSyncPayloadTests`, via a `StubURLProtocol` that serves the fixture bytes.
- [x] 1.2 Add `performRaw(request:) async throws -> Data` beside `perform<T: Decodable>`, sharing the
      existing error mapping so a transport failure and a decoded error body cannot diverge.
- [x] 1.3 Add `fetchSyncPayload()` to the `PrizmAPIClient` protocol and to `MockPrizmAPIClient`.
- [x] 1.4 `fetchSync()` keeps its signature and delegates, so no existing call site changes.

## 2. The store

- [x] 2.1 Failing tests for `VaultCacheStoreImpl` (`VaultCacheStoreImplTests`, real temp directory):
      - [x] 2.1.1 round-trip: bytes written are bytes read
      - [x] 2.1.2 two user ids do not see each other's cache
      - [x] 2.1.3 a body with no metadata reads as no cache
      - [x] 2.1.4 an unknown `schemaVersion` reads as no cache, not as a parse error
      - [x] 2.1.5 corrupt JSON in the body reads as no cache (the decode failure is the caller's, not
            a crash here)
            → **deviation:** the store returns the bytes it finds; deciding "no cache" from an
            undecodable body is the caller's job and is pinned by
            `SyncRepositoryVaultCacheTests.testSync_transportFailure_withUndecodableCache_throwsTheNetworkError`.
            Asserting nil here would put the decode verdict inside the store, where it does not belong.
      - [x] 2.1.6 `delete(userId:)` removes both files and is idempotent
      - [x] 2.1.7 a write leaves the previous cache readable until the new one is complete (simulate a
            failure between the two renames)
            → **deviation:** the failure is induced with `chmod 0o500` on the account directory, so the
            atomic write's temporary file cannot be created. Making the metadata *path* unusable only
            proves "absent"; this shape proves the previous payload survives, which is the invariant.
      - [x] 2.1.8 file permissions are `0600`
- [x] 2.2 `VaultCacheStore` protocol in `Prizm/Domain/Repositories/`; implementation in
      `Prizm/Data/Cache/VaultCacheStoreImpl.swift`.
- [x] 2.3 Directory layout and atomic write per design Decisions 2 and 5.

## 3. Sync writes the cache

- [x] 3.1 Failing test: a successful sync persists the body and metadata for the current user.
- [x] 3.2 Failing test: **a failed sync does not overwrite a good cache** — the previous payload must
      still be readable afterwards. (A cache written by a failed attempt would turn a transient outage
      into permanent data loss.)
- [x] 3.3 Failing test: metadata records the account's server URL and a write time.
- [x] 3.4 Implement the write in `SyncRepositoryImpl`, after the populate step succeeds.

## 4. Sync reads the cache

- [x] 4.1 Failing tests for the fallback matrix (design Decision 3):
      - [x] 4.1.1 `networkUnavailable` + usable cache → items populated, `source == .cache`
      - [x] 4.1.2 `serverUnreachable` + usable cache → same
      - [x] 4.1.3 `unauthorized` + usable cache → **throws**, cache is not served
      - [x] 4.1.4 `decryptionFailed` + usable cache → **throws**
      - [x] 4.1.5 transport failure + **no** cache → **throws the network error**, and the vault is
            **not** left empty-but-unlocked (design Decision 4 — assert on the vault state, not only
            on the thrown error)
      - [x] 4.1.6 cache `serverURL` does not match the account → treated as no cache
- [x] 4.2 Failing test for the token-refresh distinction: expired access token + unreachable server
      resolves to a transport failure, not `unauthorized`, so 4.1.1 applies. This is the test the
      design calls out as the one a plausible implementation fails.
- [x] 4.3 `SyncResult` gains `source` (`.server` / `.cache`) and the payload's timestamp; existing
      call sites updated.
- [x] 4.4 Implement the fallback in `SyncRepositoryImpl`.
- [x] 4.5 `UnlockUseCaseImpl`: a cache-sourced sync is a **successful** unlock. Update its doc comment,
      which currently states that the in-memory store is re-synced from the server on every launch.

## 5. Presentation

- [x] 5.1 Failing test for `SyncLabelFormatter` covering the cache source and the age of the payload.
- [x] 5.2 `VaultBrowserViewModel`: expose the sync source so the label can distinguish
      live / cached / never-synced.
- [x] 5.3 `UnlockViewModel`: a transport failure that was recovered from the cache does not surface an
      error the user has to dismiss.
- [x] 5.4 New strings in `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings`, including the
      offline wording and the attachment-opens-offline failure message.
      → **deviation:** only the two offline strings were needed. The attachment path already
      localizes: `AttachmentRowViewModel` wraps the failure as
      `Could not open file: No internet connection. Check your network connection.`

## 6. Lifecycle

- [x] 6.1 Failing test: sign-out deletes the cache for that user.
- [x] 6.2 Wire the deletion into the same path that deletes the per-user Keychain items, so the two
      cannot drift.
- [x] 6.3 Confirm lock does **not** delete the cache (a test asserting the file is still readable
      after a lock — the behaviour is easy to break by "tidying up" the lock path).

## 7. Documentation

- [x] 7.1 `SECURITY.md`: what the cache contains, what it does not, what an attacker with the file can
      do, and the corrected statement about disk (design Decision 6).
- [x] 7.2 `README.md`: the offline limitation note changes — offline read works, offline write does
      not.
- [x] 7.3 `FEATURE-GAP-ANALYSIS.md`: mark the offline-read row as implemented.

## 8. Verification

- [ ] 8.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
      → 1245 passed / 0 failures (`/tmp/prizm-test4.log`), baseline was 1214.
- [ ] 8.2 Manual: unlock → quit → network off → relaunch → unlock with the master password → read an
      item, copy a password, view a TOTP code.
- [ ] 8.3 Manual: same, with the cache removed → the app reports the network failure and does **not**
      show an empty vault.
- [ ] 8.4 Manual: open an attachment while offline → a clear network error, not a hang or an empty
      file.

> **8.2–8.4 are outstanding.** They need a running signed app against a live Vaultwarden account and
> a way to take the network down mid-session; neither is available to the agent that wrote this
> change. Everything up to the boundary is covered by `SyncRepositoryVaultCacheTests` (the fallback
> matrix, the cache-sourced populate and the no-cache throw) and `VaultCacheStoreImplTests` (the file
> contract), so what remains unproven is the UI pass, not the logic. Do not mark these done on the
> strength of the unit tests.
