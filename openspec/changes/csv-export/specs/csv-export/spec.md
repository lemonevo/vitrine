## ADDED Requirements

### Requirement: The vault SHALL be exportable as CSV in Bitwarden's documented shape

The export SHALL offer a CSV format alongside the existing JSON, with the documented columns in the
documented order:

`folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp`

#### Scenario: The header is the documented column list

- **GIVEN** a CSV export of any vault
- **WHEN** the file is read
- **THEN** its first row SHALL be the documented column names in the documented order

#### Scenario: Values are encoded as documented

- **GIVEN** a login item marked as a favourite with re-prompt protection, in a folder
- **WHEN** it is exported as a row
- **THEN** `favorite` and `reprompt` SHALL be `1` or `0`
- **AND** `type` SHALL be `login`
- **AND** `folder` SHALL be the folder's name

### Requirement: A value containing CSV syntax SHALL be quoted

Values containing a comma, a double quote, or a line break SHALL be quoted as RFC 4180 requires, with
embedded quotes doubled, so that a row always parses back into the same number of columns.

#### Scenario: An item name with a comma

- **GIVEN** an item whose name contains a comma
- **WHEN** it is exported and the file is parsed back
- **THEN** the name SHALL be unchanged

#### Scenario: Notes with a newline

- **GIVEN** an item whose notes span several lines
- **WHEN** it is exported and the file is parsed back
- **THEN** the notes SHALL be unchanged
- **AND** the row SHALL NOT be split

### Requirement: Items the format cannot carry SHALL be reported

CSV carries logins only. Items of other types SHALL be omitted, and the number omitted SHALL be
reported to the user.

#### Scenario: Non-login items are counted

- **GIVEN** a vault containing cards, identities, secure notes and SSH keys
- **WHEN** it is exported as CSV
- **THEN** those items SHALL NOT appear as rows
- **AND** their number SHALL be reported

#### Scenario: Nothing to export is refused

- **GIVEN** a vault with no login items
- **WHEN** a CSV export is requested
- **THEN** the export SHALL be refused rather than producing a file with only a header
