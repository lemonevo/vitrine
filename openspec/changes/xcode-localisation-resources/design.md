# Xcode localisation resources — Design

## D1 — A variant group, not another synchronised folder

Two candidate fixes: move `Prizm/Resources/` inside the synchronised `Prizm/Prizm` folder, or register
the strings explicitly as a `PBXVariantGroup`.

The first is the smaller diff on disk and the larger one in risk: it relocates a directory the
SwiftPM build, `build-app.sh`, `CLAUDE.md` and the screenshot harness all name, and it leaves the
question "does a synchronised group even treat `.lproj` as localisation?" open. The second is what
Xcode's own UI produces for a localised file, is readable in a diff, and states the intent — this file
has per-region variants — in the format's own vocabulary.

## D2 — The test reads the built bundle, not the checkout

`LocalizationResourcesTests` resolves through `Bundle.main.path(forResource:ofType:"lproj")` in a
`TEST_HOST`-ed bundle. Reading `Prizm/Resources/…` from the source tree would pass on a checkout that
builds an untranslated app, which is precisely the situation that went unnoticed.

The same rule is what caught the bug for real: `AuthScreenScreenshotTests.useLanguage` had a checkout
fallback added so a Chinese capture could be produced at all, and removing it is what turned the
capture into evidence.

## D3 — Key parity is checked one direction, reported both

English is the source of truth: every `L("…")` call site writes its key as an English sentence, so a
key missing from `zh-Hans` renders English text, and a key missing from `en` is a key no call site
uses. The assertion is stated as "every English key has a translation"; the reverse set is reported
too, because a stray Chinese-only entry is the same mistake made in the other direction and silence
about it would make the test look like it only checks half the problem.

`XCTAssertFalse(english.isEmpty)` is not filler. A `.strings` file decoded with the wrong encoding
parses to zero keys, and zero keys against zero keys is a passing parity test. That is how this file's
first version failed — see D4.

## D4 — Copied `.strings` are UTF-16, source files are UTF-8

Xcode rewrites `.strings` it copies into a bundle: UTF-16 with a `FF FE` BOM, plus a header comment.
`String(contentsOf:encoding:.utf8)` returns a throwing decode error on that, and had it been
`String(contentsOf:)`-with-a-default it would have produced garbage instead. The reader picks the
encoding from the BOM, so the same test passes against the bundle and against a checkout.

## D5 — `build-app.sh` keeps its copy step

SwiftPM knows nothing about `.lproj`, so the hand-assembled bundle needs the copy regardless. What
changed is the reason recorded in the comment: it was justified by "this is where Xcode would put
them", which was false, and a future reader trusting that sentence would be misled in exactly the way
that let the defect live.

## D6 — The language is pinned by a test plan, not by code in the test target

The suite needs one language, decided before the first assertion. Four ways to get there:

- **A `+load` hook in the test target.** Not available: Swift refuses to define `+load`
  (`method 'load()' defines Objective-C class method 'load', which is not permitted by Swift`) — tried,
  compiler rejected, file deleted.
- **A base `XCTestCase` every class inherits.** 150 classes to touch, and a new class that forgets the
  base silently tests the host language again.
- **`-AppleLanguages (en)` in the scheme's launch arguments.** Applies to the test *and* ordinary runs
  of the app, so the developer's own Vitrine would stop following the system.
- **A test plan with `language: en`, referenced from the shared scheme.** One file, applies to ⌘U and to
  `xcodebuild test -scheme` alike, and is the mechanism Apple built for this. Chosen.

Verified rather than assumed: with the plan's language flipped to `zh-Hans`, the six
`AccessibilityTier2Tests` string assertions fail again. If the plan were being ignored, that flip would
have changed nothing.

## D7 — Not verified

- **No archive was built.** The claim covers a plain `xcodebuild build` and the test host bundle. An
  archive goes through the same resource pipeline, but "same pipeline" is an inference, not an
  observation; the release workflow should be run once before it ships.
- **The runtime picker was not clicked.** The failure path is read from
  `LocalizationManager.applyOverride(for:)` and `AppLanguage`, and the fix is verified at the artifact
  level. Actually setting 简体中文 in a rebuilt app and watching the UI change is still a manual step.
- **`CFBundleLocalizations` is still absent** from the app's `Info.plist`. The copy happens without it,
  and `Bundle.main.localizations` now reports both regions from the folder list. Whether App Store
  metadata needs the key explicitly is out of scope here and untested.
