# Item type completeness — Design

## Context

Two independently-shaped problems got put in one change because they are one surface — "the item
types Bitwarden has that Vitrine does not".

The secure-note subtype is a data-fidelity bug. The read path drops the value
(`mapSecureNote` takes only notes and custom fields, `CipherMapper.swift:233-235`), the domain model
has nowhere to hold it, and both writers hardcode `0`. This is the third instance of the same defect
class in this codebase — after the SSH fingerprint and the collection permissions — and it shares
their signature: **the encoder is a whitelist, and anything not on it is silently discarded.**

The card fields are a usability gap with no data component: `toRawCard` already round-trips all
three.

## Decision 1 — the subtype is an enum with an "unknown" case, not a closed enum

```swift
enum SecureNoteSubtype: Equatable, Hashable {
    case generic, bankAccount, driversLicense, passport, medicalRecord
    case membership, socialSecurity, wifi, softwareLicense
    /// A subtype this build does not know. Carried, not normalised.
    case unknown(Int)
}
```

with `init(rawValue:)` mapping known integers to their cases and everything else to `.unknown(n)`,
and `rawValue` inverting it.

A closed enum is the obvious design and it is wrong here. Its failure mode is the one being fixed: a
server newer than this build serves a subtype the enum does not have, the decoder either throws or
falls back to `.generic`, and the save writes `0`. The user's passport note becomes a generic note,
again, on a slow client.

`.unknown(Int)` makes "we do not recognise this" *representable*, which is what lets it be preserved.
The picker shows the raw number for that case rather than pretending it is Generic — a label that
would be a lie of exactly the kind the old behaviour told.

## Decision 2 — the exact integers are asserted, and cannot lose data even if wrong

The nine values are Bitwarden's `SecureNoteType`. Getting one wrong would mislabel an item in the UI,
so the mapping is asserted in tests rather than left to a comment.

It cannot *destroy* anything: `.unknown(n)` round-trips any integer, so a wrong mapping produces a
wrong label, not a lost value. That asymmetry is deliberate — the cost of being wrong about a name
must not be data.

## Decision 3 — the card brand keeps a value it does not recognise

The brand picker offers Bitwarden's list. A card whose brand is not on it — a regional card, a
typo'd value from another client — must keep what it has. So the picker's selection is `String?`:
a value matching the list selects that row, anything else selects a "Custom" row whose text field
holds the original.

The alternative, a closed picker, would silently rewrite every unrecognised brand to the first entry
the moment the form opened — the same class of bug in a new place, and worse because it would happen
without the user touching the field.

## Decision 4 — expiry month and year stay strings

`CardContent.expMonth` and `expYear` are `String?`, and that is what the wire format uses. A picker
that produced `Int` would need converting at both boundaries and would change what an unrecognised
value does (currently: kept; as an `Int`: unparseable). So the picker selects from the strings the
wire already uses — `"01"`–`"12"` for months, and a year range — and a value outside the range is
preserved as a custom entry.

## Verification

The tests that carry the weight are the fidelity ones, because they are the ones that failed before:

- a decode → encode round trip preserves each of the nine subtypes, and preserves an integer the
  build does not know;
- an export of a non-generic note writes its subtype, and an import restores it;
- a card whose brand is not in the list keeps that brand through a round trip.

The UI is checked manually: a subtype set in another client shows in Vitrine's detail view and survives
an edit.
