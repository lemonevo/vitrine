## ADDED Requirements

### Requirement: The login and unlock screens present one application
Both entry screens SHALL be built from the same card chrome and SHALL identify the application with
its own icon. Neither SHALL substitute a system symbol for the icon.

The two screens are one application answering the same question at two moments, and only one of them
is ever seen twice. They previously disagreed: login drew a stock shield symbol while unlock drew the
real icon, so the app looked like a different product on the second launch.

#### Scenario: Same icon on both screens
- **WHEN** either entry screen is rendered
- **THEN** the application's own icon SHALL appear above the title
- **AND** the card's width, corner radius, padding and border SHALL come from the shared tokens rather than a per-screen value

#### Scenario: A failed attempt is shown the same way on both
- **GIVEN** either entry screen has an error to display
- **WHEN** it renders
- **THEN** the message SHALL appear in the shared error banner, not as a bare line of coloured text
- **AND** it SHALL carry the screen's existing error-message accessibility identifier

---

### Requirement: The login screen orders its fields by how often they are typed
The email and master password fields SHALL be the first fields on the login screen. The server
address SHALL remain a required, editable field — FR-001 — presented below the primary fields and at
a lower visual weight than them.

The server address is entered once per account and then never touched again; the other two are typed
on every sign-in. It previously sat at the top with the same weight as the password, so the least-used
field was the first thing a returning user looked past.

#### Scenario: Server field stays editable
- **WHEN** the login screen is shown
- **THEN** the server field SHALL be a live text field carrying the `login.serverURL` identifier
- **AND** sign-in SHALL stay disabled while it is empty

---

### Requirement: No text field on an entry screen uses a URL as its placeholder
A field whose expected value could read as a URL or an address SHALL carry its example in a hint line
below the control instead of in the placeholder.

AppKit renders a URL-looking placeholder as a detected link — blue and underlined — so an empty field
appears pre-filled with something clickable. The same trap applies to a `Text` given a URL string
literal, because SwiftUI parses Markdown in the key type; values that can look like a URL reach these
views as `String`s.

#### Scenario: Empty server field does not look filled
- **WHEN** the login screen is shown with no server configured
- **THEN** the server field SHALL have no placeholder text
- **AND** the example address SHALL appear in the hint line beneath it, in plain text
