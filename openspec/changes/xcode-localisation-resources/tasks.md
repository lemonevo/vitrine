# Xcode localisation resources — Tasks

## 1. Register the strings with the app target

- [x] 1.1 `PBXVariantGroup` `Localizable.strings` with `en` and `zh-Hans` children (D1).
- [x] 1.2 Two `PBXFileReference`s pointing at `en.lproj/…` and `zh-Hans.lproj/…`.
- [x] 1.3 One `PBXBuildFile`, added to the app target's `PBXResourcesBuildPhase`.
- [x] 1.4 The variant group added to the `Resources` group so it is visible in Xcode's navigator.

## 2. Make the test run language-independent

- [x] 2.1 `Prizm/PrizmTests.xctestplan` — `language: en`, `region: US`, one target (D6).
- [x] 2.2 Registered as a `PBXFileReference` in the main group; referenced from
      `xcshareddata/xcschemes/Prizm.xcscheme` under `<TestPlans>`, so ⌘U and CI both pick it up.

## 3. Guard it

- [x] 3.1 `LocalizationResourcesTests.test_everyRegionIsPresentInTheBuiltBundle` — each declared region
        resolves inside the built bundle.
- [x] 3.2 `…test_everyEnglishKeyHasATranslation` — key sets match, both directions reported.
- [x] 3.3 `…test_englishValuesAreTheKeysThemselves` — the English table's values are its keys (D5).
- [x] 3.4 `AuthScreenScreenshotTests.useLanguage` — checkout fallback removed; resolves from
        `Bundle.main` only.
- [x] 3.5 Copied `.strings` are UTF-16 with a BOM; the reader picks the encoding from the BOM so the
        same test works against the bundle and the checkout (D4).

## 4. Fix what the fix exposed

- [x] 4.1 Nine `en.lproj` entries whose values were Chinese (`"Set a PIN" = "设置 PIN";` and eight more
        in the same block) restored to their keys.
- [x] 4.2 `build-app.sh`'s comment: it claimed its copy step is where Xcode would put the files. It was
        not; the step is now documented as a deliberate duplicate.

## 5. Verification

- [x] 5.1 `xcodebuild clean && build` → `Contents/Resources/en.lproj` and `zh-Hans.lproj` exist, with
        the new keys inside.
- [x] 5.2 **Mutation:** delete the Resources-phase entry, clean-build, run the guards → 2 failed.
- [x] 5.3 **Mutation:** paste one Chinese value back into `en.lproj` → exactly 1 failed, the values test.
- [x] 5.4 **Mutation:** set the plan's language to `zh-Hans` → the 6 `AccessibilityTier2Tests` string
        assertions fail again, proving the plan is what pins the run.
- [x] 5.5 Full suite: **1490 passed, 0 failed, 0 skipped**. The last recorded baseline was 1472; the
      difference is the auth-screen captures plus these three guards — the count is reported, not
      reconciled line by line.
- [x] 5.6 Docs: `DEVELOPMENT.md` test count and the new plan note; `CLAUDE.md` interface-strings
        section.

## 6. Not verified — stated rather than hidden

- 6.1 **No archive was built.** The observation is a `xcodebuild build` product and the test host
      bundle. An archive runs the same resource pipeline, but that is an inference; run the release
      workflow once before shipping.
- 6.2 **The Settings language picker was never clicked.** Its failure path is read from
      `LocalizationManager.applyOverride(for:)`, and the fix is verified at artifact level. Choosing
      简体中文 in a rebuilt app and watching the UI change is still a manual step.
- 6.3 **`CFBundleLocalizations` is still absent** from the app's `Info.plist`. The copy happens without
      it. Whether App Store metadata wants the key explicitly is out of scope and untested.
- 6.4 **`Locale.preferredLanguages` is untouched by the plan's `region`/`language` for anything that
      reads it directly**, so `AppLanguage.systemPreferredCode` in a test still sees the host. Nothing
      asserts on it today; a future test that does must supply its own input.
