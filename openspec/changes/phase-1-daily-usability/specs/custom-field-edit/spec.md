## ADDED Requirements

### Requirement: Custom fields can be added, renamed, retyped, reordered and deleted

The item edit sheet SHALL allow the user to manage an item's custom fields, not only edit their
values. Specifically the user SHALL be able to:

- add a new field
- rename an existing field
- change an existing field's type
- move a field up or down within the list
- delete a field

Field order in the UI SHALL be the order sent to the server, so reordering is persisted.

Each row SHALL have a stable identity independent of its position, so that deleting or reordering a
row does not transfer one row's transient view state — such as the reveal state of a hidden field —
to another.

An empty field list SHALL NOT render the section header; the "Add field" affordance SHALL be
available regardless.

#### Scenario: Add a field
- **GIVEN** the edit sheet is open
- **WHEN** the user adds a custom field
- **THEN** a new empty text field SHALL appear at the end of the list
- **AND** it SHALL be editable immediately

#### Scenario: Rename a field
- **GIVEN** a custom field named "Old"
- **WHEN** the user changes its name to "New" and saves
- **THEN** the server SHALL hold the field under the name "New"

#### Scenario: Change a field's type
- **GIVEN** a text custom field
- **WHEN** the user changes its type to hidden and saves
- **THEN** the server SHALL hold the field with the hidden type
- **AND** its value SHALL be masked in the detail pane

#### Scenario: Reorder fields
- **GIVEN** custom fields A, B and C in that order
- **WHEN** the user moves C up and saves
- **THEN** the saved order SHALL be A, C, B
- **AND** the detail pane SHALL show them in that order

#### Scenario: Delete a field
- **GIVEN** a custom field
- **WHEN** the user deletes it and saves
- **THEN** the field SHALL no longer exist on the server

#### Scenario: Row identity survives deletion
- **GIVEN** a hidden custom field at position 2 whose value is revealed
- **WHEN** the field at position 1 is deleted
- **THEN** the remaining fields SHALL keep their own reveal state
- **AND** no other row's reveal state SHALL change

#### Scenario: Section header hidden when there are no fields
- **GIVEN** an item with no custom fields
- **WHEN** the edit sheet renders
- **THEN** no "Custom Fields" section header SHALL be shown
- **AND** the add-field affordance SHALL still be available

---

### Requirement: A linked custom field picks from the item's own fields

A custom field of type "linked" SHALL present a picker of the native fields belonging to the item's
own type: username and password for logins; cardholder name, brand, number, expiration month,
expiration year and security code for cards; the identity fields for identities. Secure notes and
SSH keys SHALL offer no linked fields, and the linked type SHALL NOT be selectable for them.

A linked field's value is derived from the field it points at, so it SHALL NOT be independently
editable and SHALL be sent to the server without a value.

Changing a field's type to linked SHALL clear any value it previously held, so that a value the UI
no longer shows cannot be sent.

#### Scenario: Login offers username and password
- **GIVEN** a login item's edit sheet
- **WHEN** the user sets a custom field's type to linked
- **THEN** the picker SHALL offer "Username" and "Password"

#### Scenario: Card offers its own fields
- **GIVEN** a card item's edit sheet
- **WHEN** the user sets a custom field's type to linked
- **THEN** the picker SHALL offer cardholder name, brand, number, expiration month, expiration year and security code
- **AND** it SHALL NOT offer login fields

#### Scenario: Secure notes and SSH keys cannot link
- **GIVEN** a secure note or SSH key edit sheet
- **WHEN** the user inspects the type picker
- **THEN** "linked" SHALL NOT be offered

#### Scenario: Linked field value is not editable
- **GIVEN** a custom field of type linked
- **WHEN** the row renders
- **THEN** its value SHALL be shown as derived and SHALL NOT be editable

#### Scenario: Switching to linked clears the previous value
- **GIVEN** a text custom field with the value "secret"
- **WHEN** the user changes its type to linked
- **THEN** its value SHALL be cleared

#### Scenario: Switching away from linked restores an editable value
- **GIVEN** a custom field of type linked
- **WHEN** the user changes its type to text
- **THEN** its value SHALL become editable

---

### Requirement: A custom field without a name blocks saving

A custom field with a blank name SHALL prevent the item from being saved, and the edit sheet SHALL
say why. The wire format requires a field name, and the mapper skips unnamed fields, so saving
would silently discard the row — leaving the user with a field that appeared to save and did not.

Whitespace-only names SHALL count as blank. The check SHALL apply to every content type, since all
five carry custom fields.

#### Scenario: Blank name blocks save
- **GIVEN** the edit sheet contains a custom field whose name is empty
- **WHEN** the sheet renders
- **THEN** the Save button SHALL be disabled
- **AND** an explanation SHALL be shown

#### Scenario: Whitespace-only name counts as blank
- **GIVEN** a custom field whose name is "   "
- **WHEN** the sheet renders
- **THEN** the Save button SHALL be disabled

#### Scenario: Filling the name re-enables save
- **GIVEN** the Save button is disabled because a custom field has no name
- **WHEN** the user types a name
- **THEN** the Save button SHALL become enabled, provided the item name is also present

#### Scenario: Deleted unnamed field re-enables save
- **GIVEN** the Save button is disabled because a custom field has no name
- **WHEN** the user deletes that field
- **THEN** the Save button SHALL become enabled, provided the item name is also present
