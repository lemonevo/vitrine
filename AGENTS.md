# Working in this repository

Operational notes for AI agents and for anyone else who has to build, run and verify this project.
This is not user documentation — that is `README.md`; the deep conventions are `CLAUDE.md`.

Read, in this order:

1. `CONSTITUTION.md` — seven non-negotiable principles. Violating one is a blocking review failure.
2. `CLAUDE.md` — design tokens, layer rules, comment standard, and the traps that have already bitten.
3. This file — how to build, verify, and avoid believing a green run that ran nothing.
4. `openspec/` — the change records, and the specs they answer to.

## Vitrine is the product; Prizm is the build

Everything user-visible says **Vitrine**. Everything internal still says `Prizm`, on purpose: the
source directory, `Prizm.xcodeproj`, the scheme, the Swift module, the executable, `PrizmTests`,
`Prizm_V2.icon`, and the `Package.swift` target. `openspec/changes/rename-product-vitrine/` records
which names were moved and why the rest were not; a target-graph rename is a separate, much larger
sweep than a find-and-replace.

Two consequences that look like mistakes and are not:

- A Release build still produces `Prizm.app` and `Prizm-v<version>.dmg`, and `build-app.sh` assembles
  `dist/Vitrine.app` whose executable is named `Prizm`.
- Identity strings are `dev.lemonevo.vitrine` (bundle id, logging subsystem, keychain service), plus
  the legacy `com.prizm.biometric` item that is still read.

## Two build paths, and which one you need

| Command | Output | Notes |
|---|---|---|
| `xcodebuild … test` | DerivedData | Does **not** touch `dist/`. The route for the test suite. |
| `./build-app.sh [release]` | `dist/Vitrine.app` | The route to something you can launch. |

`build-app.sh` exists because `xcodebuild` resolves Swift packages by re-entering `sandbox-exec`,
which fails inside an already-sandboxed process; SwiftPM's own CLI supports `--disable-sandbox`. The
Xcode project stays the source of truth for release builds — keep the two targets in sync when
settings change. The bundle is ad-hoc signed with the sandbox **off** by default (`PRIZM_SANDBOX=1`
restores it), which is also why the SSH agent runs in a locally built app and reports itself
unavailable in an Xcode-built one.

**If the user is looking at the running app, work is not delivered until `./build-app.sh` has run and
the app has been relaunched.** Check the PID changed — a rebuild that silently did not happen looks
exactly like a fix.

## Signing and the keychain

`security find-identity -v -p codesigning` reports **zero** identities on this machine, so every
build is ad-hoc. Ad-hoc signing grants keychain access per *binary*, so a new build may not own the
items an older one wrote, and touching them raises a dialog asking for the **login keychain**
password — not the vault master password. When it appears, `./reset-keychain.sh` clears the stale
items and the app recreates its own (the user then signs in again).

Do not click through that dialog, unlock the vault, or delete keychain items on the user's behalf.

## Verification

```bash
xcodebuild test \
  -project "Prizm/Prizm.xcodeproj" \
  -scheme "Prizm" \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

The signing flags are the ones CI passes; without them a build with no provisioning profile for the
bundle id fails before any test runs. The run is pinned to English by `Prizm/PrizmTests.xctestplan`
(referenced from the shared scheme) — without it, assertions resolve against the Mac's own language.

Traps, all of which have produced a false "verified" on this project:

- **`-only-testing:` with a wrong class name runs zero tests and still prints `** TEST SUCCEEDED **`.**
  Read the executed-test count in the output, not the verdict line.
- `Prizm/UITests` is on disk and is in no target: it does not compile and has never run. That is
  deliberate — `openspec/changes/fix-test-target-buildability/` has the state of play.
- The `PrizmTests` target must keep `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
  `SWIFT_VERSION = 5.0`; changing either stops it compiling.
- Scale the run to the change. The full suite is for cross-cutting work; a one-view change does not
  need it, but it does need the rebuild.

## Changes go through openspec

`openspec/specs/**` states what the software does today. `openspec/changes/<name>/` holds work in
flight, as `proposal.md` / `design.md` / `tasks.md` plus, where behaviour changes,
`specs/<capability>/spec.md` deltas — `## ADDED` / `## MODIFIED` / `## REMOVED Requirements`, each
with `### Requirement:` and `#### Scenario:` bullets. A modified requirement keeps its original
heading, so the delta replaces it instead of leaving two contradictory copies.

Specs merge into `openspec/specs/**` only when a change is archived. Do not edit the merged specs
while a change is in flight, and do not edit `openspec/changes/archive/**` at all — it records what
was true at the time.

## Documents that have drifted

`CLAUDE.md` is authoritative on conventions and on the design system. It is not authoritative on
detail — check the code before repeating a claim from any document, including this one.

- `CLEANUP.md` describes a restructure that has already happened.
- `FEATURE-GAP-ANALYSIS.md` is a dated snapshot in Chinese, and it has a documented history of
  stating official Bitwarden behaviour that no one had checked. Verify against
  `bitwarden/clients` or the live product before acting on it.
- `openspec/specs/project-documentation/spec.md` still names the old repository `b0x42/prizm`.
- `DEVELOPMENT.md` quotes a test count from an earlier revision.
