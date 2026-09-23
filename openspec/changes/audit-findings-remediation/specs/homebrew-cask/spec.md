## MODIFIED Requirements

### Requirement: Homebrew tap repository exists with a valid cask formula

This project SHALL NOT offer a Homebrew cask as an install route. It has no tap repository of its own
and publishes no release for one to point at, so `README.md`'s install section states that plainly
rather than offering a command that installs a different application.

`Casks/prizm.rb` in this repository is the upstream project's formula. It is kept because
`b0x42/homebrew-prizm` is the only tap that exists and deleting the file would not make a Vitrine tap
appear. It SHALL NOT be edited to point at this repository, and no workflow in this repository SHALL
write to `b0x42/homebrew-prizm` under any credential.

The requirement keeps its original heading so this delta replaces it rather than leaving a second,
contradictory requirement behind. It supersedes the archived `homebrew-cask` change, whose scenarios
asserted that `brew tap b0x42/prizm && brew install --cask prizm` installs Vitrine from
`b0x42/prizm`'s releases — a command that installs the upstream application. A release workflow in
this repository used to act on that requirement: it cloned that tap with a `TAP_GITHUB_TOKEN` and
rewrote its `version` and `sha256` to this repository's values, while the formula's `url` still
pointed upstream. That step is removed by this change.

#### Scenario: A reader looks for a Homebrew install command

- **WHEN** a reader reads the install section of `README.md`
- **THEN** it states that there is no Vitrine tap
- **AND** it states that `brew install --cask prizm` installs the upstream application, not this one
- **AND** it offers building from source as the route

#### Scenario: The release workflow runs on a version tag

- **WHEN** a `v*` tag is pushed to this repository
- **THEN** the workflow builds a DMG and uploads it as a draft release of this repository
- **AND** it writes to no repository other than this one

## REMOVED Requirements

### Requirement: Cask formula includes correct metadata

**Reason**: The requirement constrains a cask for this application in a tap this project does not
own. The formula that exists is upstream's, and its `name` is `Prizm`, its `homepage` is upstream's
repository.

**What still holds**: nothing that this project can satisfy. Its scenarios were never met, and
`Casks/prizm.rb` carries a header saying so.

**Migration**: none. Nothing consumed it. A future Vitrine tap is a new requirement about a new
repository under this owner, not a repair of this one.

### Requirement: Cask enforces minimum macOS version

**Reason**: As above — it constrains a formula that installs a different application.

**Migration**: none.

### Requirement: Cask declares the app artifact

**Reason**: As above. The formula declares `app "Prizm.app"`; this project's binary is also named
`Prizm` for the reasons `rename-product-vitrine` records, so the requirement as written *reads* as
satisfied while describing the wrong application. That resemblance is the reason to remove it rather
than leave it: a requirement that appears to pass while pointing at upstream's app is worse than no
requirement.

**Migration**: none.
