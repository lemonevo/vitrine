# Retarget repository links at this fork — Tasks

## 1. Documentation URLs

- [x] 1.1 `DEVELOPMENT.md` — clone command → `https://github.com/lemonevo/vitrine.git`.
- [x] 1.2 `CONTRIBUTING.md` — clone command, `issues/new`, and `compare` links → this fork.
- [x] 1.3 `SECURITY.md` — private vulnerability reporting link → this fork's advisories form.
- [x] 1.4 `ACCESSIBILITY.md` — accessibility issue link → this fork's tracker.
- [x] 1.5 `.github/CODEOWNERS` — all five rules were the upstream owner's handle, which grants review
      requests to a collaborator this repository does not have. Now `@lemonevo`.
- [x] 1.6 `README.md` re-checked, not edited: `e9a5262` already moved the badge, download, clone and
      issue links here. See 4.

## 2. About window

- [x] 2.1 **Red first.** Added `testForCurrentApp_gitHubURLEqualsThisRepository`, asserting against
      `AboutViewModel.forCurrentApp()` — the value the About window actually opens.
      Observed failure: `("https://github.com/b0x42/prizm") is not equal to ("https://github.com/lemonevo/vitrine")`,
      and it was the suite's only failure.
- [x] 2.2 **Green.** `AboutViewModel.forCurrentApp()`'s `gitHubURL` → this fork.
- [x] 2.3 Fixture and `testGitHubURL_isCorrect` updated for coherence. Recorded, not fixed here: that
      test builds its own `AboutViewModel` and asserts the URL it passed in, so it cannot fail on a
      stale repository — which is how 2.1's gap survived at all. A test that closes this class of hole
      across the app, not just this URL, is the `encoder-invariant-tests` pattern applied to strings.

## 3. Left alone on purpose

- [x] 3.1 `README.md`'s `brew tap b0x42/prizm`, `Casks/prizm.rb`, `.github/workflows/release.yml`'s tap
      push target, and the canonical `openspec/specs/homebrew-cask/spec.md` that specifies them.
      Verified through the GitHub API: `b0x42/homebrew-prizm` exists and was updated
      2026-07-24; `lemonevo/homebrew-prizm` returns "Could not resolve to a Repository"; `lemonevo/vitrine`
      has 0 releases and 0 tags. Retargeting now would point the install command at a 404.
      Supersedes the open task 6.4 of `remove-dead-code-and-doc-drift`.
- [x] 3.2 `LICENSE` — copyright and Licensor lines name the original author; MIT §"The above copyright
      notice" requires they stay. Not a link to anything the project owns.
- [x] 3.3 Bundle identifier `de.b0x42.Prizm` in `ExportOptions.plist:16` and `project.pbxproj`
      (`de.b0x42.de.PrizmTests`, note the doubled `de.`). Keys Keychain access groups and the signing
      identity; changing it orphans stored secrets on every existing install. Separate change, with a
      migration path.
- [x] 3.4 `openspec/changes/archive/**` — 7 occurrences left as written; they record what was true then.
- [x] 3.5 Canonical `openspec/specs/project-documentation/spec.md` — not hand-edited; the MODIFIED
      requirement lives in `specs/project-documentation/spec.md` here and reaches the canonical file on
      archive.
      **Superseded by `openspec/changes/rename-product-vitrine/`**: the product and repository are now
      Vitrine, so that change's delta on the same requirement is the one to archive. The URLs written
      here (`lemonevo/prizm`) were correct the day they were written and are now the old name.

## 4. Needs the repository settings, not this checkout

Blocking on owner action; each verified 2026-09-22 through `gh api` and `curl`:

- [ ] 4.1 `lemonevo/vitrine` is **private** (`visibility: private`, anonymous API 403). `README.md` calls
      the project open source; one of the two has to change.
- [ ] 4.2 **Issues disabled** (`has_issues: false`, `/issues` → 404), so the issue links in
      `README.md:156`, `CONTRIBUTING.md` and `ACCESSIBILITY.md` land nowhere.
- [ ] 4.3 **Never run a workflow** (0 runs across all branches; badge URL → 404), so the CI badge in
      `README.md:5` renders nothing, and `DEVELOPMENT.md:71`'s "The CI workflow enforces this on every
      push and pull request" is not yet true here.
- [ ] 4.4 **Private vulnerability reporting off** (endpoint → 404). Worst of these to leave broken: a
      security reporter is exactly the reader `SECURITY.md:14` exists for.
- [ ] 4.5 **No releases, no tags**, so `README.md:88`'s download link → 404 and 3.1 stays blocked.

## 5. Verification

- [x] 5.1 Every URL in the repo re-grepped for `b0x42` after the edits; each remaining hit is covered by
      §3 or §4.
- [x] 5.2 Full suite: **1508 passed, 0 failed, 0 skipped** (`** TEST SUCCEEDED **`, 166s wall,
      run 2026-09-22 15:07–15:10 with `CODE_SIGNING_ALLOWED=NO`). One more than the 1507 baseline,
      which is 2.1's new test. `testForCurrentApp_gitHubURLEqualsThisRepository` passed after 2.2.
