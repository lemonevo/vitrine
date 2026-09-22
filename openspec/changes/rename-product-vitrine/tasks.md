# Tasks — rename the product to Vitrine

## 1. Name sweep, with the exclusions that mattered

- [x] 1.1 Swift string literals only: 55 lines / 32 files. A blanket replace would have renamed
      `PrizmAPIClient` and `Prizm/Resources` too, so the pass required an explicit keep-list for
      logger categories and paths.
- [x] 1.2 Both localisation tables: 77 occurrences each. Because the key *is* the English sentence,
      this moved keys, not just values — `LocalizationResourcesTests` is the check that catches a
      one-sided move.
- [x] 1.3 Bare brand literals that were not going through `L()` at all (`LoginView`'s header title,
      `SidebarView`'s `.navigationTitle`) now do, and a `"Vitrine"` key was added to both tables.
- [x] 1.4 Docs and non-archive openspec: 246 lines / 72 files. `openspec/changes/archive/**` left
      alone — it records what was true.
- [x] 1.5 README provenance line: forked from Prizm by Benjamin, MIT, substantially rewritten.

## 2. Identity layer

- [x] 2.1 `CFBundleIdentifier` = `dev.lemonevo.vitrine`, set in **both** places it was missing or
      wrong: `build-app.sh`'s generated Info.plist, and — for the first time — the app target's
      `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj`, which had none, so Xcode builds identified
      themselves as `Prizm`.
- [x] 2.2 `CFBundleName` / `CFBundleDisplayName` → Vitrine; `dist/Prizm.app` → `dist/Vitrine.app`.
      `CFBundleExecutable`, the target, the scheme, the module and `Prizm_V2.icon` keep the old name —
      renaming those is a target-graph migration, not this.
- [x] 2.3 Login keychain service `com.prizm` → `dev.lemonevo.vitrine`; logging subsystem at 45 sites.
- [x] 2.4 Version 1.4.3/12 → **0.0.1/1** in all four build configs *and* in `build-app.sh`, which kept
      its own hardcoded copy of both numbers.
- [x] 2.5 `User-Agent` → `Vitrine/2024.12.0`. The version part stays: Vaultwarden gates SSH key
      ciphers on it, so "make it match the app version" would have silently disabled a feature.
- [x] 2.6 `Casks/prizm.rb` annotated as upstream's formula rather than deleted.

## 3. The consequence that was not predicted

- [x] 3.1 **The test suite hung, and it was the rename's fault.** `AccountFingerprintPhraseTests`
      blocked forever inside `open()`. Cause: the word-list fixture read the **source tree** via
      `#filePath`, the repository lives under `~/Desktop`, and Desktop is TCC-protected — so changing
      the bundle identifier made macOS treat the test host as a new application and the read waited on
      a consent decision nobody was present to make. Diagnosed from a `sample` of the hung process,
      not guessed: the leaf frame was `__open`.
- [x] 3.2 Fixed by loading the fixture the way production does — `Bundle.main`
      (`PasswordGenerator.swift:20`). That also makes the test assert against the copy that ships,
      and it removes a source-tree dependency that a stale comment had justified by "`swift test` has
      no resource bundle" — a recipe this project does not support.
- [x] 3.3 Swept for the same trap elsewhere: every remaining `#filePath` in the tests is an assertion
      location parameter, not a file read.
- [x] 3.4 The SSH agent's doc comment still named the old socket directory after the code moved; fixed,
      with the re-export consequence spelled out.

## 4. Costs someone has to pay (accepted, not hidden)

- [ ] 4.1 **Keychain store is orphaned.** `kSecAttrService` changed, so the existing session, device id
      and cached tokens read as absent. The app will ask to sign in again. Fine before a public
      release; after one, this needs a migration.
- [ ] 4.2 `SSH_AUTH_SOCK` path moved → re-copy the line from Settings ▸ SSH agent.
- [ ] 4.3 The offline vault cache starts empty (its directory moved). Repopulates on next sync.
- [ ] 4.4 `dist/Prizm.app` is stale; the script now writes `dist/Vitrine.app`. An instance of the old
      bundle was still running in this session — it needs to be quit before the new one is launched.
- [ ] 4.5 **The GitHub repository itself is still `lemonevo/prizm`** — renaming it is an owner action
      (Settings → General → Repository name), and it will change every URL this change just wrote.
      The local checkout directory is also still `prizm`; left alone deliberately, because another
      session is working in it.

## 5. Verification

- [x] 5.1 Full suite: **1544 passed, 0 failed, 0 skipped** after the rename and the fixture fix.
- [x] 5.2 Two earlier runs are on the record as failures: one with 11 red (the path literal I broke),
      one hung (the TCC block). Neither was waved through as "flaky".
- [ ] 5.3 **Not verified:** that the renamed app launches and behaves on a real run — the About window's
      name, the biometric prompt line ("Open your Vitrine vault with Touch ID"), the new keychain
      prompt after the service change, and the SSH agent socket at its new path. All need the app run.
