# Surface unreadable items — Design

## Context

`SyncResult.failedDecryptionCount` already exists and already carries the number. The whole change is
about getting it from the sync result to a pixel, plus deciding honestly what the number should
count and how the user should be told.

Where it comes from:

```
CipherMapper.mapContent        → throws unsupportedCipherType / fieldDecryptionFailed
PrizmCryptoService.decryptList → catches per cipher, returns (items, failedCount, keys)
SyncRepositoryImpl.sync        → SyncResult(failedDecryptionCount: failedCount)
VaultBrowserViewModel          → logger.info(...)          ← the only consumer
```

Two counts are dropped on the floor rather than one. `orgCipherFailedCount`
(`SyncRepositoryImpl.swift:259-283`) counts organisation ciphers that could not be mapped — because
the org key was not in the snapshot, or `CipherMapper` failed on them — and reaches only a log line.

## Decision 1 — the number is the total, personal plus organisation

An org item that cannot be read is exactly as invisible as a personal one, and for the user the
distinction does not exist: it is an item that is not in their vault. Publishing the personal count
alone would produce a number that is wrong in the direction that matters — it would under-report.

So `SyncResult.failedDecryptionCount` becomes `failedCount + orgCipherFailedCount`. The field's
documented meaning changes; its name does not, because renaming it would ripple through every
construction site for no gain, and "decryption failures" is still an accurate description of both
halves.

One consequence worth stating: the number now includes a case that is not a decryption failure at
all — an org cipher skipped because the org key could not be unwrapped. That is a *key* failure. Both
present to the user as "this item is not showing", which is the only distinction they can act on, so
they belong in one number. Where that matters for diagnosis, the log lines keep them separate.

## Decision 2 — the sidebar footer, not a banner

The count goes in `SyncStatusView`, below the freshness label.

It is deliberately **not** `syncErrorMessage`'s dismissable banner:

- That banner reports an **event** — a sync just failed. Once the user has read it, dismissing is
  correct, and the information has served its purpose.
- This reports a **condition** — the vault on screen is incomplete. Dismissing it would remove the
  only signal that the list is missing items, while the missing items stay missing. A dismissable
  "your vault is incomplete" is worse than none, because the user can silence it and then forget.

`SyncStatusView` is the right home for the same reason the freshness label is: it is where a user
looks to answer "is what I am seeing the whole truth". It is also pinned outside the scrolling list,
so it cannot be scrolled away.

The two lines are visually distinct — the freshness text stays secondary; the count is a warning with
an icon — because they say different kinds of thing and one of them is a problem.

## Decision 3 — say the items still exist

The tooltip's job is to prevent the wrong conclusion. A user who sees "3 items could not be read"
with nothing else will wonder whether those items were deleted, and the honest answer is the one they
cannot derive from inside the app: they are still on the server, Vitrine just cannot read them right
now.

So the tooltip says both halves. This is the whole point of surfacing the number — a count with no
explanation would be a new kind of alarming without being more useful.

## Decision 4 — singular and plural are separate keys

`L(_:_:)` is `String(format:)` over a looked-up key (`Prizm/App/LocalizationManager.swift:27-32`).
There is no plural machinery, and `Localizable.strings` has no `.stringsdict`. So one key cannot be
grammatical for both cases in English, and the precedent in this file ("%d of %d items could not be
deleted…") is simply wrong for a count of one.

Two keys and a choice in code is three lines and is correct. Chinese uses the same string for both,
which is what its own entry says.

## Decision 5 — the debug type map is fixed here, not separately

`SyncRepositoryImpl.swift:119` labels types as `[1: "login", 2: "identity", 3: "note", 4: "card",
5: "sshKey"]`. Three other places in the codebase — `RawCipher.swift:17`, `CipherMapper.swift:191-193`,
and Bitwarden's own enum — say 2=SecureNote, 3=Card, 4=Identity. The breakdown log therefore
mislabels a secure note as an identity and a card as a note.

It belongs in this change because that log line is what a person reads while diagnosing a sync whose
contents look wrong, and a mislabelled breakdown sends them down the wrong path. It is a one-line
fix with no behaviour change, so it needs no change of its own — but it does need to be stated, or it
looks like scope creep.

## Verification

Unit tests: the count reaches the view model from a sync result; org failures are included; a
subsequent clean sync clears it; `clearSessionState()` clears it with the rest of the session; the
singular and plural strings are the right ones at 1 and at 2.

The manual check is the one that matters and cannot be unit-tested: make a server return a cipher
Vitrine cannot map, unlock, and confirm the sidebar says so while the rest of the vault is usable —
rather than the list quietly being short.
