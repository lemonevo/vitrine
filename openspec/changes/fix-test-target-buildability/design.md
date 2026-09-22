# Test target buildability — Design

## Context

The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Under Swift 6 that setting changes
more than concurrency checking: it makes every type in the module implicitly `@MainActor` unless
annotated otherwise. An implicitly-isolated initialiser is part of the type's **interface**, so a
different module — including the test target — sees it as main-actor-isolated and may only call it
from a main-actor context.

`PrizmTests` has no such setting, so its own declarations default to `nonisolated`. Its test classes
are `XCTestCase` subclasses, whose initialisers are nonisolated by framework contract. The result is
two modules that cannot meet.

The four configurations measured in `b39c5c5`, each on a pristine worktree:

| configuration | result |
| --- | --- |
| v6 | 576 errors / 9 files |
| v6 + upcoming-feature flags | 22 errors / 3 files |
| v6 + `-default-isolation MainActor` | 4969 errors (every `XCTestCase` subclass) |
| v5 | 3 errors / 4 files |
| v5 + `-default-isolation MainActor` | compiles |
| v5 + `-default-isolation MainActor` + flags | compiles |

The committed configuration today is none of these: it is v6 **without** the isolation setting,
which is the configuration that produces the 33 errors this change removes. CI runs the same command
and cannot be green.

## Decision 1 — match the app target's isolation, keep the test target at v5

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on `PrizmTests`, and `SWIFT_VERSION = 5.0`.

Both halves are required and neither is a preference:

- Without the isolation setting, the app module's implicitly-isolated initialisers are unreachable
  from the tests. There is no way to fix this from the test side: annotating every test class
  `@MainActor` does not help, because `XCTestCase`'s own nonisolated initialiser then rejects the
  subclass.
- With the isolation setting under v6, that rejection becomes a hard error for every subclass — 4969
  of them. v5 downgrades it to a warning.

**The cost, stated plainly:** the test target compiles under looser concurrency rules than the code
it tests. A test can therefore do something the app's own build would reject. That is a real gap, and
it is the price of `XCTest`'s design, not a choice this project would otherwise make. It is recorded
here so the next person does not "fix" the version mismatch and lose the suite again.

## Decision 2 — record the baseline before trusting it

The failing set after this change is measured and written into `tasks.md`, with each failure triaged
into one of three categories:

- **environment** — e.g. Keychain access from a test host without an entitlement. `b39c5c5` records
  14 such failures that it attributes to a broken configuration rather than the sandbox; that claim
  is re-checked here rather than inherited.
- **product defect** — the test is right and the code is wrong.
- **test defect** — the test asserts something the product does not promise.

The point is not the number. It is that "which tests fail, and why" stops being folklore. A suite
with unexplained failures is read as noise, and noise is how a real regression gets ignored — which
is the same failure mode as having no suite at all.

## Decision 3 — do not touch `UITests` here

The 13 files under `Prizm/UITests/` are referenced by no target and have therefore never executed.
They are not part of this change because wiring them up is not a configuration fix: a UI test target
needs a signed `TEST_HOST`, a launchable app bundle and a UI session, none of which CI has today
(CI builds with signing disabled). Deleting them is also a decision — it removes an intent someone
recorded. Both options are out of scope; the finding is carried into the change's notes so it is not
lost.

## Verification

```
xcodebuild test -project "Prizm/Prizm.xcodeproj" -scheme "Vitrine" -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Must reach `Executed N tests` rather than failing in the compile phase, and `N` must exceed the
number of test files that currently compile (zero). The failing set is then compared against the
list recorded in `tasks.md`, and any difference is explained before the change is archived.
