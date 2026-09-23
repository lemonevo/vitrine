# Security

Vitrine is a password manager. This document explains exactly how it protects your
data — what is encrypted, where keys live, what threats it defends against, and what
it does not. The goal is to let any developer or technically literate user audit the
implementation and decide whether to trust it. No black boxes.

---

## Reporting a Vulnerability

Please do **not** open a public GitHub issue for security vulnerabilities.

Report privately via GitHub's [Security Advisories](https://github.com/lemonevo/vitrine/security/advisories/new)
or email the maintainer directly (address in the GitHub profile). Include a description
of the issue, steps to reproduce, and any relevant log output or proof of concept.

---

## Encryption

### Data at rest

No vault data is ever written to disk in plaintext. Two pieces of sensitive material
are persisted, both as ciphertext the app cannot read without the master password:

1. The **encrypted user key** (`encUserKey`) and the surrounding session material, in the
   macOS Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — accessible only
   when the Mac is unlocked and only on this specific device, excluded from iCloud
   Keychain and backups.
2. The **offline vault cache**: the server's last `/api/sync` response, stored verbatim in
   the app's container. See **Offline vault cache** below.

| Data | How it is protected |
|------|---------------------|
| Vault items (passwords, card numbers, identities, notes, SSH keys, custom fields) | AES-256-CBC + HMAC-SHA256; decrypted in memory only, after unlock; the ciphertext form of the whole sync response is cached on disk (see below) |
| File attachments | Two-layer AES-256-CBC + HMAC-SHA256; plaintext exists in memory only during upload/download; see "File Attachments" section |
| Master password | Never stored anywhere; used transiently during KDF and then discarded |
| Encrypted user key (`encUserKey`) | AES-256-CBC encrypted by the stretched master key; stored in Keychain |
| Access and refresh tokens | Stored in Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| KDF parameters | Stored in Keychain; required for offline unlock |
| Remembered-device token | Stored in Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; see "Remembered two-factor devices" |

### Offline vault cache

Vitrine can unlock and show the vault with no network. The mechanism is a copy of the server's
last successful `/api/sync` response, written to the app's container at:

```
~/Library/Application Support/Vitrine/vault-cache/<userId>/sync.json
~/Library/Application Support/Vitrine/vault-cache/<userId>/sync.meta.json
```

| Property | Value |
|---|---|
| **Contains** | The `/api/sync` response exactly as the server sent it: item names, usernames, passwords, notes, TOTP seeds, SSH keys, card numbers, identities, custom fields, folder and collection names, and attachment *metadata*. Every content field is already an `EncString` in Bitwarden's own format. |
| **Does not contain** | Any plaintext vault content, any key material of any kind, and attachment *blobs* — attachments are downloaded on demand and are not part of the sync response. |
| **Encryption** | The server's ciphertext, unchanged. Nothing is decrypted to write it and nothing is re-encrypted. |
| **Written when** | After a sync that reached the server *and* whose payload was decoded successfully. A failed or cache-sourced sync never writes. |
| **Deleted when** | Sign-out. **Not** on lock — the file is what makes an offline unlock possible, and locking does not need to remove it (see below). |
| **File permissions** | `0600`, in a `0700` directory. A user id that is not a plain identifier is refused, so the path cannot be made to escape the cache root. |

**The lock still means what it means.** The cache holds ciphertext only. Decrypting it requires
the vault symmetric keys, which are re-derived from the master password (or released by the
biometric Keychain item) at unlock and zeroed at lock. A cached file therefore has the same
standing as the `encUserKey` in the Keychain, which was already at rest: an attacker holding
either one needs the master password to make use of it.

**What an attacker with the file can do.** Read the ciphertext — that is all. They learn the
*number* of items and, because the response's envelope is unencrypted, the vault's structural
skeleton (how many folders, which collections, item types and revision dates). They cannot read
a single field.

**What an attacker with the unlocked machine can do.** Read the ciphertext file. This is a
change in what is reachable on disk but not in substance: such an attacker can equally read the
decrypted vault straight out of the running process, which is already outside what this app
defends against.

### Data in transit

All API communication uses HTTPS/TLS. Vault data is **encrypted before it leaves the
device** — when creating or editing an item, the client encrypts the plaintext fields
using the vault symmetric keys and sends only ciphertext to the server. The server
never receives plaintext vault content or the master key at any point.

Authentication sends a one-way derived hash (`serverHash`) rather than the master
password itself.

**When the app talks to the server.** A sync is a `GET /api/sync` carrying only the session
token; no vault content is sent. One runs at unlock, one when the user asks (⌘R), and one every
five minutes for as long as the vault stays unlocked — plus one when the app comes back to the
foreground or the machine wakes. Nothing is sent while the vault is locked: the refresh timer is
stopped at lock, so a locked session makes no requests at all. Refreshing is the only traffic the
app generates on its own; the other endpoints are reached only in response to something the user
did.

### Algorithms

| Algorithm | Purpose | Implementation |
|-----------|---------|----------------|
| AES-256-CBC + PKCS7 | Vault item encryption / decryption | CommonCrypto (`kCCAlgorithmAES128`, 256-bit key) |
| AES-256-CBC + PKCS7 (Bitwarden binary blob) | File attachment blob encryption | CommonCrypto; blob format: IV(16) ‖ ciphertext ‖ HMAC(32) per Bitwarden Security Whitepaper §4 |
| HMAC-SHA256 | MAC verification (Encrypt-then-MAC) for both vault items and attachments | CryptoKit `HMAC<SHA256>` |
| PBKDF2-SHA256 | Master key derivation (PBKDF2 accounts) | CommonCrypto `CCKeyDerivationPBKDF` |
| Argon2id | Master key derivation (Argon2id accounts) | `Argon2Swift` — thin wrapper around the reference C implementation |
| HKDF-SHA256 | Key stretching | CryptoKit `HKDF<SHA256>` (RFC 5869) |
| RSA-OAEP-SHA1 | Organisation key unwrapping | `Security.framework` `SecKeyCreateDecryptedData` with `kSecKeyAlgorithmRSAEncryptionOAEPSHA1`; SHA-1 is a Bitwarden protocol requirement (Whitepaper §4), not a free choice |

No hand-rolled cryptographic algorithms are used. All implementations are Apple system
frameworks or the vendored `Argon2Swift` package (Argon2id is not provided by Apple
frameworks).

---

## Key Management

### Where keys live

| Key material | Storage | Lifetime |
|---|---|---|
| Master key (32 bytes) | In-memory only | Derived on login/unlock; zeroed on lock or sign-out |
| Stretched keys (enc + mac, 64 bytes) | In-memory only | Derived from master key; zeroed on lock |
| Vault symmetric keys (enc + mac) | In-memory only | Decrypted from `encUserKey`; zeroed on lock |
| RSA private key (PKCS#8, variable) | In-memory only (`actor` state) | Decrypted from `profile.privateKey` EncString during sync; zeroed on lock |
| Organisation symmetric keys (64 bytes each) | In-memory only (`OrgKeyCache` actor) | RSA-OAEP-SHA1 unwrapped from `RawOrganization.key` during sync; zeroed and cleared from `OrgKeyCache` on lock |
| Encrypted user key (`encUserKey`) | macOS Keychain | Persisted across sessions; deleted on sign-out |
| Biometric vault key (64 bytes) | macOS Keychain (biometric-gated) | Created on user opt-in; deleted on sign-out, disable, or biometric invalidation |
| Access token | macOS Keychain | Persisted across sessions; deleted on sign-out |
| Refresh token | macOS Keychain | Persisted across sessions; deleted on sign-out |
| KDF parameters | macOS Keychain | Persisted across sessions; deleted on sign-out |
| Remembered-device token | macOS Keychain | Written only if you tick "Remember this device" at a two-factor prompt; deleted on sign-out, **not** on lock |
| Device identifier (UUID) | macOS Keychain | Stable across sessions; **retained on sign-out** (corrected — this row previously said it was deleted; see the note below) |

### Key lifecycle

1. **Login** — master password + email → KDF (PBKDF2 or Argon2id) → master key →
   HKDF → stretched keys → decrypt `encUserKey` → vault symmetric keys. All in memory.
2. **Sync (organisation keys)** — `SyncRepositoryImpl.sync()` performs additional key
   setup when the account belongs to one or more organisations:
   a. Decrypt `profile.privateKey` EncString with vault symmetric keys → raw RSA private key (PKCS#8); held in actor state.
   b. For each `RawOrganization` in the sync response, strip the PKCS#8 wrapper, import the RSA private key via `SecKeyCreateWithData`, and decrypt `RawOrganization.key` (a Type-4 EncString) with `SecKeyCreateDecryptedData` / `kSecKeyAlgorithmRSAEncryptionOAEPSHA1` → 64-byte org symmetric key.
   c. Store each org key in `OrgKeyCache` keyed by `organizationId`.
   d. Org cipher fields are then decrypted using the org symmetric key rather than the personal vault key, with collection names decrypted via the same org key.
3. **Lock** — all in-memory key material is zeroed. `OrgKeyCache` is cleared: each
   `CryptoKeys` entry's underlying `Data` bytes are overwritten with zeros before the
   dictionary entry is removed. Keychain entries are retained so the vault can be
   unlocked offline without re-authenticating to the server. The offline vault cache is
   likewise retained — it is ciphertext, and without the keys it is unreadable.
   **The decrypted plaintext goes with the keys**: the item list, the selection, and the
   decrypted folder, organisation and collection names are held by the presentation layer as
   well as the vault store, and locking clears both. A sync that was already in flight when
   the lock happened cannot put any of it back — it discards its own result, and the sync
   repository refuses to write to the store or the key caches for a session that has ended.
   The copy commands are additionally disabled while locked, so the menu cannot hand out a
   password from the previous session.
4. **Sign out** — all in-memory key material is zeroed, all Keychain entries for the
   account are deleted, and the offline vault cache for that account is deleted. The app
   returns to a blank login screen. The same plaintext teardown runs as on lock, from the
   same routine, so the two cannot diverge.

### Remembered two-factor devices

Ticking **Remember this device** at a two-factor prompt lets the server recognise this installation
and skip the challenge next time. The token the server issues for that is stored in the Keychain,
alongside the email address it belongs to.

- **What it is worth to an attacker.** It is a credential that lets a login skip a second factor. With
  it, the password alone is enough for that account. It is stored `WhenUnlockedThisDeviceOnly`, so it
  is not in iCloud Keychain, not in a backup, and not readable while the Mac is locked.
- **It is sent only to the account it was issued for.** The stored email is compared against the one
  being signed in with, so it cannot be spent on a different account. That comparison is why the email
  is stored at all.
- **It is deleted on sign-out**, with the rest of the session's material. It is **not** deleted on
  lock: locking keeps you signed in, and a remembered device is part of being signed in rather than of
  the vault being open.
- **The server decides when it expires.** Vitrine stores and replays it, and does not reinterpret its
  lifetime. When the server stops accepting it, the challenge simply reappears — which is the ordinary
  path and needs no special handling.

> **A correction, recorded rather than quietly made.** The table above said the device identifier was
> deleted on sign-out. It is not — `AuthRepositoryImpl.signOut` deletes the account's session keys and
> leaves it. The row now says what the code does. Whether it *should* be deleted is a separate question
> (the sign-out alert promises all local data is cleared), and changing it would give the installation
> a new identity on the server after every sign-out, so it is not being changed as part of this edit.

### PIN unlock

A PIN is an alternative to the master password and to biometrics. It is off by default and must be set
from an unlocked vault.

**What it stores.** Not the PIN. The vault's key material (64 bytes) is wrapped with a key derived from
the PIN — PBKDF2-SHA256, 210,000 rounds, over a random 32-byte salt generated once for this
installation — and the wrapped value is stored in the Keychain under `WhenUnlockedThisDeviceOnly`,
together with the salt and a count of consecutive failures. Nothing anywhere holds the PIN or a hash of
it that could be tested offline: a wrong PIN simply fails to decrypt.

**It deliberately weakens local protection, and the official documentation says so too** — using a PIN
"can weaken the level of encryption that protects your application's local vault database". A
four-character PIN is on the order of ten thousand possibilities. The key derivation is a speed bump,
not the wall, and it is not presented as one.

The protection rests on two things instead:

1. **Where the wrapped key lives.** `WhenUnlockedThisDeviceOnly`: device-only, not synchronised to
   iCloud, not in a backup, unreadable while the Mac is locked.
2. **The attempt limit.** Five consecutive wrong PINs destroy the wrapped value, the salt and the
   count, and sign the user out. **The count is stored**, not held in memory — an in-memory counter is
   cleared by quitting the app, which would make five guesses per restart available indefinitely. That
   is the difference between a limit and the appearance of one.

**Requiring the master password after a restart is on by default**, matching the official client. With
it on, a PIN cannot open an app that has not been opened properly since launch — locking and unlocking
again is unaffected, which is the case a PIN is for. Turning it off is the user accepting that a
four-digit code is all that stands between someone who has the machine and the vault.

**What an attacker with the Keychain item and unlimited guesses can do.** Try PINs. Ten thousand of
them, at 210,000 PBKDF2 rounds each, minus the five they get before the material is destroyed. Against
someone who can also read process memory while the vault is unlocked, none of this matters — that case
was already outside what this app defends against.

**Deleted on sign-out, kept on lock.** A PIN is a way into a session, so it goes when the session does;
locking keeps the session, and therefore keeps the PIN.

### Biometric vault key (Touch ID / Face ID)

When the user enables biometric unlock, the vault symmetric keys (`CryptoKeys`, 64
bytes: 32-byte encryption key + 32-byte MAC key) are stored in a separate macOS
Keychain item protected by `SecAccessControl` with `.biometryCurrentSet`.

| Property | Value |
|---|---|
| What is stored | `CryptoKeys` — 64 bytes (encryptionKey ‖ macKey) |
| Access control | `.biometryCurrentSet` — requires successful biometric evaluation; invalidated if fingerprints are added or removed |
| Keychain class | `kSecClassGenericPassword` with `kSecUseDataProtectionKeychain: true` |
| Synchronizable | `kSecAttrSynchronizable` is NOT set — device-only, never backed up or synced to iCloud |
| Access group | Inferred from `keychain-access-groups` entitlement — not accessible to other apps |
| Created when | User explicitly opts in (enrollment prompt or Settings toggle), vault must be unlocked |
| Deleted when | Sign-out, user disables toggle, or biometric enrollment changes (`.biometryCurrentSet` invalidation) |

The master password is **never** stored in the biometric Keychain item. Only the
already-derived vault symmetric keys are cached. On biometric unlock, the keys are
read directly and passed to `PrizmCryptoService.unlockWith(keys:)`, skipping the KDF
entirely.

---

## File Attachments

Attachments use the Bitwarden two-layer client-side encryption scheme (Security Whitepaper §4).
No plaintext file content is ever sent to the server.

### Encryption scheme

Three encrypted artifacts are produced per attachment:

| Artifact | What it is | How it is encrypted |
|---|---|---|
| Encrypted file blob | The full file contents | AES-256-CBC + HMAC-SHA256 using the per-attachment key; binary layout: IV(16) ‖ ciphertext ‖ HMAC(32) |
| Encrypted attachment key | 64-byte random per-attachment key | EncString type-2 (AES-256-CBC + HMAC-SHA256) using the cipher key |
| Encrypted file name | The original file name | EncString type-2 (AES-256-CBC + HMAC-SHA256) using the cipher key |

The **cipher key** is either the vault symmetric key or a per-item key (if the cipher has
one). The **attachment key** is a freshly generated 64-byte random value for each upload.

### Key locations

| Key material | Storage | Lifetime |
|---|---|---|
| Per-attachment key (64 bytes) | In-memory only | Exists from the start of `upload()` until it returns; zeroed in `defer` |
| Cipher key (64 bytes) | In-memory only | Passed in from the calling use case; never persisted by the repository |
| Encrypted attachment key (EncString) | Bitwarden/Vaultwarden server | Stored as part of the cipher metadata; decrypted on demand during download |

### Temp file lifecycle (Open action)

When a user opens an attachment, the decrypted plaintext is written to a system temp
directory file and opened with the default application. The temp file is:

1. Overwritten with zeros then deleted after **30 seconds** (deadline-based cleanup).
2. Cleaned up on every **foreground transition** (`NSApplication.didBecomeActiveNotification`).

The 30-second window is a trade-off: long enough for the application to load the file,
short enough to limit plaintext exposure if the user switches away without closing the file.

### Upload-incomplete state

If a network failure occurs after the server creates attachment metadata but before the
encrypted blob is fully uploaded, the attachment is marked `isUploadIncomplete = true`.
The server retains the empty metadata record. The client shows a "Retry" action which:
1. Deletes the orphaned metadata record via `DELETE /api/ciphers/{id}/attachment/{attachmentId}`.
2. Performs a fresh upload as a new attachment.

### Threat model additions

- **Server sees only ciphertext** — attachment keys and file contents are encrypted
  before the first API call; the server never receives plaintext.
- **Per-attachment key isolation** — each file is encrypted with an independent 64-byte
  key; compromising one attachment key does not expose other attachments.
- **Temp file exposure window** — the plaintext is on disk for at most 30 seconds after
  opening. A disk image captured during this window could recover the file content.
  Full-disk encryption (FileVault) is strongly recommended.
- **Memory during upload/download** — raw file bytes are held in memory only for the
  duration of the operation, then zeroed. A memory dump during an active upload/download
  could reveal the plaintext.

---

## Vault Export and Import

Export writes an **unencrypted Bitwarden JSON** file to wherever the user chooses. That file
contains, in plaintext:

- every item's name, notes, custom fields and URIs;
- usernames and passwords;
- **TOTP seeds** — which generate every future code for the account, not just the current one;
- **previous passwords**, for any item whose server-side history is present.

It is therefore the single most sensitive artefact the app can produce, and the export sheet says so
before the file is written rather than afterwards. Password history is included because the
interchange format carries it and dropping it would make the file unusable as a backup; the
alternative would be a second "without history" format that no other client reads.

What is **not** supported, and why it matters:

- **No encrypted export.** The password-protected JSON the official clients can write is not
  produced, and the importer refuses one with an explicit error rather than failing part-way.
- **No ZIP.** Attachments are not bundled into the export, so an exported file restores the items
  and not their files.
- **CSV is offered, and it is narrower than the JSON.** It carries logins only — one row per login,
  in the column order the official importer expects — and the `login_totp` column writes the TOTP
  **seed** verbatim, with the same consequence described above. Cards, identities, secure notes and
  SSH keys have no column to go in and are counted and reported rather than dropped silently. The
  sheet that offers CSV says which of these applies before the file is written.

Import accepts the same unencrypted shape, and nothing else. A file that is encrypted, or is another
vendor's CSV, is rejected with a message rather than partially imported — a partial import is the
one outcome that leaves the user unable to tell what they now have.

---

## Password Strength Estimator

The meter and the health report's weak-password check use a local estimator. **It is not `zxcvbn`**,
and the difference is mostly the dictionaries: 609 common passwords rather than 30,000+, one word
list rather than several. Concretely it does not model l33t substitutions (`p@ssw0rd` is not
recognised as `password`), multi-word combinations, names and places, or cross-pattern combinations.

It is biased deliberately: when wrong, it is wrong **low**. A mixed-character password is costed as
the product of its character runs rather than `pool^length`, which understates it. Understating is
the safe direction for a meter; overstating is how a user is talked into keeping a password they
should not have.

Two absences that are refusals, not gaps:

- **No leaked-password check.** It would require sending a hash prefix to a public API. A client
  whose point is self-hosting should not open a connection the user did not configure, so the health
  report states the omission on the face of it rather than leaving it to be assumed.
- **No data-breach check** for the same reason.

A score is an estimate of guessing cost. It is not a statement that a password is safe, and it says
nothing about whether it has been exposed.

---

## Threat Model

### What this app defends against

- **Server compromise** — The server never receives the master password, master key,
  or plaintext vault data. A fully compromised server exposes only ciphertext; an
  attacker must still brute-force the KDF to decrypt it.
- **Disk / at-rest compromise** — Vault data is never on disk in plaintext. What is on
  disk is the Keychain's encrypted user key and the offline cache's ciphertext; neither
  can be decrypted without the master password.
- **Memory dump after lock** — All key material is zeroed on lock, and the decrypted vault content
  the app was holding is dropped with it — the item list, the selection, and the decrypted names. A
  memory dump taken after the vault locks reveals neither usable keys nor usable plaintext. A sync
  already in flight when the lock happened discards its own result rather than restoring either.
- **Clipboard sniffing** — Copied secrets are cleared from the clipboard **30 seconds after they
  are copied, by default**, and best-effort on quit. The interval is a setting: 10 seconds to two
  minutes, or **Never**, and Never means the secret stays on the clipboard until something replaces
  it. Clearing is also not a defence against a clipboard manager the user has chosen to run — it
  reads the value on the way in.
- **Network eavesdropping** — All server communication uses HTTPS/TLS. Vault payloads
  are encrypted before transmission regardless.

### What this app does NOT protect against

- **Compromised macOS installation** — The app relies on macOS sandboxing, Keychain
  integrity, and process isolation. A rootkit or kernel exploit invalidates these
  guarantees.
- **Debugger or memory inspector while unlocked** — While the vault is unlocked, key
  material exists in process memory. An attacker with `task_for_pid` or debugger
  access can read it.
- **Another process running as you, while the vault is unlocked** — Anything on the
  machine running as your user can reach the SSH agent's socket and can read this
  process's memory. The agent's master-password gate closes an unattended path to a
  *signature*; it is a consent boundary, not a cryptographic one. See **SSH Agent**.
- **Keylogger** — The master password is entered via the keyboard. A keylogger can
  capture it before it reaches the app.
- **Physical access while the Mac is unlocked** — Keychain items with
  `WhenUnlockedThisDeviceOnly` are accessible to the app whenever the Mac is in an
  unlocked state.
- **TLS interception (MitM on server identity)** — Certificate pinning is **opt-in per host and
  off by default**, so on a host with no recorded pin, TLS validation rests on the system trust
  store and a certificate issued by any trusted authority is accepted. See **Server Trust** for
  what enabling a pin does and why the default is what it is. This bullet previously stated that
  pinning was not implemented at all, which stopped being true when the feature shipped.
- **Organisation vault access control** — Org keys are RSA-unwrapped client-side; the
  server cannot selectively withhold an org key without breaking sync entirely.
  Role enforcement (owner / admin / manager / user) is applied in the UI layer only
  (e.g., collection management is hidden for non-admin roles). A determined attacker
  with full memory access while the vault is unlocked could bypass these UI gates and
  read or modify org ciphers they have a key for.

---

## Runtime Protections

The app is built with App Sandbox and Hardened Runtime enabled:

- Outbound network connections: allowed (Bitwarden/Vaultwarden API, icon service)
- Inbound network connections: denied
- File system access: read-only, user-selected files only
- No access to camera, microphone, contacts, calendars, location, Bluetooth, USB, or printing

The app writes nothing outside its own container: the Keychain items described above and the offline
vault cache under `~/Library/Application Support/Vitrine/`. Container writes are implicit to the
sandbox and need no entitlement, which is why they are not in the list above; no entitlement grants
access to any other location.

---

## Server Trust

Two optional settings, both off by default and both scoped to the one server the user configured:

- **A private certificate authority** can be trusted, so a self-signed deployment works. When one
  is trusted it is the *only* anchor for that host's chain — the system's own authorities are not
  added alongside it. No App Transport Security exception is enabled, and no other host is
  affected.
- **Certificate pinning** records the SHA-256 of the leaf certificate on the first connection and
  refuses any later certificate that differs. It is opt-in because a pin enabled by default would
  lock a user out of their own server the first time they reinstall it.

The trusted certificate and the recorded fingerprint are stored in the Keychain, per host,
`WhenUnlockedThisDeviceOnly` and never synchronisable — not in `UserDefaults`, which any process
running as the user can rewrite with one `defaults write`.

**What pinning does not cover**, stated because "the connection is pinned" is otherwise read as more
than it says:

- **The first connection.** The fingerprint is recorded from the first certificate seen (trust on
  first use). A pin turned on while something is already intercepting is a pin of the interceptor.
- **Other hosts.** Trust and pinning are scoped to the configured server host. The icon service is a
  different host and is not covered by either — it is configurable, and when it is left unset no
  icon is fetched at all rather than fetched from a default third party.
- **Anything after the TLS handshake.** Pinning authenticates the server. It says nothing about
  whether the server is the one the user meant, whether the account's keys are the ones another
  client would show, or whether the response was tampered with by someone holding the server's key.
  The account fingerprint phrase in Settings is the check for the second of those.

**Untested: the TLS handshake itself.** `ServerTrustPolicy.decide` — the rule that decides what the
handshake is asked to do — is a pure function and is fully unit-tested, and the certificate parsing
is tested against a real certificate. The `SecTrust` evaluation in `ServerTrustDelegate` is not: a
unit test cannot stand up a TLS server with a private authority, and faking `SecTrust` would test
the fake. That gap is recorded here rather than left to be discovered, and it is the first thing to
cover if a test host with a private authority ever becomes available.

---

## SSH Agent

Vitrine can serve the SSH private keys held in the vault to `ssh` and `git` over a Unix socket, so a
key that already lives in the vault does not have to be copied out into `~/.ssh`. The feature is
**off by default**, and the agent runs only while the vault is unlocked.

### What limits it

- **The socket is reachable by anything running as you.** That is what a Unix socket is. The agent
  cannot tell `git` from a script you were talked into running, and it does not try to. This is the
  reason for the gate below, not an oversight.
- **Every key needs the master password, once per unlock.** The first signature request for a key
  asks; later requests for that key do not. Prompting on every signature would make any `git`
  operation that signs more than once unusable, and an agent the user switches off protects nothing
  — which is the outcome this exists to prevent. The grant is still consulted on every request, so
  no signature skips the gate, and every grant is revoked on lock and on sign-out.
- **The gate is a consent boundary, not a cryptographic one.** A correct master password changes
  nothing about the vault: same keys, same session, no unlock. An attacker who can read this
  process's memory bypasses the gate by reading memory, not by answering it. It is described this
  way deliberately — a gate presented as stronger than it is gets relied on for the wrong thing.
- **The request names the process, from the kernel.** The sheet shows the requesting executable's
  name, resolved from `LOCAL_PEERPID` and `proc_pidpath` rather than sent by the client, so a client
  cannot claim to be something else. When the kernel declines to say, the sheet reads "an
  application" instead of guessing.
- **The socket is private to the user.** The directory is created `0700` and the socket is `0600`.
  Vitrine refuses to bind in a directory it did not create, or one whose permissions were widened:
  binding there would hand every signature request to anyone who can write to it.
- **The keys offered are the keys in the vault**, re-read per request rather than snapshotted at
  start, so deleting a key from the vault stops it being offered immediately.

### What it does not cover

- **A process that can read Vitrine's memory while the vault is unlocked** — see the gate above. The
  gate closes an *unattended* path to a signature; it says nothing about memory access.
- **The user approving a request they did not mean to.** The sheet names the process, but the
  decision is the user's. A prompt is only as good as the reading of it.
- **A sandboxed build — which is the configuration the Xcode project builds.** The agent refuses
  to start when the process is sandboxed. A sandboxed app cannot write to the real
  `~/Library/Application Support/`, and a socket inside its own container is not something this
  code has *verified* `ssh` can reach — so the bind would either fail or succeed while no client
  could find it, and coming up green in that state is the one outcome this feature must not
  produce. It is detected before binding and the reason is shown in Settings.

  The consequence, stated plainly: `Prizm/Prizm/Prizm.entitlements` enables
  `com.apple.security.app-sandbox`, so **a release build reports the agent as unavailable**, while
  the local `build-app.sh` build disables the sandbox and is the only configuration where the agent
  runs today. Closing that gap means placing the socket inside the container and verifying that a
  non-sandboxed `ssh` can connect to it — a change of its own, not a tweak, and not something to
  assume either way.
- **Keys Vitrine cannot use.** Only `openssh-key-v1` containers, and only ed25519 and RSA. A
  passphrase-protected key is listed as unusable with that reason: Vitrine stores no passphrase for a
  key and does not prompt for one, so offering it would produce signature requests that can never
  succeed.

### Untested: the end-to-end path

The protocol framing, the key parsing, the signing primitives, the socket lifecycle and the
authorization gate are unit-tested — 103 cases across `SSHAgentPrimitivesTests`,
`SSHAgentSessionTests`, `SSHAgentServerTests`, `SSHAgentAuthorizerTests`, `SSHAgentCoordinatorTests`
and `SSHAgentSectionTests`. The ed25519 and RSA expectations are compared against values computed
**outside** Vitrine (Python `cryptography`), so they test Vitrine's output rather than restate it. No
private key material is committed: the fixtures are assembled from components, and the one key with
a secret in it is built from a seed of repeated bytes.

What the suite does **not** cover is an end-to-end run against real clients: `ssh-add -l` listing
the keys, `ssh -T git@github.com` completing a signature, and a `git` commit that signs. That needs
a real vault with a real key and a real remote. It is recorded here rather than left to be
discovered.

---

## Standards and References

- [Bitwarden Security Whitepaper](https://bitwarden.com/help/bitwarden-security-white-paper/) — vault architecture, key derivation, encryption flow, attachment encryption (§4)
- [RFC 5869](https://tools.ietf.org/html/rfc5869) — HKDF
- [RFC 8018](https://tools.ietf.org/html/rfc8018) / [NIST SP 800-132](https://csrc.nist.gov/publications/detail/sp/800-132/final) — PBKDF2
- [RFC 9106](https://tools.ietf.org/html/rfc9106) — Argon2id
- [NIST SP 800-107](https://csrc.nist.gov/publications/detail/sp/800-107/rev-1/final) — HMAC
