## ADDED Requirements

### Requirement: An existing vault item can be duplicated

The vault browser SHALL offer a duplicate action for the selected item, reachable from the Item
menu via ⌘D and from the item row's context menu. The action SHALL create a new cipher on the
server and SHALL select the new item in the list.

The duplicate SHALL be a new item: it SHALL receive a new identifier, a fresh creation and revision
date, and SHALL NOT modify the original in any way.

The name SHALL be the original name with a localised "(copy)" suffix.

The following SHALL be copied: all type-specific content fields, notes, custom fields, URIs, the
folder assignment, organisation membership, collection assignments, and the re-prompt flag.

The following SHALL NOT be copied, and each exclusion is deliberate:

- **Attachments** — matching the official clients. Copying them would re-upload blobs the server
  already holds.
- **The per-item cipher key** — it is what the original's attachments are wrapped with. A copy has
  no attachments, and sharing the key would leave the original's attachments wrapped with a key
  that two ciphers now claim.
- **Passkeys (`fido2Credentials`)** — a passkey is a credential for one account. Two ciphers holding
  the same credential is a state no Bitwarden client expects, and Prizm offers no UI to inspect or
  remove the copy.
- **Password history** — that history belongs to the original cipher.
- **Archived date** — a duplicate is a new item and is not archived.

The favorite flag SHALL be reset to `false`. Favorites is a deliberate shortlist and adding to it
is the user's decision rather than a side effect of duplicating.

Duplicating an item in Trash SHALL NOT be offered.

#### Scenario: Duplicate creates a new item
- **GIVEN** an item is selected
- **WHEN** the user presses ⌘D
- **THEN** a new item SHALL be created on the server with a different identifier
- **AND** it SHALL be selected in the item list
- **AND** the original SHALL be unchanged

#### Scenario: Name carries a copy suffix
- **GIVEN** an item named "Bank"
- **WHEN** the user duplicates it
- **THEN** the new item's name SHALL be "Bank (copy)"

#### Scenario: Content is copied
- **GIVEN** a login item with a username, password, URIs, notes and custom fields
- **WHEN** the user duplicates it
- **THEN** the new item SHALL have the same username, password, URIs, notes and custom fields

#### Scenario: Folder and organisation membership are copied
- **GIVEN** an item assigned to a folder, or to an organisation and its collections
- **WHEN** the user duplicates it
- **THEN** the new item SHALL have the same folder assignment, and the same organisation and collection assignments

#### Scenario: Favorite flag is not copied
- **GIVEN** a favorited item
- **WHEN** the user duplicates it
- **THEN** the new item SHALL NOT be a favorite

#### Scenario: Passkeys and password history are not copied
- **GIVEN** an item carrying passkeys and password history
- **WHEN** the user duplicates it
- **THEN** the new item SHALL carry neither passkeys nor password history

#### Scenario: Attachments are not copied
- **GIVEN** an item with attachments
- **WHEN** the user duplicates it
- **THEN** the new item SHALL have no attachments
- **AND** the original SHALL keep its attachments

#### Scenario: Duplicate is unavailable in Trash
- **GIVEN** the sidebar selection is Trash
- **WHEN** the item list renders
- **THEN** no duplicate action SHALL be offered

#### Scenario: Failure is reported
- **GIVEN** the server rejects the create request
- **WHEN** the user duplicates an item
- **THEN** an error SHALL be shown and no item SHALL be added to the list
