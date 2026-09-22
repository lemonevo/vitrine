# Test suite buildability

The unit-test suite compiles and runs under the settings committed to the Xcode project, so that a
failing test can precede a fix.

This capability is about the *build configuration*, not about any behaviour of the app. It exists
because a suite that does not compile is indistinguishable from a suite that passes, except that one
of them is honest about it.

## ADDED Requirements

### Requirement: The committed project configuration SHALL build the test target

`xcodebuild test` with signing disabled SHALL compile `PrizmTests` and reach the test-execution
phase. Compilation of the test target SHALL NOT fail on actor-isolation diagnostics arising from the
app target's `SWIFT_DEFAULT_ACTOR_ISOLATION` setting.

#### Scenario: The suite compiles and runs

- **GIVEN** a clean checkout with the committed `project.pbxproj` and no local signing identity
- **WHEN** `xcodebuild test` is run for the `Prizm` scheme on a macOS destination
- **THEN** the test target SHALL compile
- **AND** the run SHALL report an executed test count greater than zero

#### Scenario: The isolation setting matches the app target

- **GIVEN** the `Prizm` target declares `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **WHEN** a test constructs a type declared in the app module without an explicit isolation
  annotation
- **THEN** the construction SHALL compile

### Requirement: The set of failing tests SHALL be known and recorded

The project SHALL record which tests fail, and for each one the reason it fails. A failure SHALL be
classified as environment, product defect, or test defect, with evidence for the classification.

#### Scenario: A pre-existing failure is documented rather than tolerated

- **GIVEN** the suite reports N failing tests
- **WHEN** the change is archived
- **THEN** each of the N failures SHALL appear in the change's task file with a classification
- **AND** any failure without a classification SHALL block archiving

#### Scenario: Failure count alone is not accepted as evidence

- **GIVEN** a suite reporting the same failure count as a previous baseline
- **WHEN** the failing *set* differs from the baseline — a different test now failing
- **THEN** the difference SHALL be explained before the change is archived

### Requirement: The language-mode mismatch SHALL be documented

The test target compiles under a different Swift language mode from the app target. This SHALL be
recorded, with the reason, wherever the build configuration is described.

#### Scenario: A reader does not "fix" the mismatch

- **GIVEN** a reader notices `SWIFT_VERSION = 5.0` on `PrizmTests` next to `6.0` on `Prizm`
- **WHEN** they look for the reason
- **THEN** the design document SHALL state that v6 with main-actor default isolation produces
  4969 errors from `XCTestCase` subclassing
- **AND** SHALL state that the mismatch is deliberate
