# Collection permission round-trip — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`.

## 1. The model

- [x] 1.1 Failing test: `RawCollection` decodes `groups`, `users` and `externalId` from a sync payload.
- [x] 1.2 Failing test: a permission object containing a field this build does not model survives
      decoding — the property that makes the opaque passthrough worth having.
- [x] 1.3 Failing test: a payload with no permission arrays decodes to empty, not to a failure — older
      servers omit them.
- [x] 1.4 `PreservedCollectionFields` and the field on `OrgCollection` and `RawCollection`.

## 2. The request

- [x] 2.1 Failing test: renaming a collection that has groups and users sends them in the body. **Assert
      on the encoded body**, which is where the defect was.
- [x] 2.2 Failing test: a collection with no membership sends empty arrays rather than `null`.
- [x] 2.3 Failing test: `externalId` is sent when it was read.
- [x] 2.4 `CollectionBody` gains the fields; `renameCollection` takes them.

## 3. The repository

- [x] 3.1 Failing test: `VaultRepositoryImpl.renameCollection` passes the stored collection's preserved
      fields to the API.
- [x] 3.2 Failing test: the entity it returns still carries them — the local rebuild is where the client
      came to agree with the loss.
- [x] 3.3 Failing test: creating a collection still sends empty membership.
- [x] 3.4 Carry them through in `VaultRepositoryImpl` and in the sync mapping.

## 4. Verification

- [x] 4.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
- [x] 4.2 Manual: rename a shared collection on a server where another account has access, and confirm
      the other account still has it.

> **Done.** 1398 tests / 0 failures. **4.2 is outstanding** — it needs two accounts on a live server
> (rename a shared collection, confirm the other account still has it). The unit tests assert on the
> **request body**, which is where the defect was; they cannot show that a real server honours it.

## The sweep (added after the tasks above were done)

- [x] Sweep every outgoing body and every `Raw*` model against the pattern, after writing the pattern
      down. Result: no new high-confidence findings; one hole in this change's own fix (the `.empty`
      fallback), closed; two low-reachability items recorded rather than built; one reported claim
      falsified by running it.

