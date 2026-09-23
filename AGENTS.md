# Working in this repository

Operational notes for AI agents and for anyone else who has to build, run and verify this project.
This is not user documentation — that is `README.md`.

Read, in this order:

1. `README.md` — what the application is, and what it claims to a user.
2. `openspec/specs/**` — what it does, requirement by requirement. `openspec/changes/<name>/` holds
   the work in flight.
3. This file — how to build, verify, and avoid believing a green run that ran nothing.

## Conventions that still bind

The manual that used to hold these was removed on 2026-09-23; the full text is in git
(`git show 0014016:CLAUDE.md`). What survives here are the rules that cost the most when broken:

- **Three layers, one direction.** `Domain/` imports Foundation only; `Data/` is the only layer that
  imports crypto, all of it behind `BitwardenCryptoService`; `Presentation/` imports SwiftUI and never
  `Data/`.
- **Typography and spacing come from `Prizm/Presentation/DesignSystem.swift`.** No raw font or spacing
  literals in a view; a new role gets a token with a comment.
- **Alpha derived from `Color.primary` or a semantic colour comes from `ContrastAwareOpacity.swift`**,
  keyed on `colorSchemeContrast`, never written as a literal at a call site — that is what makes
  Increase Contrast change anything. `.secondary` and `.tertiary` are not safe for copy a user has to
  act on.
- **Every user-facing string is `L("key")`, and the key is added to both `en.lproj` and
  `zh-Hans.lproj`.** A missing key renders as the key itself, so Chinese silently reads as English.
- **A view that shows a published value must observe the model that publishes it.** `let model: X`
  where `X: ObservableObject` installs no subscription: the view draws once and freezes while every
  unit test stays green.
- **Item commands go in the item's header, not the window toolbar** — `NavigationSplitView` lays each
  column's toolbar items out in column order, so they change the window's shape with the selection.

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

Check the code before repeating a claim from any document, including this one.

- `openspec/specs/**` still names documents that were removed on 2026-09-23 — `SECURITY.md`,
  `DEVELOPMENT.md`, `ACCESSIBILITY.md`, `CODE_OF_CONDUCT.md`, `CONSTITUTION.md`, `CLAUDE.md`. The
  deltas under `openspec/changes/bilingual-readme/specs/` correct them when that change is archived.
- `openspec/specs/release-infrastructure/spec.md` requires a signed, notarised and stapled DMG, and
  names `DEVELOPMENT.md` in a signing error message. `.github/workflows/release.yml` builds **unsigned**
  and stops at a draft. That requirement has been false for longer than this change has existed.
- Comment references to the removed documents survive in 19 Swift files under `Prizm/`.
- `openspec/specs/project-documentation/spec.md` still names the old repository `b0x42/prizm`.
- `openspec/changes/**` records from before that date cite them too. Those are history, like the
  archive — leave them.
