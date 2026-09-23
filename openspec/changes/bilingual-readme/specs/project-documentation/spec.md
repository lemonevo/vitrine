## MODIFIED Requirements

### Requirement: README exists and is release-quality

The repository SHALL contain a `README.md` at the root that serves as the primary landing page for
users discovering Vitrine on GitHub. It SHALL follow this structure: app icon → centered headline →
badges → one-liner → tagline → language switcher → screenshot → Why Vitrine → Privacy → Security →
Features → Requirements → Install → Shortcuts → Roadmap → Known Limitations → Contributing →
Mission & Principles.

The requirement keeps its original heading so this delta replaces it rather than leaving a second,
contradictory one behind. Two of its scenarios described the roadmap and the limitations as they had
been, and one asserted a badge naming a compiler version rather than the language mode the project
compiles in; all three are corrected below. The body of the README is a description of the
application, and this requirement can only be satisfied by reading the application.

#### Scenario: User lands on the GitHub repo

- **WHEN** a user visits the GitHub repository
- **THEN** they see the Vitrine app icon centered above the headline, followed by a centered
      `# Vitrine` headline, a badge row, a one-sentence description ("Native macOS client for
      Vaultwarden and self-hosted Bitwarden, built in Swift."), the tagline "Your secrets. Your server.
      Our user interface.", and a link to the README's other language

#### Scenario: User scans badges

- **WHEN** a user glances at the badge row
- **THEN** they can confirm the CI build status, the **Swift language mode the project compiles in**,
      the minimum macOS version, and the license
- **AND** no badge names a toolchain version, because a reader cannot check one from the repository

#### Scenario: User reads Why Vitrine

- **WHEN** a user reads the Why Vitrine section
- **THEN** they find a direct comparison with the official Bitwarden macOS client, naming what Electron
      costs a Mac user and what a native build gives back

#### Scenario: User reads the Privacy section

- **WHEN** a user reads the Privacy section
- **THEN** they find that nothing is collected and nothing leaves their server
- **AND** they find the two official features deliberately refused for that reason, each with the
      reason — a refusal described as "not yet done" would be a different, false claim

#### Scenario: User reads the Security section

- **WHEN** a user reads the Security section
- **THEN** they find a short list (key derivation, authenticated encryption, keys in the macOS
      Keychain and zeroed on lock) and a link to `SECURITY.md` for the full account

#### Scenario: User reads the feature list

- **WHEN** a user reads the feature list
- **THEN** every item describes what they can do, not how it is implemented
- **AND** every item exists in the application — the list is checked against the code, not carried
      forward from the previous revision

#### Scenario: User reads Requirements

- **WHEN** a user reads the Requirements section
- **THEN** they find the minimum macOS version, the server they need, and the version this project is
      tested against

#### Scenario: User wants to install the app

- **WHEN** a user reads the Install section
- **THEN** they are told there is no tap, and that the command the name suggests installs a different
      application
- **AND** they find the build-from-source route, which is the only one available until a release is
      published
- **AND** they find what to expect from a published release: unsigned, not notarised, and the exact
      steps to open it anyway

#### Scenario: User reads the shortcut table

- **WHEN** a user reads the shortcut table
- **THEN** every entry matches a shortcut the application actually binds
- **AND** the entry for copying a one-time code says "code", not "seed" — the two are different things
      and only one of them belongs on a clipboard

#### Scenario: User reads the roadmap

- **WHEN** a user reads the roadmap table
- **THEN** the "Now" column names work that is actually in progress, not work that shipped

#### Scenario: User reads Known Limitations

- **WHEN** a user reads the Known Limitations section
- **THEN** every entry is still true of the current build

#### Scenario: Technical user wants to contribute

- **WHEN** a user reads the Contributing section
- **THEN** they find a link to `DEVELOPMENT.md` and a brief mention of the openspec workflow

#### Scenario: User reads the mission section

- **WHEN** a user scrolls to the bottom of the README
- **THEN** they find the Mission & Principles statement as a closing section

## ADDED Requirements

### Requirement: The README is available in both languages the application speaks

The application ships in English and 简体中文 and its own rule is that neither is machine-translated.
The documentation that introduces it SHALL hold the same line: a `README.zh-Hans.md` beside
`README.md`, written in Chinese rather than translated into it, with the same section order and the
same tables so that the two can be compared mechanically. Each SHALL link to the other.

The suffix follows the application's own localisation directories, `en.lproj` and `zh-Hans.lproj`, so
the project does not acquire a second spelling of its own language code. The Chinese file is not a
translation of the English one and SHALL NOT be maintained as one: the two are written from the same
facts.

#### Scenario: A reader arrives speaking Chinese

- **WHEN** a reader opens `README.md`
- **THEN** the top of the file offers a link to `README.zh-Hans.md`, and that file offers the way back

#### Scenario: The two files describe the same application

- **WHEN** the two READMEs are compared
- **THEN** they carry the same sections in the same order, the same shortcut table, the same roadmap
      and the same limitations
- **AND** the values in them — versions, limits, commands — are identical, because they are facts
      rather than prose
