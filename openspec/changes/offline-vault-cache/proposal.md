## Why

Unlocking requires the network, and the vault exists only in memory. `UnlockUseCaseImpl.execute`
calls `sync.sync()` and lets its error propagate (step 2 of that file), and the same file states in
its own comment that "the in-memory store is cleared on every app quit". So with no network — server
down, laptop offline, certificate problem, upstream outage — **a correct master password does not
open the vault.** The user cannot read one password, not even the one they could have read
yesterday. For a password manager, that is the one failure it must not have: the moment the network
is gone is exactly the moment a local vault is worth having.

Official Bitwarden clients cache the vault and read it offline. Prizm does not, and this is the
largest remaining gap between "usable" and "can be a daily driver".

**The part that makes this cheap, and the reason it is not a cryptography project:** unlocking is
already entirely local. `encUserKey` (the account's symmetric key, wrapped by the master key) and
`kdfParams` are already persisted per user in the Keychain (`AuthRepositoryImpl.swift:786,794`), so
the master password → Argon2id → unwrap `encUserKey` path already works with no server involved. The
only thing missing is the **ciphertext of the vault** — and the server hands us exactly that on every
sync.

So this change caches the server's own bytes. It adds no key, no new algorithm, and no new way to
reach plaintext: after this change, reading cached data still requires the master password, exactly
as reading live data does today.

## What Changes

- `PrizmAPIClient` gains a raw-payload form of `fetchSync` that returns the response body alongside
  the decoded `SyncResponse`. The decode path is unchanged; the bytes are a by-product, not a second
  parse.
- New `VaultCacheStore` — protocol in Domain, implementation in Data — storing the response body
  **verbatim** under the app's Application Support directory, one directory per user id, with a small
  metadata file recording when it was written and which server it came from.
- `SyncRepositoryImpl` writes the cache after every successful sync, and reads it when the server
  cannot be reached, running the same decrypt-and-populate path either way.
- `SyncResult` gains the source of its data (server or cache) and the timestamp of the payload, so
  the UI can be honest about which one the user is looking at.
- The sync label reports the cached state — "Offline — showing data from <time>" — instead of the
  failure looking like a normal successful sync or, worse, like an empty vault.
- The cache is deleted on sign-out, and ignored when the server URL recorded in its metadata no
  longer matches the account's configuration.

## Non-goals

- **Offline writes.** Creating, editing, deleting and moving items still require the server. No write
  queue, no write-ahead log, no conflict resolution — that is a different change with a different
  risk profile, and it depends on the `revisionDate` loss being fixed first.
- **Caching attachment contents.** The `BLOCKED` metadata for attachments is in the cached payload;
  the encrypted blobs are not, so opening one offline fails with a network error. The UI must say so
  rather than appear broken.
- **A new key, a new format, or a new encryption step.** The cache is the server's ciphertext byte
  for byte. Nothing is decrypted to disk.
- **Background refresh.** A cache with no refresh is still the point of this change; keeping it fresh
  while the app runs is the next change.
- **Multi-account.** The cache is laid out per user id so that it does not block the later change,
  but no account switching is added here.

## Capabilities

### New Capabilities

- `offline-vault-cache`: persisting the server's encrypted vault payload so that an unlock with no
  network connection can still open the vault, while keeping the cache excluded from anything that
  would let it be read without the master password.

### Modified Capabilities

- `vault-browser-ui`: the sync status shows whether the data on screen came from the server or from
  the cache, and how old the cached copy is.

## Impact

- `Prizm/Data/Network/PrizmAPIClient.swift` — the raw-payload sync fetch; the `PrizmAPIClient`
  protocol
- `Prizm/Data/Cache/VaultCacheStoreImpl.swift` — **new**; path layout, atomic write, metadata
- `Prizm/Domain/Repositories/VaultCacheStore.swift` — **new** protocol
- `Prizm/Data/Repositories/SyncRepositoryImpl.swift` — cache write on success, cache read on
  transport failure
- `Prizm/Domain/Repositories/SyncRepository.swift` — `SyncResult` source and payload timestamp;
  `SyncError` may need a case for "no usable cache"
- `Prizm/Data/UseCases/UnlockUseCaseImpl.swift` — the failure that is now recoverable
- `Prizm/App/AppContainer.swift`, `Prizm/App/PrizmApp.swift` — wiring; cache deletion on sign-out
- `Prizm/Presentation/Vault/VaultBrowserViewModel.swift`, `SyncLabelFormatter.swift` — the cached
  state, and the wording for it
- `Prizm/Presentation/Unlock/UnlockViewModel.swift` — a network failure with a usable cache is not an
  error the user has to clear
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — new strings
- `SECURITY.md` — the cache is a new artefact on disk and must be documented there, with what it
  contains and what it does not
- `Prizm/PrizmTests/Mocks/MockPrizmAPIClient.swift`, `MockSyncRepository.swift` — follow the new
  protocol shapes
- `Prizm/Resources/Prizm.entitlements` — unchanged; the Application Support container is already
  writable under the App Sandbox
