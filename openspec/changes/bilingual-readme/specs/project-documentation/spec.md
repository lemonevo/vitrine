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
      Keychain and zeroed on lock)
- **AND** the threats the application does not defend against are named there, because the file that
      used to hold the full account was removed from the repository

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
- **THEN** they find how to build and test (`⌘R`, `⌘U`) and a brief mention of the openspec workflow,
      because the file that used to hold the full instructions was removed from the repository

#### Scenario: User reads the mission section

- **WHEN** a user scrolls to the bottom of the README
- **THEN** they find the Mission & Principles statement as a closing section

#### Scenario: A reader who is not the author opens the README

- **WHEN** a user with no involvement in the project reads the README
- **THEN** nothing in it is addressed to a maintainer or to an agent: no process instructions, no
      build-system detail only a contributor needs, and no sentence explaining the project to itself
- **AND** the notes that are for a maintainer or an agent are in `AGENTS.md`, which the README does not
      require a reader to open

### Requirement: Community health files exist

The repository SHALL contain the standard GitHub community health files so contributors know the
expectations before opening issues or pull requests.

- `.github/ISSUE_TEMPLATE/bug_report.md` — structured bug report template
- `.github/ISSUE_TEMPLATE/feature_request.md` — structured feature request template
- `.github/pull_request_template.md` — PR checklist

`CODE_OF_CONDUCT.md` is removed from this list. It arrived with the fork, was never edited here, and
was deleted with the rest of the root document set; the templates above are the files that are still
read.

#### Scenario: User opens a new issue

- **WHEN** a user clicks "New issue" on GitHub
- **THEN** they are offered the bug report and feature request templates with pre-filled fields to guide them

#### Scenario: User opens a pull request

- **WHEN** a user opens a pull request
- **THEN** the PR description is pre-filled with the template checklist

## ADDED Requirements

### Requirement: AGENTS.md carries the notes that are not a reader's

The repository SHALL contain an `AGENTS.md` at the root holding the operational facts that a
contributor or an agent needs and a user does not: how the two build paths differ, what the signing
situation does to the keychain, how to tell a real test result from a green-looking one, and which
documents have drifted away from the code. `README.md` SHALL NOT carry these; `CLAUDE.md` SHALL point
at the file rather than repeat it.

Every claim in it SHALL be a fact about this repository, checkable in the repository — and where a
document it mentions is wrong, the entry says so rather than the file staying silent.

#### Scenario: An agent is asked to change something and verify it

- **WHEN** an agent reads `AGENTS.md` before working
- **THEN** it learns that `xcodebuild test` does not update `dist/Vitrine.app`, that a change is only
      visible in the running app after `./build-app.sh` and a relaunch, and that a test run reporting
      success may have executed zero tests

#### Scenario: An agent reads a name that looks wrong

- **WHEN** an agent finds `Prizm` in a path, a scheme or a bundle name in a project called Vitrine
- **THEN** `AGENTS.md` tells it which names were deliberately left alone, which is why, and where that
      decision is recorded

#### Scenario: A reader repeats a claim from the documentation

- **WHEN** an agent or contributor is about to repeat something a document asserts
- **THEN** `AGENTS.md` names the documents that are known to have drifted from the code, so the claim
      is checked first

## REMOVED Requirements

### Requirement: DEVELOPMENT.md exists for contributors

**Reason**: The root document set was cut to `README.md`, `README.zh-Hans.md` and `AGENTS.md` on
2026-09-23. The instructions this requirement asked for were either folded into the README's Install
and Contributing sections or are in `AGENTS.md`; a second copy under a heading of its own was the kind
of document that goes stale unnoticed.

**What still holds**: a contributor can still clone the repository, copy `LocalConfig.xcconfig.template`,
fill in a Team ID, build with `⌘R` and test with `⌘U`. What is gone is the promise of a separate file
that describes it — and with it, the release-signing secret table, which documented five secrets for a
workflow that no longer uses them.

**Migration**: none. The file is in git history (`git show 0014016:DEVELOPMENT.md`).

### Requirement: SECURITY.md exists and documents the threat model

**Reason**: Removed with the root document set. This is the one deletion with a cost worth stating
plainly: the repository no longer contains a written threat model, an algorithm-by-algorithm account
of what is encrypted, or the explicit list of out-of-scope threats. The README keeps a one-paragraph
version of the last of those and names the cryptography in three bullets.

**What still holds**: the cryptography itself is unchanged — Argon2id per RFC 9106, AES-256-CBC with
HMAC-SHA256 encrypt-then-MAC, keys in the Keychain, zeroed on lock. Every algorithm is a public
standard implemented in `Prizm/Data/Crypto/`, which is where a reader now has to go.

**Migration**: none. The file is in git history (`git show 0014016:SECURITY.md`). Restoring a threat
model means writing a new requirement, not repairing this one.


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
