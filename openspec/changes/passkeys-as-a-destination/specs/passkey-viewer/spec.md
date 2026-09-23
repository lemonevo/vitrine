# passkey-viewer — delta

## ADDED Requirements

### Requirement: The vault's passkeys are gathered in one sidebar destination

A sidebar row, placed after Verification Codes, lists every non-deleted item that carries at least
one passkey, so that "which of my items have a passkey" is answerable without opening them one by one.

Whether an item has a passkey SHALL be decided from the credential list the item already carries
unencrypted; entering the destination SHALL NOT decrypt anything by itself.

#### Scenario: The row counts the items that have credentials
- **GIVEN** a vault with three logins carrying passkeys and one of them trashed
- **WHEN** the sidebar renders
- **THEN** the passkeys row SHALL count 2, the trashed item being excluded as it is everywhere else

#### Scenario: An item with no credential is not listed
- **GIVEN** a login whose `fido2Credentials` is empty
- **WHEN** the destination is opened
- **THEN** that item SHALL NOT appear

#### Scenario: The destination itself decrypts nothing
- **GIVEN** the destination has just been selected and no row has been drawn yet
- **WHEN** the list is built
- **THEN** no credential field SHALL have been decrypted

---

### Requirement: Each row names the credentials it holds, decrypted when that row appears

A row SHALL show the item's name and username, how many credentials it carries, and the relying-party
ids it could decrypt. The values SHALL be obtained per row at the moment the row is drawn, and
discarded when it is removed — the destination SHALL NOT decrypt the whole vault's credentials in
order to list them, and SHALL NOT retain decrypted values after their row is gone.

#### Scenario: A row below the fold is not decrypted
- **GIVEN** a destination with more rows than fit on screen
- **WHEN** it is opened
- **THEN** only the rows that were drawn SHALL have been decrypted

#### Scenario: Leaving the destination releases the values
- **GIVEN** rows have been drawn and their credentials decrypted
- **WHEN** the user selects a different sidebar entry
- **THEN** those decrypted values SHALL be discarded with the rows

#### Scenario: One credential failing to decrypt leaves the row standing
- **GIVEN** an item with three credentials of which one cannot be decrypted
- **WHEN** its row renders
- **THEN** the row SHALL still appear, naming the two it could read
- **AND** the count SHALL be the number the item carries, not the number that happened to decrypt

#### Scenario: An item whose credentials all fail to decrypt still appears
- **GIVEN** an item whose every credential field fails to decrypt
- **WHEN** its row renders
- **THEN** the row SHALL appear with its name and count, without relying-party ids
- **AND** the item SHALL NOT silently vanish from a list whose purpose is to say what is present

---

### Requirement: The destination behaves like every other list in the window

The toolbar's search field and sort menu SHALL act on this list while it is showing, and selecting a
row SHALL open that item in the detail column, where the existing passkey section can be expanded.

Search matches the fields the vault search can read without decrypting — the item's name, username,
URIs and folder — and SHALL NOT be presented as though it matched relying-party ids.

#### Scenario: The search field filters this list
- **GIVEN** the destination is selected
- **WHEN** the user types in the toolbar's search field
- **THEN** the rows are filtered, and a query matching none shows a "no item with a passkey matches"
  message rather than the vault-is-empty message

#### Scenario: Sorting offers only what a row has
- **GIVEN** the destination is selected
- **WHEN** the sort menu is opened
- **THEN** the orders offered are the ones a row can actually be ordered by

#### Scenario: A row opens its item
- **GIVEN** a row is shown
- **WHEN** the user clicks it
- **THEN** the detail column shows that item, including its passkey section

---

### Requirement: The destination states what cannot be done with these

The same note the detail section carries SHALL appear here: Vitrine cannot use a stored passkey to sign
in, and the private half is never read. A list of credentials that offers no action reads as a feature
that failed to load.

#### Scenario: The note is on screen with the list
- **GIVEN** the destination is open and has rows
- **WHEN** the user reads the pane
- **THEN** the limitation SHALL be stated on the pane, not hidden behind a control
