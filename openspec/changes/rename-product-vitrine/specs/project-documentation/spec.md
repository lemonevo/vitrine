## MODIFIED Requirements

### Requirement: GitHub repository is renamed to match the app name

The application and its repository SHALL carry the same name: **Vitrine**, at
`https://github.com/lemonevo/vitrine`. The local git remote `origin` SHALL point at that repository, and
every repository-scoped link the project publishes — the clone commands in its contributor
documentation, its issue and pull-request entry points, its security and accessibility reporting links,
the review ownership rules in `.github/CODEOWNERS`, and the GitHub link the About window builds — SHALL
address it.

The previous owner's repository remains the origin of the code, and the licence's copyright attribution
to it SHALL stay. A rename moves what the project calls itself; it does not move who wrote the first
version, and the README SHALL say both.

The requirement keeps its original heading so this delta replaces it rather than leaving a second,
contradictory requirement behind. It supersedes the same-named requirement in
`openspec/changes/repository-links-at-this-fork/`, which pointed the links at `lemonevo/prizm` — a name
this change retired.

#### Scenario: Contributor clones from the documentation

- **WHEN** a reader copies the clone command from `DEVELOPMENT.md` or `CONTRIBUTING.md`
- **THEN** it addresses `https://github.com/lemonevo/vitrine.git`
- **AND** `git remote get-url origin` in a checkout of this repository names the same repository

#### Scenario: The bundle the user installs is named for the product

- **WHEN** the application is built by either supported path
- **THEN** `CFBundleName` and `CFBundleDisplayName` read `Vitrine`
- **AND** `CFBundleIdentifier` reads `dev.lemonevo.vitrine`, set once and shared by every build path,
      so the login keychain and the operating system see one application rather than three
- **AND** the binary, the Xcode target, the scheme and the Swift module MAY still carry the previous
      name, because renaming those is a build-graph migration and is not this requirement

#### Scenario: The provenance is stated rather than implied

- **WHEN** a reader looks for where this project came from
- **THEN** the README names the upstream project and its author
- **AND** `LICENSE` retains the original copyright line, as MIT requires

#### Scenario: Package distribution links are exempt until they have a target

- **GIVEN** a Homebrew tap command, cask formula, or release workflow that names another owner's
  repository because the artefact it resolves to lives only there
- **WHEN** the documentation is retargeted
- **THEN** those links SHALL be left unchanged and the missing target recorded as a prerequisite
- **AND** the README SHALL NOT present `brew install --cask prizm` as a way to install this application,
      because it installs a different one

#### Scenario: A name change states its own costs

- **WHEN** the product name moves the login keychain service or the application bundle identifier
- **THEN** the change SHALL record that existing stored sessions become unreadable to the new identity
      and that the user will be asked to sign in again
- **AND** it SHALL NOT paper over that with a compatibility shim before there are users to protect
