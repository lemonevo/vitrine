# Xcode localisation resources — Proposal

## Why

**An `xcodebuild` build of Prizm contained no translation files at all.**
`Prizm.app/Contents/Resources/` had `Assets.car`, `Prizm_V2.icns` and the wordlist — no `en.lproj`, no
`zh-Hans.lproj`. `project.pbxproj` had zero references to `Localizable.strings`, to `lproj`, or to any
`PBXVariantGroup`.

The consequence is not "a Chinese user sees English", which is what makes it easy to shrug at. It is
sharper than that:

- **The Settings language picker did nothing.** Choosing 简体中文 calls
  `LocalizationManager.applyOverride(for:)`, which asks `Bundle.main` for `zh-Hans.lproj`, gets `nil`,
  and — by the "a missing `.lproj` falls back rather than failing loudly" rule written into that
  function — clears the override. Every string then resolves against a bundle whose only localisation
  is English.
- **"Follow System" did nothing on a Chinese Mac**, by the same path.
- `AppLanguage.match(_:)` deliberately sends `zh-Hant` readers to Simplified Chinese "because a Chinese
  reader gets far more from Simplified Chinese than from untranslated English". In an Xcode build that
  care was wasted: they got untranslated English either way.

Nothing logged. Nothing failed. The one build path where Chinese *did* work is `./build-app.sh`, which
copies the `.lproj` folders by hand — and whose comment claimed that was "exactly where Xcode would put
them". It was not.

## Root cause

The app target's `fileSystemSynchronizedGroups` covers `Prizm/Prizm` — the folder holding
`Assets.xcassets`, `Info.plist`, the entitlements and the `.icon` bundles. The strings live in
`Prizm/Resources/`, which is a **different** folder, registered as an ordinary `PBXGroup` whose only
child is `eff-large-wordlist.txt`. So `Resources/*.lproj` was in no build phase at all, and the
synchronised group never saw it. This is the same trap that produced `2870a47` ("register the 81
sources the Xcode project never knew about"), one layer over.

## What changes

- **`Localizable.strings` becomes a `PBXVariantGroup`** with `en` and `zh-Hans` file references, placed
  in the `Resources` group and added to the app target's Resources build phase. Xcode then emits
  `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings` (as UTF-16 with a BOM) into
  the bundle.
- **`PrizmTests.xctestplan`** pins the test run to English (`language: en`, `region: US`) and is
  referenced from the shared scheme, so ⌘U and CI get the same determinism. Once the bundle carries
  translations, the test host resolves strings against the Mac's own language — on a Chinese machine
  **18 assertions in 6 classes flipped from green to red without any code changing**. A suite whose
  results depend on System Settings is not testing the code.
- **`LocalizationResourcesTests`** (3 tests) asserts against the *built* bundle that every declared
  region is present, that the two tables' key sets match, and that the English table's values are the
  keys themselves.
- **Nine PIN strings in `en.lproj` had Chinese values.** `"Set a PIN" = "设置 PIN";` and eight more,
  one contiguous block. They were unreachable while the table was not in the bundle at all — every
  lookup returned the key — and became nine lines of Chinese in an English interface the moment the fix
  landed. Corrected to match their keys; that is what the third test now guards.
- **`AuthScreenScreenshotTests.useLanguage`** now resolves only from `Bundle.main`. It used to fall
  back to `Prizm/Resources` in the checkout, which is how the defect stayed hidden: the Chinese capture
  succeeded, and proved nothing about the artifact.
- **`build-app.sh`**'s comment corrected. Its copy step stays — SwiftPM has no `.lproj` concept — but it
  is now a deliberate duplicate, not a substitute for a missing registration.

## Evidence

| Check | Before | After |
|---|---|---|
| `Contents/Resources/` | `Assets.car`, icns, wordlist | + `en.lproj/`, `zh-Hans.lproj/` |
| `grep lproj project.pbxproj` | 0 matches | variant group, 2 file refs, 1 build file, 1 phase entry |
| `LocalizationResourcesTests` | — (did not exist) | 3 passed |
| …with the Resources-phase entry deleted, rebuilt clean | — | **2 failed** |
| …with one Chinese value pasted back into `en.lproj` | — | **1 failed**, exactly the values test |
| `AccessibilityTier2Tests` on this (Chinese) Mac | 6 failed after the strings landed | 13 passed |
| Same class with the plan's language flipped to `zh-Hans` | — | **6 failed** — the plan is what pins it |
| Full suite | 1472 passed / 0 failed | **1490 passed / 0 failed / 0 skipped** |

## What this does not change

No string content, no `L()` call sites, no `AppLanguage` logic, no `LocalizedBundle` mechanism. The
fallback-to-English on a missing `.lproj` is kept: it is the right behaviour for an intentionally
untranslated build, and it is now covered by a test instead of by hope.
