# Offline vault cache — Design

## Context

The unlock path is: `AuthRepositoryImpl.unlockWithPassword` (master password → Argon2id → unwrap
`encUserKey` → open the crypto service; **no network**), then `SyncRepositoryImpl.sync` (GET
`/api/sync` → decrypt → populate the in-memory store). Only the second step needs the server, and the
store it fills is lost on quit.

The Keychain already holds, per user: `kdfParams`, `encUserKey`, `accessToken`, `refreshToken`,
`email`, `name`, `serverEnvironment`. So the key material needed to *read* cached ciphertext is
already at rest. The missing piece is the ciphertext.

## Decision 1 — cache the response bytes verbatim, never a re-encoded model

`SyncResponse` is `Decodable` (`Prizm/Data/Network/Models/SyncResponse.swift:11`). It is tempting to
make it `Codable` and write `JSONEncoder().encode(response)`. That would be a mistake with a known
history in this codebase: re-encoding a decoded model writes back only the fields the model carries,
and everything else is silently destroyed. This project has already shipped that bug three times —
passkeys, password history, and `organizationId`/`collectionIds` on folder operations — through
`CipherMapper.toRawCipher`, and `FEATURE-GAP-ANALYSIS.md §2` records the trail.

A cache is a copy of the server's data. It must not be able to lose a field, so it stores the bytes
the server sent, and the decoder keeps reading them. This also means no serialisation code is added
at all: the bytes already exist inside `perform<T: Decodable>`
(`PrizmAPIClient.swift:1113`); they are returned instead of discarded.

## Decision 2 — two files per user, body first and metadata last

```
<Application Support>/Prizm/vault-cache/<userId>/sync.json        # verbatim response body
<Application Support>/Prizm/vault-cache/<userId>/sync.meta.json   # { writtenAt, serverURL, schemaVersion }
```

Both are written atomically (temp file + rename). **Metadata is renamed last, and its absence means
the cache is unusable.** The ordering matters in one direction only: body-then-metadata means the
worst crash outcome is a fresh body with a stale timestamp, which is harmless. The reverse would
produce a stale body carrying a fresh timestamp — a cache that lies about its own age, which is the
one thing the UI depends on.

`schemaVersion` exists so that a future format change invalidates the file rather than misparsing it:
an unreadable cache must degrade to "no cache", never to a crash or a partial vault.

`userId` comes from the account, not from the file, and the account's server URL is compared against
`serverURL` before use — the same user id on a different server is a different vault.

## Decision 3 — fall back on transport failure only, never on an answer from the server

| failure | fall back to cache? | why |
| --- | --- | --- |
| `networkUnavailable`, `serverUnreachable` | **yes** | nobody answered; this is the case the capability exists for |
| `unauthorized` | no | the server answered and rejected the session. Serving stale data would hide an expired session behind a screen that looks like a normal unlock |
| `decryptionFailed` | no | the keys are wrong, not the network. Cached ciphertext would fail identically, and a second failure would obscure the first |

**The place an implementation gets this wrong:** the unlock path refreshes the access token first
(`AuthRepositoryImpl.swift:343-377`). If the token has expired and the network is down, a naive
implementation collapses "could not reach the server to refresh" into "unauthorized" — and then
refuses the cache, which is exactly the offline case this change exists to fix. The refresh path must
keep transport failures and server rejections distinct, and the test for that distinction belongs at
the API layer where the mapping happens, not at the use case.

## Decision 4 — no usable cache surfaces the error; it never yields an empty vault

If the server is unreachable and there is no cache, unlock fails with the network error, exactly as it
does today. Rendering an empty vault is the worst available outcome: it is indistinguishable from
"all my items are gone", and it invites the user to act on that belief.

This is the highest-stakes requirement in the change, so it is a test, not a convention. The
empty-vault path is what a refactor produces by accident when the cache read returns "nothing" and
nobody checks whether the server was reachable.

## Decision 5 — the cache survives lock and quit, and dies with the account

- **Survives lock.** That is the point: relaunch with no network, unlock with the master password,
  read the vault. Locking zeroes the keys; it does not touch ciphertext.
- **Deleted on sign-out**, in the same path that deletes the per-user Keychain items, so the two
  cannot drift apart.
- **Not deleted on lock**, which means the Security section below cannot claim "the vault is never on
  disk".
- Permissions are `0600` inside the app's own container. On macOS there is no equivalent of iOS data
  protection classes to apply here, and nothing is gained by pretending otherwise: what protects the
  file is that it is ciphertext plus the Keychain-resident keys that unwrap it.

## Decision 6 — what `SECURITY.md` has to say afterwards

The document currently claims the vault is in memory only and that nothing reaches disk. That is
already inaccurate (KDF parameters, the wrapped user key, tokens and the server environment are at
rest in the Keychain), and this change makes it more so. The update must state:

- **What is on disk:** the server's `/api/sync` response, as received — item names, usernames,
  passwords, notes, TOTP seeds, SSH keys and attachment metadata, every field of which is already an
  `EncString` in the server's own format.
- **What is not:** plaintext, any key, and attachment blobs.
- **What an attacker with the file can do:** nothing without the master password or the biometric
  Keychain item, because the account key that decrypts it is wrapped by the master key — the same
  position they were already in with the Keychain entries.
- **What an attacker with the *unlocked* machine can do:** read the ciphertext file — unchanged in
  substance, since they can equally read the vault from the running process.
- **That the lock still means what it means:** locking zeroes the keys, and the cached file is not
  readable without them.

## Verification

Beyond the unit tests listed in `tasks.md`, one manual check carries most of the weight: unlock,
quit, disable the network, relaunch, unlock with the master password, and read an item. Then repeat
with the cache deleted and confirm the app reports the network failure rather than an empty vault.
