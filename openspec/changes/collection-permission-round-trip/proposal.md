# Collection permission round-trip — Proposal

## Why

Renaming a collection in Prizm wipes every other member's and group's access to it.

```
RawCollection            decodes id, organizationId, name — and nothing else
PrizmAPIClient:1023-1027 CollectionBody { name, groups: [], users: [] }
PrizmAPIClient:1051      renameCollection sends that body
```

Vaultwarden stores the collection object verbatim, so a field missing from the request body is gone —
the same mechanism documented for ciphers at `RawCipher.swift:123-125`. A rename therefore replaces
the collection with one that has no members and no groups.

`externalId` is lost the same way and is not even decoded: it is used by directory-sync deployments to
keep collections matched to their source.

The local consequence is worse than a server-side one. `VaultRepositoryImpl.renameCollection:666`
builds a **brand new** `OrgCollection` from the three fields it knows, discarding whatever the store
held — so the loss is immediate and the UI agrees with it.

This is the fourth instance of the same defect in this codebase, after the SSH key fingerprint, the
secure-note subtype, and the offline cache's re-encoded payload. They share a signature: **the decoder
is a whitelist, and the encoder invents whatever the whitelist left out.**

## What Changes

- `RawCollection` decodes `groups`, `users` and `externalId`, **opaquely** — permission objects are
  carried as `JSONValue`, not modelled, because their shape varies by server version (`manage` is
  newer than `readOnly`/`hidePasswords`) and because a field this build does not know is exactly the
  thing that must not be dropped.
- `OrgCollection` carries them, so the entity the UI holds is the one that was read.
- `renameCollection` sends them back instead of empty arrays.
- `VaultRepositoryImpl.renameCollection` passes the stored collection's preserved fields through, and
  keeps them in the rebuilt entity rather than constructing one from three fields.
- Creation still sends empty arrays, which is correct: a new collection has no members.

## Non-goals

- **Editing permissions.** Prizm has no UI for granting a member or group access, and adding one is a
  separate feature. This change makes the client *stop destroying* permissions it was given; it does
  not introduce managing them.
- **Modelling the permission shape.** Deliberately opaque: `readOnly`, `hidePasswords` and `manage`
  have already changed across server versions, and a model would have to be right about all of them.
  Round-tripping bytes has to be right about none of them.
- **Reconciling the local cache with what the server returns.** The rename response is discarded today
  (`_ = try await`); this change does not start trusting it, because the failure it guards against —
  losing data — is about what is *sent*.

## Impact

- `Prizm/Domain/Entities/OrgCollection.swift` — `PreservedCollectionFields`, and the field on the entity
- `Prizm/Data/Network/Models/SyncResponse.swift` — `RawCollection` decodes them
- `Prizm/Data/Network/PrizmAPIClient.swift` — `CollectionBody` and `renameCollection`
- `Prizm/Data/Repositories/VaultRepositoryImpl.swift` — carry them through the rename
- `Prizm/Data/Repositories/SyncRepositoryImpl.swift` — pass them from the sync response
