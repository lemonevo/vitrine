# URI match type on the wire — Proposal

## Why

**Every URI matching strategy above the first one was being written as its neighbour, and "Never" was
being written as "regular expression".**

`URIMatchType` was an `Int`-backed enum starting at `domain = 0`. The wire — and the comment on
`RawURI.match` in this same repository said so — is Bitwarden's `UriMatchStrategySetting`:
`0=default, 1=baseDomain, 2=host, 3=startsWith, 4=exact, 5=regex, 6=never`. The enum was missing
"base domain" and so named every case one number below what it means, and it had no case at all for 6.

The mapping is a pass-through in both directions, which is what makes it survive a round-trip test:
read 2, get `.startsWith`, write 3. Wrong on the way in, wrong on the way out, perfectly consistent,
and invisible to any test that only checks that a value comes back unchanged.

What a user gets out of that:

- Choosing **"Never"** in the edit form sends **5**, which the browser reads as *regular expression* —
  a rule to autofill, on a site where the user asked for none. This is the one direction in the whole
  app where a security-relevant setting is inverted rather than merely misplaced.
- Choosing **"Host"** sends 1 = base domain, so `https://mail.example.com` and
  `https://other.example.com` both match where only one should.
- A rule set to **Never (6)** in the web vault arrives as `URIMatchType(rawValue: 6) == nil`, displays
  as "Default", and the next save writes `nil`. The setting is gone.
- **A favourite toggle is enough to trigger the rewrite.** `toggleFavorite` builds a full draft and
  issues the same whole-object `PUT` an edit does, so clicking a star silently rewrites every URI rule
  on the item.

This is the fifth instance of the pattern that produced the SSH fingerprint, the secure-note subtype,
the offline-cache re-encode and the collection permissions losses: a decoder reads a field, the model
has nowhere to put it, the encoder omits it, and the server — which stores what it is sent and replaces
the whole object — deletes it. It is the first of the five that changes what a browser does with a
credential.

## What changes

- `URIMatchType` is no longer `Int`-backed. It maps its cases to the wire numbers explicitly, in both
  directions, and gains `.defaultMatch` (0) and `.baseDomain` (1).
- An integer this build cannot name becomes `case unknown(Int)` and is **carried back out unchanged**,
  instead of decoding to `nil` and being erased on the next save. This is the same shape
  `SecureNoteSubtype` already uses for exactly this reason.
- The edit form's picker offers `URIMatchType.selectable`, gains "Base domain", and shows an unrecognised
  strategy as `Unknown (7)` rather than dropping the row or relabelling it "Default".
- The export format is unaffected in shape — it already writes the integer — but the integers it writes
  are now the ones every other Bitwarden client reads.
- **`URIMatchTypeTests`** asserts the wire numbers case by case, in both directions, plus the unknown
  value. A round-trip test alone would have passed the whole time this was broken; that is the point of
  asserting the numbers themselves.
- **`CipherEncoderInvariantTests`** now carries `match: 6` and `match: 7` in its login fixture, so the
  guard that exists to catch this class of loss actually sees these two values. Verified by mutation:
  making the encoder drop `never` turns three tests red with a message that names the consequence.

## Contradicts, deliberately

Nothing in `openspec/specs/`. `uri-add-remove-reorder` covers adding and removing entries, not the
meaning of the integers — which is itself part of how this survived. A spec is added instead:
`specs/uri-match-strategies/spec.md`, pinning the numbers, because "the enum's raw values are the wire
format" is not something a reader can infer from either file.

## Related, found on the way, not fixed here

`Prizm/Presentation/Vault/Sidebar/SidebarView.swift` builds one delete confirmation with curly quotes
(`“%@”`) and `ItemListView.swift` builds the same shape with straight ones (`"%@"`), so both keys exist
in the tables and neither is orphaned. It is a copy inconsistency, not a defect; it is also the reason
the "unused localization keys" sweep in the hygiene change stopped short of deleting any.
