## ADDED Requirements

### Requirement: The system derives a one-time code from a stored TOTP secret

The system SHALL provide a `TOTPGenerator` that, given the TOTP secret stored on a login item,
returns the current one-time code. The secret SHALL be accepted in either of the two shapes
Bitwarden stores: a full `otpauth://totp/…` key URI, or a bare Base32 secret. Parameters SHALL
default to the Key URI Format defaults — HMAC-SHA1, 6 digits, 30-second period — and SHALL be
overridden by the URI's `algorithm`, `digits` and `period` query items when present.

Base32 decoding SHALL be case-insensitive and SHALL ignore padding (`=`) and embedded whitespace.
The generated code SHALL be zero-padded to the configured digit count.

#### Scenario: RFC 6238 SHA-1 test vector
- **GIVEN** the secret `12345678901234567890` encoded as Base32
- **WHEN** the code is generated for time step 1 (59 s since epoch)
- **THEN** the result SHALL be `94287082` when 8 digits are configured

#### Scenario: Bare Base32 secret uses the defaults
- **GIVEN** a secret stored as a bare Base32 string with no URI
- **WHEN** the code is generated
- **THEN** HMAC-SHA1, 6 digits and a 30-second period SHALL be used

#### Scenario: otpauth URI overrides the defaults
- **GIVEN** a secret stored as `otpauth://totp/Example:alice?secret=…&algorithm=SHA256&digits=8&period=60`
- **WHEN** the code is generated
- **THEN** HMAC-SHA256, 8 digits and a 60-second period SHALL be used

#### Scenario: Base32 input is normalised
- **GIVEN** a secret written in lower case, with padding, or with spaces every four characters
- **WHEN** the code is generated
- **THEN** it SHALL decode successfully and produce the same code as the canonical form

#### Scenario: Code changes with the time step
- **GIVEN** a valid secret
- **WHEN** the code is generated at the last second of a period and again at the first second of the next
- **THEN** the two codes SHALL differ

---

### Requirement: An unusable secret produces no code

The generator SHALL return `nil` rather than a placeholder or an empty string when the stored value
is missing, is not a valid Base32 string, is an `otpauth://` URI without a `secret` parameter,
requests an unsupported algorithm, requests a digit count outside 6–8 (the range RFC 4226 §4.1
defines), or requests a non-positive period.

#### Scenario: Malformed secret yields no code
- **GIVEN** a stored TOTP value of `"not-base32!"`
- **WHEN** the code is generated
- **THEN** the result SHALL be `nil`

#### Scenario: Out-of-range parameters yield no code
- **GIVEN** an `otpauth://` URI with `digits=4`, `digits=12` or `period=0`
- **WHEN** the code is generated
- **THEN** the result SHALL be `nil`
- **AND** the generator SHALL NOT silently fall back to the defaults

#### Scenario: Empty secret yields no code
- **GIVEN** a login item whose TOTP field is nil or empty
- **WHEN** the code is generated
- **THEN** the result SHALL be `nil`

#### Scenario: Unsupported algorithm yields no code
- **GIVEN** an `otpauth://` URI with `algorithm=MD5`
- **WHEN** the code is generated
- **THEN** the result SHALL be `nil`

---

### Requirement: The TOTP secret never reaches the clipboard

The stored TOTP secret SHALL NOT be exposed through any clipboard command, menu item or displayed
field. Only the derived one-time code SHALL be copyable. The secret SHALL NOT appear in log output.

#### Scenario: No command copies the seed
- **WHEN** the Item menu is inspected for a login item with a TOTP secret
- **THEN** no enabled command SHALL place the secret itself on the clipboard

#### Scenario: Secret is not logged
- **WHEN** code generation fails or succeeds
- **THEN** the log output SHALL NOT contain the secret value
