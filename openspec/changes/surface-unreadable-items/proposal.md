# Surface unreadable items — Proposal

## Why

A cipher Prizm cannot decrypt is dropped, counted, and never mentioned again.

The chain, end to end:

- `CipherMapper.mapContent` throws for a type it does not handle
  (`Prizm/Data/Mappers/CipherMapper.swift:202`), and throws again for a field it cannot decrypt.
- `PrizmCryptoServiceImpl.decryptList` catches each failure and increments a counter
  (`Prizm/Data/Crypto/PrizmCryptoService.swift:293-299`).
- The counter becomes `SyncResult.failedDecryptionCount` (`SyncRepositoryImpl.swift:325`).
- Its **only consumer is a log line** (`VaultBrowserViewModel.swift:890`).

Nothing in the UI reads it. So the failure mode is: the vault unlocks, the list looks complete, and
items are simply not in it. The user's first thought is that they never saved them — or worse, that
something deleted them. There is no way to tell from inside the app that anything is wrong.

The triggers are broader than "a type this version does not know":
field-level decryption failure, a per-item key problem, and — separately counted and equally silent —
an organisation item whose org key could not be unwrapped (`orgCipherFailedCount`,
`SyncRepositoryImpl.swift:270-275`, logged at `:283`).

This is the Constitution's no-silent-failures rule and `CLAUDE.md`'s "no swallowed errors" rule, in
the place where being wrong costs the user the most: they cannot tell their vault is incomplete.

## What Changes

- `SyncResult.failedDecryptionCount` becomes the **total** across personal and organisation items.
  Counting only the personal ones would under-report exactly the case this change exists to expose.
- `VaultBrowserViewModel` publishes the count as `unreadableItemCount`, set from the sync result and
  cleared by `clearSessionState()` along with the rest of the session.
- The sidebar footer renders it below the freshness label, in a warning treatment, with a tooltip
  that states the two things a user needs to know: the items are still on the server, and Prizm could
  not read them.
- It is **not** a dismissable banner. It is a standing fact about the vault's contents, and dismissing
  it would hide the only signal that the list is incomplete. (`syncErrorMessage` stays dismissable:
  that one reports an event — a sync that failed — rather than a condition.)
- Singular and plural strings, chosen in code: `L` performs plain format substitution with no plural
  rules, so one key cannot be correct for both in English.
- The debug breakdown at `SyncRepositoryImpl.swift:119` is corrected. It maps `2: "identity",
  3: "note", 4: "card"` while `RawCipher.swift:17`, `CipherMapper` and the Bitwarden enum all say
  2=SecureNote, 3=Card, 4=Identity. Log-only, but it is the log a person reads *while diagnosing
  exactly this kind of problem*.

## Non-goals

- **Showing which items could not be read.** That needs an "unreadable item" representation in the
  domain layer and a row to render it, because the item's name is encrypted and cannot be read
  either. It is the better experience and a materially bigger change; this one turns a silent loss
  into a visible one first.
- **Retrying, or offering a repair.** Some of these failures are permanent (an unsupported type) and
  some are transient (a locked org key). Distinguishing them needs the per-item reason, which needs
  the representation above.
- **Supporting more cipher types.** No evidence was found that types beyond 1–5 exist — see below.

## A correction to the earlier analysis

The audit this work is based on attributed the problem to "bank accounts / IDs / passports (types
6/7/8, depending on the server version)". **That specific claim is not supported by the code and is
not repeated here.** `RawCipher.swift:17`, `CipherMapper.swift:191-193` and the export path all state
that the type integers match Bitwarden's `CipherType` enum, which ends at 5. Whether a real
Vaultwarden deployment serves 6+ is unverified.

The bug is real and does not depend on that claim: the failure is silent for **any** reason, not just
an unknown type. Fixing the silence covers the unknown-type case for free if it ever exists.

## Not covered by this change

Recorded rather than left unexamined — these are the same class of silence, and neither is addressed
here:

- **Folder names that fail to decrypt** are dropped from the folder list
  (`SyncRepositoryImpl.swift:126-128` logs the count; nothing surfaces it).
- **Attachment metadata that fails to decrypt** drops the attachment from the item.

## Impact

- `Prizm/Domain/Repositories/SyncRepository.swift` — the meaning of `failedDecryptionCount`
- `Prizm/Data/Repositories/SyncRepositoryImpl.swift` — total the count; fix the debug type map
- `Prizm/Presentation/Vault/VaultBrowserViewModel.swift` — `unreadableItemCount`
- `Prizm/Presentation/Vault/Sidebar/SyncStatusView.swift` — render it
- `Prizm/Presentation/Vault/VaultBrowserView.swift` — pass it through
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — singular, plural and tooltip strings
