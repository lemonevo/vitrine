# Passkeys as a destination — Proposal

## Why

`passkey-viewer` (in `phase-2-data-sovereignty`) made passkeys visible **one item at a time**: the
detail view has a collapsed section, and opening it decrypts that item's credential fields. Nothing in
the app answers the question that section presupposes — *which of my items have passkeys at all?* A
user with a few hundred logins finds out by opening them one by one, and there is no way to see
whether a site they expected to be able to sign in to has a credential here or not.

The sidebar already solved the same shape of problem for one-time codes: `SidebarSelection
.verificationCodes` is a row that gathers every item carrying a key into one screen. This is that row,
for passkeys, placed directly under it.

## What changes

- **`SidebarSelection.passkeys`** — a new case, with a sidebar row under Verification Codes showing
  how many items carry at least one credential.
- **`.passkeys` is a real indexed selection in `VaultRepositoryImpl.buildIndexes()`**, filtered by
  `item.preserved.fido2Credentials` being non-empty. This is the one structural choice worth stating,
  because it is where this destination differs from the codes one:
  the codes destination reads the vault itself and builds its own rows, because a code is derived
  state that no item list carries. A passkey's *existence* is already on the item, unencrypted —
  `CipherMapper` fills `fido2Credentials` from the wire at decode time and nothing decrypts it — so
  making it an ordinary selection means `items(for:)`, `itemCounts()`, `searchItems(query:in:)` and
  the toolbar's sort menu all start working for it without a line of new plumbing. The pane is then
  only responsible for the one thing that does need new machinery: the per-row decryption.
- **`PasskeysPane`** — one row per item: its name, its username, how many credentials it holds, and
  the relying-party ids those credentials are registered with. Rows come from
  `viewModel.displayedItems`, so filtering and ordering are the window's existing behaviour rather
  than a second copy of it.
- **Per-row lazy decryption.** Each row owns a small view model that calls
  `VaultRepository.passkeys(for:)` when the row appears, and drops the values when it goes away. The
  pane never asks for the whole vault's credentials in one go.
- **A `passkey-viewer` delta** adding the destination as a requirement, with the four existing
  requirements' constraints carried forward rather than restated.

## What this does not change about passkeys

`passkey-viewer`'s rules are about a detail section; this adds a second place that shows the same
data, so each of its four requirements had to be checked against the new surface rather than assumed:

- **The private key is never read.** The pane renders `PasskeyCredential` values, and that type has no
  field for `keyValue` — the same shape that makes it a property of the code in the detail view, so
  the list inherits it. No copy control appears on a row.
- **Decrypted on demand, never cached.** "When the section is rendered" becomes "when the row is on
  screen". `LazyVStack` means a row below the fold has not appeared and has not been decrypted;
  leaving the destination tears the rows down, which releases every value they held. Nothing is
  retained in the domain model, and the pane holds no dictionary of decrypted credentials.
- **The limitation is stated.** The pane carries the same footnote the section does. A list of
  passkeys that offers nothing to *do* with them reads as a broken feature unless it says why.
- **A malformed entry does not hide the rest.** `passkeys(for:)` already omits what it cannot
  decrypt; the row shows the count of credentials it has against the count it could name, so a row
  that says "3" and lists two is honest rather than silently wrong.

## Search, and what it cannot reach

Typing in the toolbar filters this list through the ordinary vault search, which matches item names,
usernames, URIs and folder names. It does **not** match a relying-party id, because on the wire those
strings are EncStrings and matching them would mean decrypting every credential in the vault to
answer one keystroke. So searching `github` finds the item named "GitHub" and not an unnamed item
whose only passkey is for `github.com`. The empty-results message says "no item with a passkey
matches", which is the truth; the alternative would be a promise this list cannot keep.

## Impact

- 1 new view file (`Presentation/Vault/Passkeys/PasskeysPane.swift`), registered in
  `project.pbxproj` — the app target compiles from an explicit Sources phase.
- `SidebarSelection`: one case, one display name, one `==` arm, one hash arm.
- `VaultRepositoryImpl.buildIndexes()`: one selection added to the pre-built lists and counts, which
  is what `vault-actor-isolation`'s "indexes rebuild after every write mutation" requirement already
  expects of a new selection.
- `MockVaultRepository.items(for:)`: the matching case (its switch is exhaustive).
- Plumbing mirrors the codes destination: `AppContainer` factory, `PrizmApp` dependency protocol,
  `VaultBrowserView` route, `AccessibilityID.Passkeys` pane identifiers.
- New strings in **both** `en.lproj` and `zh-Hans.lproj`.
- No wire-format, crypto, or domain-model change; `PasskeyCredential` and `passkeys(for:)` are reused
  as they stand.
