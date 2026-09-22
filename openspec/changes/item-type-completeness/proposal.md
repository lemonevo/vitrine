# Item type completeness — Proposal

## Why

Two of Bitwarden's item-type surfaces are unfinished, and one of them is losing data.

**Secure note subtypes are erased on save.** Bitwarden's secure note carries a `type` integer —
Generic, Bank Account, Driver's Licence, Passport, Medical Record, Membership, Social Security, WiFi,
Software Licence. Prizm does not model it:

- `RawSecureNoteData` has the field (`Prizm/Data/Network/Models/RawCipher.swift:198`,
  `let type: Int`), but `mapSecureNote` ignores it and `SecureNoteContent` has nowhere to put it
  (`Prizm/Domain/Entities/VaultItem.swift:289-292`).
- The write path hardcodes it: `RawSecureNoteData(type: 0)`
  (`Prizm/Data/Mappers/CipherMapper.swift:477`).
- Export hardcodes it too: "`type` is always 0" (`Prizm/Domain/Utilities/VaultExportDocument.swift:164`).

So a note whose subtype was set by the official client is silently reset to Generic by opening and
saving it in Prizm, and an export writes it out as Generic as well. This is the same shape as the SSH
fingerprint: a wire field the read path drops and the write path invents.

**Card brand and expiry are free-text.** `CardContent.brand`, `expMonth` and `expYear` round-trip
correctly already — `toRawCard` encrypts and returns all three
(`CipherMapper.swift:514-523`). The forms simply render them as plain text fields
(`CardEditForm.swift:19,23-25`), so a user types "09" or "September" or "9", and a brand name nobody
spells consistently. Bitwarden offers a brand list and month/year pickers.

## What Changes

- A `SecureNoteSubtype` value: the nine known subtypes, plus a case that carries any other raw
  integer **unchanged**. The unknown case is the point — a subtype this build does not recognise
  must round-trip, not be flattened to Generic. Losing data because a server is newer than the client
  is the failure being fixed, and a closed enum would reintroduce it.
- `SecureNoteContent` carries the subtype; the decode path reads it; the encode path writes it;
  export writes it and import reads it.
- The subtype is selectable in `SecureNoteEditForm` and shown in `SecureNoteDetailView`.
- Card brand becomes a picker over Bitwarden's brand list, with the free-text value preserved when it
  matches nothing in the list (the same "do not destroy what you do not recognise" rule). Expiry
  month and year become pickers.

## Non-goals

- **Changing the wire format.** All four values are already strings and integers on the wire; this
  change makes Prizm stop dropping them, not invent a new encoding.
- **Validating the card fields.** A picker prevents most typos, but a value that arrives from the
  server and is not a brand or a valid month is preserved rather than rejected. Prizm is not the
  authority on what a card may contain.
- **The other item types.** Identity and SSH key carry their full field sets already.
- **Migrating existing items.** Nothing to migrate: the values live on the server, and this change
  makes Prizm stop erasing them on the next save.

## A note on the subtype values

The nine values come from Bitwarden's published `SecureNoteType`. They are asserted in tests as the
integers Prizm writes, so a wrong mapping fails loudly rather than silently relabelling a passport as
a bank account. The `unknown(Int)` case means a wrong mapping cannot *destroy* anything either — the
raw value survives regardless of whether this build names it correctly.

## Impact

- `Prizm/Domain/Entities/VaultItem.swift` — `SecureNoteSubtype`, `SecureNoteContent.subtype`
- `Prizm/Domain/Entities/DraftVaultItem.swift` — `DraftSecureNoteContent.subtype`
- `Prizm/Data/Mappers/CipherMapper.swift` — read and write the subtype
- `Prizm/Domain/Utilities/VaultExportDocument.swift` — write it; read it on import
- `Prizm/Presentation/Vault/Edit/SecureNoteEditForm.swift`, `CardEditForm.swift`
- `Prizm/Presentation/Vault/Detail/SecureNoteDetailView.swift`, `CardDetailView.swift`
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — nine subtype names, twelve months,
  the brand list
