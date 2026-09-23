# Audit findings remediation — Design

## Decision 1: do not re-send collection membership on an edit

**The defect.** `VaultRepositoryImpl.update` called `updateCipherCollections` on every organisation
item, passing `draft.collectionIds`. `RawCipher` decodes `collectionIds` as
`(try? decode([String].self, forKey: .collectionIds)) ?? []`, so a membership that is absent **and**
one that fails to decode both arrive as `[]`.

**Why that is destructive, from the server's own source.** Two endpoints matter, and they behave
differently:

- `PUT /api/ciphers/{id}` — `put_cipher` calls `update_cipher_from_data(..., shared_to_collections:
  None, ..., UpdateType::SyncCipherUpdate)`. Inside `update_cipher_from_data` the only use of that
  parameter is `nt.send_cipher_update(..., shared_to_collections, conn)` — the push notification.
  There is no `CollectionCipher::save` or `::delete` in the function at all.
- `PUT /api/ciphers/{id}/collections` — `post_collections_update` builds
  `posted_collections` and iterates `posted_collections.symmetric_difference(&current_collections)`,
  saving or deleting membership per element. An empty `posted_collections` therefore *removes* the
  item from every collection it is currently in.

So the cipher PUT cannot damage membership, and the collections PUT is the only call that can — and
re-sending a value this client never learned is exactly how it does damage. Editing an organisation
item's name was enough.

**The decision.** Delete the call rather than guard it.

A guard (`only send when non-empty`) was considered and rejected: it encodes "empty is never
meaningful" as an assumption in the write path, when empty *is* meaningful to the endpoint. Deleting
the call states the real invariant — nothing in this client changes membership, so nothing should
send it — and removes a redundant request per edit. Design Decision 1 of
`critical-integrity-fixes` already established that a value the client does not understand must be
carried, not reconstructed; this is the same rule applied to a value that must not be sent at all.

**What this forecloses.** A future membership editor must call `updateCipherCollections` from that
action alone. That is written at the call site so the next reader does not restore the old shape.

**The tests, and the check that they are not vacuous.** Two regression tests assert the call count is
zero — one for an org item with a known membership, one for the degraded case whose membership
decoded as empty. Both were confirmed to **fail** against the previous implementation (`("1") is not
equal to ("0")` at the call-count assertion) before the call was removed, so they pin the defect
rather than the fix.

## Decision 2: remove the Homebrew cask step, do not repoint it

The release workflow cloned `b0x42/homebrew-prizm` with a `TAP_GITHUB_TOKEN` and rewrote that
repository's `Casks/prizm.rb`: `version` became this repository's tag, `sha256` became this
repository's DMG. The cask's `url` is `https://github.com/b0x42/prizm/releases/download/...`, which
this workflow never changed — so the result is a cask whose checksum cannot match its URL.

Consequences if a `v*` tag is ever pushed while a token is configured: every upstream user's
`brew install --cask prizm` breaks, against a release they did not ask for. That is a change to
someone else's repository, and it is the one finding in the audit that reaches outside this one.

**The token was never configured, and the audit's first report overstated the danger.** `gh secret
list` exits 0 with no rows on this repository, so the step would have hit its own guard
(`if [[ -z "${TAP_GITHUB_TOKEN:-}" ]]`), printed a `::warning::` and exited 0 without pushing. Nothing
was ever at risk, and there is no secret to delete — an earlier draft of this design asked the owner
to remove one. The step is removed anyway, for the reason in the workflow comment: it asserts an
ownership this project does not have, and the next person to add a token would arm it.

Repointing the step at a new tap is not possible today: a tap needs a repository of its own under
this owner plus a published release to point at, and neither exists. So the step is deleted, with
the reasoning recorded in its place, and `Casks/prizm.rb` keeps its existing header saying it is
upstream's cask.

## Decision 3: leave the internal `Prizm` names alone

The audit listed the surviving `Prizm` strings in `build-app.sh`, `CFBundleExecutable` and
`Prizm_V2.icon` as an unfinished rename. That was wrong, and this change records why so it is not
"fixed" later: `rename-product-vitrine/proposal.md` lists them under *Not changed, and why* —
"Asset and binary names belong to the target", and renaming the target graph is a migration, not a
find-and-replace. The scheme is in the same list, and `b56367f5` exists because a markdown sweep had
already turned six working build commands into `-scheme "Vitrine"`.

What *was* a real defect is `reset-keychain.sh`: it deleted service `com.prizm`, while the session
store has been `dev.lemonevo.vitrine` since the rename (`KeychainService.swift:115`). It found the
one leftover item and missed both live ones — the opposite of what it is for, and it reported
success. It now covers the current session store, the biometric key, and the pre-rename service, and
its `--list` output names each one.

## Decision 4: which documentation statements were wrong, and how they were established

Each was checked against the code, not against another document:

| Statement | Reality |
|---|---|
| "No CSV, no ZIP. Only the one JSON shape." | `VaultExportCSV` exists, is reachable from the export sheet, and its `login_totp` column writes the seed |
| "Certificate pinning is not implemented." | It is implemented and **opt-in**, default off (`ServerTrustConfiguration.swift`) — the same file's Server Trust section describes it correctly, so the document contradicted itself |
| Clipboard "cleared after 30 seconds" | 30 s is the **default** of a setting ranging 10 s to two minutes plus Never |
| Cache under `Application Support/Prizm/` | `VaultCacheStoreImpl.defaultDirectory` appends `"Vitrine"` |
| README: "this repository is private" | It is public; it still has no releases, which is the part that matters for the 404 |

## Not settled here

**Argon2id accounts.** `makeServerHash` always uses PBKDF2 over the master key. Bitwarden's
specification derives the server hash that way for both KDFs, so this is probably correct, but the
tests only assert length and determinism and there is no known-answer vector. Confirming it needs a
real Vaultwarden account configured for Argon2id; it is recorded rather than changed, because
changing a login hash on a guess would lock users out.
