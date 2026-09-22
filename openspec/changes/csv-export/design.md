# CSV export — Design

## Context

`ExportVaultUseCaseImpl.execute()` builds a `VaultExportDocument`, encodes it with
`.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`, and returns a `VaultExport` carrying the bytes,
a filename and two counts. The writing is the App layer's job, which is why this type has no
file-system dependency and is testable without touching disk. CSV slots into the same seam: build
different bytes, everything else unchanged.

## Decision 1 — a pure serializer, not a string-building loop in the use case

`VaultExportCSV.serialise(items:folders:)` is a pure function over the items and folders and returns
`(csv: String, omittedCount: Int)`. The use case stays a thin composition, and the escaping rules — the
part that is easy to get subtly wrong and impossible to eyeball in a big file — are testable on their
own.

## Decision 2 — the documented encodings, quoted

From the official import-conditions page, which specifies the file rather than describing it:

| column | encoding |
|---|---|
| `type` | a word — `login` |
| `favorite` | `1` or `0` |
| `reprompt` | `0` or `1` |
| `folder` | the folder's **name**, not its id |
| `fields` | `name:value;name:value` |

And its example row, reproduced verbatim in the tests:

```
Social,1,login,Twitter,,,0,twitter.com,me@example.com,password123,
```

## Decision 3 — logins only, and the omission is counted

The columns are `login_*`: there is nowhere in this schema for a card number, an identity's fields or
an SSH key. The official documentation says the unencrypted formats exclude those types anyway.

What is *not* official is doing it quietly. `serialise` returns the omitted count, `VaultExport`
carries it, and the done sheet shows it — because "I exported 400 items and the file has 300 rows" is
exactly the kind of discrepancy a user must not have to discover by counting.

**Secure notes are counted as omitted too**, though they are arguably representable via `notes`. The
`type` token for a non-login row is not pinned by the documentation, and a guessed token produces a
file that fails on import. Recorded: confirm the token, then include them.

## Decision 4 — RFC 4180 quoting

A value is quoted when it contains a comma, a double quote, CR or LF; embedded quotes are doubled.
Written by hand rather than pulled from a library because the rule is four lines and a dependency for
it would be larger than the code.

This is not theoretical: item names contain commas, notes contain newlines, and a password may contain
both. Unquoted, those produce a file that parses into the wrong number of columns — silently, and
differently depending on the reader.

## Decision 5 — the filename extension follows the format

`prizm_export_<timestamp>.csv` beside the existing `.json`. A `.csv` containing JSON, or the reverse,
is the kind of thing a user would reasonably not check.

## Verification

The tests are the format:

- the header row is exactly the documented column list, in order
- the documentation's example row is produced byte-for-byte from an equivalent item
- a value containing a comma, a quote and a newline round-trips through a permissive CSV parse
- a folder id resolves to the folder's name
- an item in no folder yields an empty folder column rather than the literal `nil`
- non-login items are omitted **and counted**
- a vault with no login items is refused rather than written as a header-only file
