## MODIFIED Requirements

### Requirement: GitHub repository is renamed to match the app name

The canonical location of this project's source SHALL be `https://github.com/lemonevo/vitrine`. The local
git remote `origin` SHALL point at it, and every repository-scoped link the project publishes — the
clone commands in its contributor documentation, its issue and pull-request entry points, its security
and accessibility reporting links, the review ownership rules in `.github/CODEOWNERS`, and the GitHub
link the About window builds — SHALL address that same repository. A link that resolves to a different
repository is a claim about where this software comes from, and it has to be true.

The requirement is kept under its original heading so this delta replaces it rather than leaving a
second, contradictory requirement behind.

#### Scenario: Contributor clones from the documentation

- **WHEN** a reader copies the clone command from `DEVELOPMENT.md` or `CONTRIBUTING.md`
- **THEN** it addresses `https://github.com/lemonevo/vitrine.git`
- **AND** `git remote get-url origin` in a checkout of this repository names the same repository

#### Scenario: A user opens the project from inside the app

- **WHEN** the About window is shown and the user activates its GitHub link
- **THEN** the URL the app built is `https://github.com/lemonevo/vitrine`

#### Scenario: A reader reports a vulnerability or an accessibility problem

- **WHEN** a reader follows the private-reporting link in `SECURITY.md`
- **THEN** it addresses the security advisories form of `lemonevo/vitrine`
- **WHEN** a reader follows the reporting link in `ACCESSIBILITY.md`
- **THEN** it addresses the issue tracker of `lemonevo/vitrine`

#### Scenario: Package distribution links are exempt until they have a target

- **GIVEN** a Homebrew tap command, cask formula, or release workflow that names another owner's
  repository because the artefact it resolves to lives only there
- **WHEN** the documentation is retargeted at this repository
- **THEN** those links SHALL be left unchanged, and the missing target recorded as a prerequisite
- **AND** they move only once this repository publishes the release and the tap they would point at

#### Scenario: Identity strings that are not links are out of scope

- **GIVEN** a copyright line or a bundle identifier that carries the previous owner's name
- **WHEN** links are retargeted
- **THEN** the copyright attribution SHALL stay as the licence requires
- **AND** the bundle identifier SHALL NOT change as part of this work, because it keys Keychain access
  groups and code signing rather than pointing at a repository
