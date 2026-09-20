## ADDED Requirements

### Requirement: A vault health report runs five local checks

The application SHALL provide a report that examines the decrypted vault and reports findings for
five checks:

1. **Weak passwords** — login items whose password scores *weak* or lower.
2. **Reused passwords** — passwords used by two or more login items.
3. **Stale passwords** — passwords whose recorded revision date is missing or older than two years.
4. **Unsecured websites** — items with a URI whose scheme is `http`.
5. **Missing two-factor** — login items with a password but no TOTP seed.

The report SHALL make no network request. It SHALL be available whenever the vault is unlocked,
including on a server with no internet access.

#### Scenario: A weak password is reported
- **GIVEN** a login item's password scores 1
- **WHEN** the report runs
- **THEN** that item SHALL appear under weak passwords

#### Scenario: A reused password is reported
- **GIVEN** two login items share the same password
- **WHEN** the report runs
- **THEN** both items SHALL appear under reused passwords

#### Scenario: A unique password is not reported as reused
- **GIVEN** every login item has a distinct password
- **WHEN** the report runs
- **THEN** no item SHALL appear under reused passwords

#### Scenario: A stale password is reported
- **GIVEN** a login item's password revision date is three years old
- **WHEN** the report runs
- **THEN** that item SHALL appear under stale passwords

#### Scenario: A recent password is not reported as stale
- **GIVEN** a login item's password revision date is one month old
- **WHEN** the report runs
- **THEN** that item SHALL NOT appear under stale passwords

#### Scenario: An http site is reported
- **GIVEN** an item has a URI beginning `http://`
- **WHEN** the report runs
- **THEN** that item SHALL appear under unsecured websites

#### Scenario: An https site is not reported
- **GIVEN** every URI uses `https://`
- **WHEN** the report runs
- **THEN** no item SHALL appear under unsecured websites

#### Scenario: A login without a TOTP seed is reported
- **GIVEN** a login item has a password and no TOTP seed
- **WHEN** the report runs
- **THEN** that item SHALL appear under missing two-factor

#### Scenario: A clean vault produces no findings
- **GIVEN** every item has a strong, unique, recent password, an https URI and a TOTP seed
- **WHEN** the report runs
- **THEN** every check SHALL report zero findings

#### Scenario: No network request is made
- **GIVEN** the report is run
- **WHEN** it completes
- **THEN** no network request SHALL have been made

---

### Requirement: Findings name the offending items and can be acted on

Each check SHALL report the number of findings and the name of every offending item. Selecting a
finding SHALL select that item in the vault browser so the user can correct it.

#### Scenario: Item names are listed
- **GIVEN** three items have weak passwords
- **WHEN** the report is displayed
- **THEN** the weak-password section SHALL show a count of 3
- **AND** it SHALL list the three item names

#### Scenario: Selecting a finding opens the item
- **GIVEN** the report lists an item under weak passwords
- **WHEN** the user selects it
- **THEN** the report SHALL close
- **AND** that item SHALL be selected in the vault browser

#### Scenario: An item failing several checks appears in each
- **GIVEN** a login item has a weak, reused, stale password on an http site with no TOTP seed
- **WHEN** the report runs
- **THEN** it SHALL appear under all five checks

---

### Requirement: The omitted breach check is stated rather than silently missing

The report SHALL state that compromised-password checking is not performed and that this is because
it would require disclosing data to a third party. The absence SHALL be visible next to the five
checks that did run.

#### Scenario: The omission is explained
- **GIVEN** the report is displayed
- **WHEN** the user reads it
- **THEN** it SHALL state that compromised passwords are not checked
- **AND** it SHALL state the reason
