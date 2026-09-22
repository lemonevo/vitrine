## ADDED Requirements

### Requirement: The built application carries every language the project declares
The application bundle produced by the build system SHALL contain a `Localizable.strings` for every
region the project declares, and the presence of those files SHALL be asserted against the built
bundle rather than against the source tree.

A missing `.lproj` is silent by design: string lookup falls back to the key, which is English, so the
interface degrades to one language without an error, a log line, or a failed build. Two user-visible
features depend on the files being present — the Settings language picker and "Follow System" — and
both fail in the same invisible way when they are not.

#### Scenario: Every declared region resolves in the built bundle
- **GIVEN** the app has been built by the project's own build system
- **WHEN** the localisation resources are looked up for each declared region
- **THEN** an `.lproj` SHALL exist for that region
- **AND** it SHALL contain a non-empty translation for a key on the unlock screen

#### Scenario: Registering the strings is not optional
- **WHEN** the localisation files are removed from the app target's resources
- **THEN** the test suite SHALL fail
- **AND** it SHALL fail against the built bundle, not against a checkout path that would succeed anyway

---

### Requirement: Every interface string exists in every shipped language
A key present in the English table SHALL be present in every other shipped language table. A key
present only in a translation SHALL be reported.

Keys are written as English sentences at their call sites, so an untranslated key renders English text
inside a Chinese interface — the same silent degradation as a missing table, at one string at a time.

#### Scenario: A key added to English only is named
- **GIVEN** a new key in the English table with no counterpart
- **WHEN** the suite runs
- **THEN** the failure SHALL list the missing key rather than only a count

#### Scenario: The comparison cannot pass on an unreadable file
- **GIVEN** a strings table that decodes to nothing
- **WHEN** parity is checked
- **THEN** the test SHALL fail rather than compare two empty sets as equal
