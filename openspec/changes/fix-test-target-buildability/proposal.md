## Why

`xcodebuild test` — the command CI runs, and the only one the committed project settings support —
fails before a single test executes. The test target does not compile: **33 errors across 7 files**,
all the same shape:

```
PrizmTests/Domain/DraftVaultItemTests.swift:46:29: error: call to main actor-isolated
initializer 'init(_:)' in a synchronous nonisolated context
```

Root cause: the two targets disagree about default actor isolation.

| target | `SWIFT_DEFAULT_ACTOR_ISOLATION` | `SWIFT_VERSION` |
|---|---|---|
| `Prizm` | `MainActor` | 6.0 |
| `PrizmTests` | *(absent — defaults to nonisolated)* | 6.0 |

Every `VaultItem`, `DraftVaultItem` and `CustomField` in the app module is therefore implicitly
`@MainActor`, while the test methods that construct them synchronously are nonisolated.

This was diagnosed already. `b39c5c5` (2026-09-20) recorded the recipe in
`openspec/changes/phase-2-data-sovereignty/tasks.md`: the test target needs `-default-isolation
MainActor`, and the language mode must stay **v5** — under v6, `XCTestCase`'s nonisolated
initialiser conflicts with every MainActor-isolated subclass, producing 4969 errors. The recipe was
measured through a temporary `Package.swift` target and then reverted, on the reasoning that "the
Xcode project remains the source of truth". The change never reached the project, so the suite has
not compiled since.

Consequence: **125 unit-test files protect nothing.** Constitution §IV makes TDD non-negotiable and
`CLAUDE.md` repeats it, but no test can be run, so no failing test can precede any fix. Every change
made until this is fixed is unverifiable by construction.

The same note records a pre-existing baseline of **10 failing tests** (`842/10` climbing to
`953/10`). Those are not introduced here and are not fixed here — they are the first thing this
change measures.

## What Changes

- `PrizmTests` gains `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in both configurations, matching
  the app target.
- `PrizmTests` moves from `SWIFT_VERSION = 6.0` to `5.0`. The mismatch with the app target's 6.0 is
  deliberate and load-bearing; the design records why.
- The suite is run and its **actual** failing set is recorded in `tasks.md`, so the next change has a
  baseline to compare against rather than an assumption.
- Each pre-existing failure is triaged: environment (Keychain access under a test host), product
  defect, or test defect — with the verdict written down. An unexplained failure is worse than none,
  because it trains the reader to ignore red.

## Non-goals

- **Fixing the failing tests.** This change makes them run; it does not make them pass. Fixing a test
  is a product change and belongs in its own change, on its own evidence.
- **Adopting Swift 6 language mode in the test target.** It cannot be done while `XCTestCase`
  subclasses are `@MainActor`; the constraint is the framework, not the project.
- **The 13 XCUITest files in `Prizm/UITests/`.** They belong to no target at all, so they have never
  run. Wiring them up (or deleting them) is a separate decision with its own cost — a UI test target
  needs a signed app and a UI session.

## Capabilities

### New Capabilities

- `test-suite-buildability`: the committed project configuration compiles and runs its unit-test
  suite, and the set of failures it reports is known and recorded.

### Modified Capabilities

_None._

## Impact

- `Prizm/Prizm.xcodeproj/project.pbxproj` — two build settings on the `PrizmTests` target, both
  configurations
- `openspec/changes/phase-2-data-sovereignty/tasks.md` — the recorded recipe is superseded; it points
  at this change instead of describing a manual workaround
- `DEVELOPMENT.md` — the test command becomes runnable as written
