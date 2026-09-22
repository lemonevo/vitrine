# Retarget repository links at this fork — Proposal

## Why

This build is no longer a mirror of `b0x42/prizm`. The work of the last months — the three-pane
redesign, offline vault read, background sync, PIN and biometric unlock, the attachment pipeline, the
encoder invariant tests — has no counterpart upstream, and none is going to be contributed back. Yet
every pointer that tells a reader where this project lives still addressed the upstream repository, so
a contributor following `CONTRIBUTING.md` cloned a codebase that does not contain this app, and a user
clicking the GitHub link in the About window was sent somewhere else than the build they are running.

The second reason is honesty. A link to a repository that is not this one is a claim about provenance
that this project no longer stands behind.

## What changes

Every repository-scoped URL in the user-facing documentation, the app's About window, and the
code-review ownership file moves to `https://github.com/lemonevo/vitrine`:

- `DEVELOPMENT.md` — the clone command.
- `CONTRIBUTING.md` — the clone command, the "open an issue" link, the "open a PR" link.
- `SECURITY.md` — the private vulnerability reporting link.
- `ACCESSIBILITY.md` — the "report an accessibility issue" link.
- `AboutViewModel.forCurrentApp()` — the URL the About window opens.
- `.github/CODEOWNERS` — review ownership, which was the upstream owner's handle on every path.

`README.md` was moved to this fork by `e9a5262`; this change does not touch it. See **Open** below for
what that commit left in a state this change cannot fix from the checkout.

## What deliberately does NOT change

- **The Homebrew tap**: `README.md`'s `brew tap b0x42/prizm`, `Casks/prizm.rb`, and the push target in
  `.github/workflows/release.yml`. Verified against GitHub's API while writing this: `b0x42/homebrew-prizm`
  exists and is updated; `lemonevo/homebrew-prizm` **does not exist**, and `lemonevo/vitrine` has **zero
  releases and zero tags**, so a retargeted cask would resolve to a download URL that returns 404. That
  turns a working install command into a broken one. The prerequisite is a tap repository and a published
  release here, not a search-and-replace. This supersedes task 6.4 of
  `openspec/changes/remove-dead-code-and-doc-drift/`, which recorded the same mismatch as unverified.
- **`LICENSE`** — the copyright line names the original author. MIT requires it to stay.
- **The bundle identifier `de.b0x42.Prizm`** (`ExportOptions.plist`, `project.pbxproj`). It is not a link:
  it keys Keychain access groups and the signing identity, so changing it strands every stored secret on
  existing installs. Its own change, with its own migration.
- **`openspec/changes/archive/**`** — historical records of what was true when those changes shipped.

## Impact

- Affected specs: `project-documentation` (one MODIFIED requirement).
- Affected code: one production string in `Presentation/About/`, plus a test that for the first time
  asserts the URL the About window actually builds. The pre-existing `testGitHubURL_isCorrect` compares a
  hand-built fixture against itself and cannot notice a stale URL.
- Affected docs: four files, seven URLs.
- No dependency, no build setting, no user-visible behaviour beyond the About window's link.

## Open — needs action on GitHub, not in this checkout

Retargeting the links makes them *correct*; it does not by itself make them *reachable*. As verified on
2026-09-22, `lemonevo/vitrine` is **private**, has **Issues disabled**, has **never run a workflow**, and
**private vulnerability reporting is off**. So until the owner acts on the repository settings:

- the CI badge in `README.md` returns 404 (no workflow run exists to render),
- `README.md`'s download link returns 404 (no release, no tag),
- the issue links in `README.md`, `CONTRIBUTING.md` and `ACCESSIBILITY.md` return 404,
- the `SECURITY.md` advisory link returns 404 for anyone not already a collaborator, which for a
  security-reporting path is the worst of these to leave broken,
- and the clone commands only work for members.

`README.md` also asserts the project is open source. That sentence and a private repository cannot both
stay as they are. Making the repository public is an owner decision and is not attempted here.
