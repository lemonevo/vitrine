# CSV export — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`.

## 1. The serializer

- [x] 1.1 Failing test: the header row is the documented column list, in the documented order.
- [x] 1.2 Failing test: the documentation's example row is reproduced exactly
      (`Social,1,login,Twitter,,,0,twitter.com,me@example.com,password123,`).
- [x] 1.3 Failing test: `favorite` and `reprompt` are `1`/`0`, never `true`/`false`.
- [x] 1.4 Failing tests for RFC 4180 quoting:
      - [x] 1.4.1 a value containing a comma is quoted
      - [x] 1.4.2 a value containing a double quote has it doubled
      - [x] 1.4.3 a value containing a newline is quoted, and the row still parses back correctly
- [x] 1.5 Failing test: a login in a folder carries the folder's **name**.
- [x] 1.6 Failing test: a login in no folder has an empty folder column, not `nil`.
- [x] 1.7 Failing test: custom fields serialise as `name:value;name:value`, with empty values kept.
- [ ] 1.8 Failing test: multiple URIs — the documented column is singular, so the first is written and
      the rest are counted as dropped. (Confirm against the docs; if the column can hold several, this
      changes.)
- [x] 1.9 Failing test: non-login items are omitted from the rows **and** counted.
- [x] 1.10 Failing test: a vault with no login items is refused, not written as a header-only file.
- [x] 1.11 `VaultExportCSV.serialise(items:folders:) -> (csv: String, omittedCount: Int)`.

## 2. The use case

- [x] 2.1 Failing test: `execute(format: .json)` is byte-identical to today's output — the regression
      guard for the existing format.
- [x] 2.2 Failing test: `execute(format: .csv)` returns CSV bytes and a `.csv` filename.
- [x] 2.3 `VaultExportFormat`, the parameter on the use case, and `VaultExport.omittedItemCount`.

## 3. Presentation

- [x] 3.1 The backup sheet offers JSON or CSV, with a line saying what CSV cannot carry.
- [x] 3.2 The done sheet shows the omitted count when it is non-zero.
- [x] 3.3 Strings in both language files.

## 4. Verification

- [x] 4.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
- [ ] 4.2 Manual: export CSV and import it into the official client, which is the only check that the
      format is what it claims to be.

> **1.8 is deliberately not done** — several URIs into one column. The documented column is singular
> (`login_uri`), the format has no separator it would split on, and inventing one would produce a value
> no importer parses the way we meant. The first URI is written; the rest are dropped. If the official
> format turns out to accept several, this is the line to revisit.

> **Done.** 1413 tests / 0 failures. 4.2 is outstanding and is the only check that proves the file is
> what it claims to be: **import the exported CSV into the official client.** The tests establish that
> every encoding matches the documentation, including its example row byte-for-byte — which is strong
> evidence, but it is evidence about the documentation, not about the other client.
