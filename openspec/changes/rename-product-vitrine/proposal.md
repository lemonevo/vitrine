# Rename the product: Prizm → Vitrine — Proposal

## Why

This build is not the project it was forked from. The three-pane redesign, offline read, background
sync, PIN and biometric unlock, the verification-codes screen, the encoder invariant tests, and the
auth screens have no counterpart upstream, and none will be contributed back. Sharing a name with the
upstream while shipping a different product is the worst of both: users searching for one find the
other, and the fork inherits trust it did not build.

The name is **Vitrine** — a glass display case. It says the two things the project actually claims:
what is inside is valuable, and you can see it.

## Scope of the rename

What a rename can change cheaply is the *product's* name. What it cannot is the *build's* internal
names, which are the Xcode target, the Swift module, the scheme, the executable, the source directory
and the asset names. Renaming those is a separate, much larger sweep — it touches 162 test files'
`@testable import Prizm`, `Package.swift`, the `project.pbxproj` target graph, and `Prizm_V2.icon`.
This change deliberately leaves them alone and says so at each site that would otherwise read as a
mistake.

### Changed

- **User-visible name**: 55 lines across 32 Swift files, and **77 occurrences in each localisation
  table**. Because this project's rule is that the key *is* the English sentence, a rename moves keys,
  not just values — which is exactly why `LocalizationResourcesTests` is the check that matters here.
- **Identity strings**: `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier`
  (`dev.lemonevo.vitrine`), the `NSFaceIDUsageDescription`, the login keychain service
  (`kSecAttrService`), the logging subsystem (`com.prizm` → `dev.lemonevo.vitrine`, 45 sites), the
  `User-Agent` (`Vitrine/2024.12.0`), the `deviceName` reported to the server, and the SSH agent
  socket directory.
- **Version**: `MARKETING_VERSION` 1.4.3 → **0.0.1**, `CURRENT_PROJECT_VERSION` 12 → 1, in all four
  build configs *and* in `build-app.sh`'s generated Info.plist, which hardcoded its own copy. The old
  number collided with upstream's latest release.
- **Docs**: 72 files, 246 lines. `openspec/changes/archive/**` untouched — it records what was true.
- **README install section**: rewritten, because `brew install --cask prizm` now installs a *different
  application* than the one the README describes.

### Not changed, and why

| Left as `Prizm` | Reason |
|---|---|
| Xcode target, scheme, module, `Prizm.xcodeproj`, `Prizm/` source dirs, `PrizmTests` | Renaming is a target-graph migration, not a find-replace |
| Type names `PrizmAPIClient`, `PrizmCryptoService*` | Internal; they follow the module |
| `Prizm_V2.icon`, `CFBundleExecutable` | Asset and binary names belong to the target |
| `LICENSE` copyright "Benjamin (github.com/b0x42)" | MIT attribution; the fork does not get to delete the author |
| `Casks/prizm.rb` | It is upstream's formula, for upstream's releases. Header now says so |
| `openspec/changes/archive/**` | History |

## Consequences someone has to accept

- **The keychain store is orphaned.** `kSecAttrService` is how items are found; changing it means the
  existing session, device id and cached tokens read as absent. The app will ask to sign in again.
  Acceptable only because there is no installed base yet — after a public release this is a migration
  with a user-visible cost.
- **`SSH_AUTH_SOCK` moves.** The socket directory is named for the product, so a shell profile
  pointing at the old path must re-copy the line from Settings ▸ SSH agent.
- **The offline vault cache starts empty.** Its directory moved. It repopulates on the next sync, so
  the cost is one loss of offline read, not data.
- **`dist/Prizm.app` is now stale.** The script builds `dist/Vitrine.app`.
- **The bundle id is `dev.lemonevo.vitrine`.** I chose it from the GitHub handle because I cannot
  verify domain ownership; it is one string in three places if you have your own domain.

## Impact

- Affected specs: `project-documentation` (the repository-name requirement), `homebrew-cask` (the
  product name it specifies is now a different app's), `release-infrastructure`, `biometric-unlock`
  (the prompt line that names the app), plus the specs of every active change that quoted a string.
- Suite: see tasks §5.
