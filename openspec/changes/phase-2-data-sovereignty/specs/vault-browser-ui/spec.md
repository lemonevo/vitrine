## ADDED Requirements

### Requirement: The File menu offers export and import

The application SHALL offer **Export Vault…** (⌘⇧E) and **Import Vault…** (⌘⇧I) in the File menu.
Both SHALL be disabled unless the vault is unlocked.

#### Scenario: The commands are present
- **GIVEN** the application is running
- **WHEN** the File menu is opened
- **THEN** Export Vault… and Import Vault… SHALL be listed

#### Scenario: Both are enabled while unlocked
- **GIVEN** the vault is unlocked
- **WHEN** the File menu is opened
- **THEN** both commands SHALL be enabled

#### Scenario: Both are disabled while locked
- **GIVEN** the vault is locked
- **WHEN** the File menu is opened
- **THEN** both commands SHALL be disabled

#### Scenario: The commands enable on unlock without waiting for a sync
- **GIVEN** the application was launched with a stored session
- **WHEN** the user unlocks the vault
- **THEN** both commands SHALL become enabled
- **AND** no sync SHALL be required to enable them

---

### Requirement: The Tools menu offers the vault health report

The application SHALL offer **Vault Health Report…** (⌘⇧H) in a Tools menu. It SHALL be disabled
unless the vault is unlocked.

#### Scenario: The command is present
- **GIVEN** the application is running
- **WHEN** the Tools menu is opened
- **THEN** Vault Health Report… SHALL be listed

#### Scenario: Disabled while locked
- **GIVEN** the vault is locked
- **WHEN** the Tools menu is opened
- **THEN** the command SHALL be disabled
