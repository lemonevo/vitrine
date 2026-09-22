# Small parity completions — Proposal

## Why

Two places where an existing surface stops one option short of the official client.

**The generator has no username mode.** Bitwarden's generator offers password, passphrase and
username; Prizm's offers the first two (`PasswordGeneratorConfig.Mode`, `:7-10`). A password manager
that generates a password but not a username leaves the user to invent one, and invented usernames
are the reused kind.

**The Trash says nothing about being temporary.** Bitwarden's Trash states that items are permanently
deleted automatically. Prizm's shows a list, a per-row context menu and an "Empty Trash" bar
(`TrashView.swift:33-58`) and never says that anything will happen on its own — so a user who deletes
an item to "deal with it later" has no way to know the later is time-limited.

## What Changes

- `PasswordGeneratorConfig.Mode` gains `.username`, and a `UsernameGenerator` produces one from the
  EFF word list the passphrase mode already uses. The shape is `word.word<digits>` — readable and
  typable, in the spirit of Bitwarden's random-word username.
- The generator view offers the mode and copies the result through the same clipboard path the other
  two modes use.
- `TrashView` gains a footer stating that items are permanently deleted automatically.

## Non-goals

- **Bitwarden's "forwarded email" username mode.** It creates an address through a third-party relay,
  which means sending the user's data to a service — the same trade this project has already refused
  for breach checking, and written into the UI there. Recorded as refused, not missing.
- **Naming a retention period.** Bitwarden's purge interval is a **server** setting, and Prizm
  implements no endpoint that reads it. Printing "30 days" would be inventing a number for a server
  Prizm cannot see — and worse than saying nothing, because a user would plan around it. The notice
  says the deletion is automatic and does not guess when. Reading the real value is a separate change
  and depends on a server that exposes it.
- **Favourites on top.** It was in this batch and does not belong in it: the item list groups items
  under letter headings when the order is name-based (`ItemListView.swift:37-44`), so "favourites
  first" is a section-layout decision rather than a comparator change, and it would collide with that
  grouping. Moved out rather than bolted on.
- **Archive.** Also moved out: `archivedDate` is preserved on save but there is no endpoint to set it,
  so it needs API work, not a UI.

## Impact

- `Prizm/Domain/Utilities/PasswordGeneratorConfig.swift` — the mode
- `Prizm/Domain/Utilities/UsernameGenerator.swift` — **new**
- `Prizm/Presentation/Vault/Edit/PasswordGeneratorViewModel.swift`, `PasswordGeneratorView.swift`
- `Prizm/Presentation/Vault/Trash/TrashView.swift`
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings`
