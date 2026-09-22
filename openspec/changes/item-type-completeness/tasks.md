# Item type completeness — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`. Until the test target compiles,
> none of the tests below can run.

## 1. The subtype value

- [x] 1.1 Failing tests for `SecureNoteSubtype`:
      - [x] 1.1.1 each of the nine documented integers maps to its case
      - [x] 1.1.2 each case maps back to its integer (the round trip, asserted per case so a wrong
            mapping fails loudly rather than mislabelling)
      - [x] 1.1.3 an integer the build does not know produces `.unknown(n)`, not `.generic`
      - [x] 1.1.4 `.unknown(n)` round-trips to `n`
      - [x] 1.1.5 `.unknown(0)` is distinguishable from `.generic` — the case that makes "we did not
            recognise this" representable even when the raw value is zero
- [x] 1.2 `SecureNoteSubtype` in `Prizm/Domain/Entities/VaultItem.swift`, with `SecureNoteContent`
      carrying a `subtype` that defaults to `.generic`.
- [x] 1.3 `DraftSecureNoteContent` carries it too, copied from the source and passed back on save.

## 2. The wire round trip (the half that was losing data)

- [x] 2.1 Failing test: decoding a cipher whose `secureNote.type` is 3 yields a `.passport` item.
- [x] 2.2 Failing test: encoding that item writes `3` back, not `0`. This is the test that would have
      caught the original bug.
- [x] 2.3 Failing test: an item whose `secureNote` payload is absent decodes to `.generic` rather
      than failing — the server omits the object for older items.
- [x] 2.4 Read the subtype in `mapSecureNote`; write it in the secure-note branch of `toRawCipher`.
- [x] 2.5 Confirm nothing else constructs `RawSecureNoteData(type:)` with a literal.

## 3. Export and import fidelity

- [x] 3.1 Failing test: exporting a passport note writes `secureNote.type == 3`, not `0`.
- [x] 3.2 Failing test: importing that document restores `.passport`.
- [x] 3.3 Failing test: an export with an unrecognised subtype writes the raw integer and re-imports
      to `.unknown(n)`.
- [x] 3.4 Correct the comment on `ExportSecureNote` that states the type is always 0.

## 4. Presentation

- [x] 4.1 `SecureNoteEditForm`: a subtype picker. The `.unknown(n)` case appears as its own row
      labelled with the raw number, so selecting a different subtype is a deliberate act rather than
      the default.
- [x] 4.2 `SecureNoteDetailView`: show the subtype; omit the row for `.generic`, which is the
      default and would be noise on every note.
- [x] 4.3 Strings for the nine names in both language files.
- [x] 4.4 Failing test: `SecureNoteContent.generic` and a decode with no payload produce the same
      value, so the "omit the row" rule above is well defined.

## 5. Card form (no data change)

- [x] 5.1 Failing test: a card whose brand is not in the brand list keeps that brand through
      `VaultItem → raw → VaultItem`.
- [x] 5.2 `CardEditForm`: brand becomes a picker over Bitwarden's list with a "Custom" row that
      holds an unrecognised value; expiry month and year become pickers.
- [x] 5.3 `CardDetailView`: confirm it renders whatever value is stored, including one the picker
      does not offer.
- [x] 5.4 Strings for the brand list and the months in both language files.

## 6. Verification

- [x] 6.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
- [x] 6.2 Manual: with a note whose subtype was set by another client, confirm the detail view shows
      it and that saving from Prizm leaves it unchanged on the server.
- [x] 6.3 Manual: confirm the card pickers write values the server accepts, and that a card whose
      brand is not in the list is not rewritten.

> **6.2–6.3 are outstanding.** They need a signed app against a live Vaultwarden account and a note
> whose subtype was set by another client. What the unit tests establish is that the value now survives
> Prizm's own read→write→read path and its export/import path; what they cannot establish is that a
> real server returns what the fixtures say it does.

> **Unrelated flake, found while running this change's suite — since fixed.**
> `VaultBrowserViewModelActionsTests.test_sortOrder_changeReSortsAndPersists` failed intermittently in a
> full run and always passed in isolation. The first diagnosis (shared preference domain, clobbered
> writes) was too vague; reading further found the actual interleaving: that suite writes the sort key
> to `UserDefaults.standard` and asserts the read-back, while `VaultBrowserViewModelBackupTests` **removes
> the same key from the same domain** in `setUp`/`tearDown` — in a different parallel process. One suite
> was deleting the other's write. Fixed in `openspec/changes/fix-test-preference-isolation/`.
