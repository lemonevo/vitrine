# Collection permission round-trip — Design

## Context

The sync response's collection object looks like this once decoded:

```json
{ "id": "…", "organizationId": "…", "name": "2.enc==", "externalId": null,
  "groups": [ { "id": "…", "readOnly": false, "hidePasswords": false, "manage": false } ],
  "users":  [ { "id": "…", "readOnly": true,  "hidePasswords": false, "manage": false } ] }
```

`RawCollection` decodes the first three and drops the rest. The PUT body then says `groups: []`,
`users: []`, and because Vaultwarden stores the object verbatim, those two arrays *become* the
collection's membership.

## Decision 1 — carry the permission arrays opaquely

`PreservedCollectionFields` holds `groups: [JSONValue]`, `users: [JSONValue]` and `externalId: String?`,
following `PreservedCipherFields` exactly — the mechanism this codebase already has for "a field the
client does not understand but must not delete".

Modelling the permission objects was the alternative and is worse here:

- The shape has already moved. Older payloads carry `readOnly`/`hidePasswords`; newer ones add
  `manage`. A model has to be right about every version; an opaque passthrough has to be right about
  none.
- This change is about *not deleting*, not about *reading*. A model would invite a permission editor,
  which is a different change with its own UI and its own authorization questions — and which the
  official client does not offer in a way this build would be matching.

## Decision 2 — the entity carries them, not just the wire type

`OrgCollection` gains the same field.

The alternative — keeping them only in the sync layer and looking them up at rename time — would mean
the repository reaching into a wire-format cache to answer a question about an entity it already
holds. And `VaultRepositoryImpl.renameCollection` currently *rebuilds* the entity from three fields,
which is how the local view comes to agree with the server's loss. Carrying the field on the entity is
what stops that.

## Decision 3 — create still sends empty arrays

A POST that invented membership would be a different and worse bug. Empty is correct there, and the
asymmetry with rename is the point: for a new collection, empty is the truth; for an existing one, it
is a deletion.

## Decision 4 — the rename response is still discarded

`_ = try await apiClient.renameCollection(...)`. The response *does* carry the collection as the server
now has it, so applying it would be more accurate than trusting the local copy.

It is left alone deliberately. The response's shape is the same wire model, so using it would mean
trusting a round trip this change has not yet verified against a real server; and the defect being
fixed is about what is *sent*. Recorded as a known, deliberate simplification rather than an oversight.

## Verification

The tests that matter assert on the **request body**, not on an outcome: a rename of a collection whose
stored form has groups and users must send those groups and users. A test that only checked the local
entity would pass against the very code that loses them on the server.

- a collection carrying groups, users and an `externalId` round-trips all three through a rename
- a collection with no membership sends empty arrays, not `null`
- the local entity keeps its preserved fields after the rename
- an unknown permission field inside a group object survives — the property an opaque passthrough
  exists for, and the one a model would break

## The systematic sweep this change prompted

Three instances of the same defect had been found one at a time, so the pattern was written down and
every outgoing body in the data layer was swept against it (nine `httpBody` sites and every `Raw*`
model). The question asked of each field was: *"for this field, is there a source, or is it a literal /
`nil` / empty array?"*

**Nothing new at high confidence.** Every cipher sub-object now decodes the complete server field set
and its encoder supplies every member; `attachments: nil` was checked rather than assumed and is safe
(Vaultwarden only writes `attachments2` when the key is present, and attachments have their own
endpoints); `RawFolder` is complete; the offline cache stores raw bytes so it does not re-encode.

**One real hole, closed here** — `renameCollection` fell back to `.empty` when the collection was not
in the store (`VaultRepositoryImpl:669`). The same revocation, through a narrower path: a collection
dropped by sync because its name failed to decrypt. Unreachable from the UI today (such a collection is
not in the sidebar either), which is an argument for a cheap guard rather than for leaving it. It now
**refuses** rather than sending an empty membership.

**Two recorded, not built:**

- **`deletedDate: nil`** (`CipherMapper:414`) has no source — `DraftVaultItem` keeps only `isDeleted`.
  Safe today for two reasons that are both load-bearing and neither of which is obvious from that line:
  the UI never builds a draft from a trashed item, and Vaultwarden ignores the field on update. A
  comment at the literal now says so. Carrying the timestamp would be plumbing for a path that cannot
  currently be reached.
- **Forward-map coercions** rewrite values this build does not recognise: `CustomFieldType(rawValue:) ?? .text`,
  and unknown `linkedId` / `match` values dropped. Same shape, LOW reachability (needs a server newer
  than this build). Fixing them properly means `.unknown` cases like `SecureNoteSubtype`'s, which is a
  change of its own.

**One claim falsified, and worth recording because it was plausible.** The sweep reported that
`updateCipherPartial`'s `body["folderId"] = folderId as Any` (`PrizmAPIClient:1104`) would fail to
serialise when `folderId` is nil, making "move to No Folder" the riskiest call in the file. It does not:
a boxed `Optional.none` serialises to `{"folderId":null,...}`, which was checked by running it rather
than by reasoning about Swift bridging. The two call sites *are* asymmetric — the other omits the key
when nil — but which is correct depends on whether the server reads an absent `folderId` as "no change"
or "clear it", and that is not answerable from this repository. **Left alone**: changing it on the
strength of a guess could break the very operation the guess said was broken.

