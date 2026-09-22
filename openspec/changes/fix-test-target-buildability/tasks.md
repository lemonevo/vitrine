# Test target buildability — Tasks

## 1. Configuration

- [x] 1.1 `PrizmTests` Debug configuration gains `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
      (`Prizm/Prizm.xcodeproj/project.pbxproj`, config `4309FD132F68121F0031C9F4`).
- [x] 1.2 `PrizmTests` Release configuration gains the same setting (config
      `4309FD142F68121F0031C9F4`).
- [x] 1.3 `PrizmTests` `SWIFT_VERSION` becomes `5.0` in both configurations. `Vitrine` stays at `6.0`.
- [x] 1.4 Confirmed no other `PrizmTests` setting diverges from `Vitrine` in a way that matters. The
      full comparison, read from `project.pbxproj`:

      | setting | `Vitrine` | `PrizmTests` | note |
      | --- | --- | --- | --- |
      | `SWIFT_VERSION` | 6.0 | **5.0** | the intended divergence — Design Decision 1 |
      | `SWIFT_DEFAULT_ACTOR_ISOLATION` | MainActor | MainActor | now matched |
      | `SWIFT_APPROACHABLE_CONCURRENCY` | YES | YES | already matched |
      | `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` | YES | YES | already matched |
      | `SWIFT_EMIT_LOC_STRINGS` | YES | NO | irrelevant: the test target has no string catalog |
      | `SWIFT_STRICT_CONCURRENCY` | unset | unset | neither target sets it; both take the default |

      So `SWIFT_VERSION` is the only divergence that can change what compiles, and it is deliberate.
      Anything else appearing here later is a new divergence and should be read, not assumed.

## 2. Build

- [x] 2.1 The test run reaches the test phase with no compile errors. Verified with the command in
      the Verification section of `design.md`:
      - `rg -c "error:" /tmp/prizm-test2.log` → **0**
      - the log ends with **`** TEST SUCCEEDED **`**
      - **1210 tests passed, 0 failed, 0 skipped**, across **121 test classes** in **125 test
        files**. Every file under `Prizm/PrizmTests/` appears in the log, so nothing was silently
        excluded from the target.
      - Note on the check itself: task 2.1 originally said to assert the log contains `Executed`.
        That string is emitted by **`xcpretty`**, which CI pipes through and a local run does not.
        Without it the markers are `** TEST SUCCEEDED **` and one `Test case '…' passed on` line per
        case. Check for those two, not for `Executed`.
- [x] 2.2 The app target still builds, and this change did not touch it. `Vitrine` config `434D9EC3`/
      `434D9EC7` are unmodified (`SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
      as before); `git diff` on `project.pbxproj` is confined to the two `PrizmTests` configs.

## 3. Baseline

- [x] 3.1 The failing set is **empty** — see "Recorded baseline" below.
- [x] 3.2 Nothing to triage: there are no failures, so no environment / product-defect / test-defect
      verdicts are owed.
- [x] 3.3 The `b39c5c5` claim is re-checked and it **holds, more strongly than it claimed**. It
      attributed the Keychain failures to a broken configuration rather than the sandbox. Under the
      Xcode test host, all **28** Keychain test cases run and pass — including
      `KeychainServiceTests.testProbedInitCanWriteRegardlessOfEntitlement`,
      `KeychainServiceTests.testAllKeysShareExactlyOneItem` and all ten
      `BiometricKeychainServiceTests`. The sandbox was never the obstacle; the SwiftPM workaround
      was.
- [x] 3.4 Recorded below, with the date and the exact command.

## 4. Record the recipe

- [x] 4.1 `openspec/changes/phase-2-data-sovereignty/tasks.md` — the `Package.swift` note now points
      at this change and states that the workaround is no longer needed.
- [x] 4.2 `DEVELOPMENT.md` — the documented command was already runnable as written; the note added
      there records the baseline, so "all tests must pass" is now checkable rather than aspirational.

## Recorded baseline

**Captured 2026-09-21.**

```
xcodebuild test -project "Prizm/Prizm.xcodeproj" -scheme "Vitrine" -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

**Result: 1210 tests, 0 failures, 0 skipped. `** TEST SUCCEEDED **`.**

There is no failing set. The table this section was written to hold has no rows to hold, and the
remainder of this section explains why that is a finding rather than an absence.

### The 9–10 failures recorded in `phase-2-data-sovereignty` were an artefact of the workaround

`openspec/changes/phase-2-data-sovereignty/tasks.md` records the suite as "**842 tests / 10 failure
records**", and earlier phases as 551 / 10, 718 / 10. Those numbers were measured through a temporary
`Package.swift` test target, because that was the only way to run the suite at the time. Under
`swift test`, `Bundle.main` is the xctest runner, so `Assets.car` and the EFF wordlist are absent —
and the note names that as the cause: "seven `PasswordGeneratorTests` and one
`PasswordGeneratorViewModelTests`, all of which need `Assets.car` or the EFF wordlist, neither of
which exists when `Bundle.main` is the xctest runner", plus one `CardBackground`.

Under the Xcode project the test bundle is hosted by the app (`TEST_HOST = …/Vitrine.app/…/Prizm`), so
`Bundle.main` **is** the app bundle, the resources are present, and those same tests pass. Verified
directly: 36 `PasswordGenerator*` cases ran and passed, and `CardBackgroundTests` ran and passed.

So the failures were never a defect in the product or in the tests. They were a measurement of the
measuring tool. This is the same class of error the phase-2 note itself documents and warns about —
it records that an earlier version of that note claimed `-swift-version 5` alone compiles, and that
the claim was wrong because plain `swift build` never compiles the test target. The lesson is
identical: **the suite's result is only meaningful when run the way the product is built.** The
Xcode project is the source of truth, and now that the target compiles, that is how the baseline is
taken.

`b39c5c5` reached the same conclusion from the other direction, and its Keychain attribution is
confirmed above.

### The cost of Decision 1, measured

Running the test target at `SWIFT_VERSION = 5.0` downgrades the `XCTestCase`-isolation conflict from
an error to a warning. The cost is not hypothetical and it is small enough to state exactly: **6
warnings at 2 sites**, all in `PrizmTests`.

| site | warning |
| --- | --- |
| `PrizmTests/Domain/ImportVaultUseCaseTests.swift:55:17` | call to main actor-isolated instance method `append` in a synchronous nonisolated context — ×2 |
| `PrizmTests/Presentation/AttachmentBatchViewModelTests.swift:27:77` | main actor-isolated static property `stubAttachment` can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode — ×4 |

These six are the entire visible consequence of the version mismatch. They are recorded rather than
fixed because fixing them means moving the test target to v6, which is the 4969-error configuration.
When someone eventually does that work, these two files are the starting point.

The remaining warnings (22 of 28) are unrelated lint: unnecessary `try`, `var` that should be `let`,
an unused `pending` value, deprecated `SecTrustGetCertificateAtIndex` / `init(cString:)`.
