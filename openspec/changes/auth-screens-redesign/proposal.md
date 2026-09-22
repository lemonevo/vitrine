# Auth screens redesign — Proposal

## Why

The two screens every user meets before they meet the vault were the two screens the vault redesign
left untouched. They disagreed about what application they belonged to:

- **Login** drew a stock `lock.shield.fill` in the accent colour. **Unlock** drew the real application
  icon. Same app, one launch apart, two identities.
- **Login** pinned its form to the top of the window with a `Spacer()`, so in any window taller than
  the minimum the bottom half was empty and the form looked unfinished.
- **Unlock had no submit button at all.** Return was the only way in, and `isUnlockDisabled` was
  computed on every keystroke and then shown to nobody — the screen gave no indication that anything
  could be pressed, or that it was waiting for a password.
- The server field's placeholder was `https://vault.example.com`. A `TextField` whose placeholder
  reads as a URL is rendered by AppKit as a *detected link* — blue, underlined — so an empty field
  looked pre-filled with something clickable. Verified by capture, not by reading the docs.
- The "Sign in with a different account" control (FR-039) sat pinned to the bottom edge of the
  window, as far from the form it acts on as the layout could arrange.

## What changes

- **New shared chrome** — `Prizm/Presentation/Components/AuthChrome.swift`: `AuthCard`, `AuthHeader`,
  `AuthField`, `AuthPrimaryButton`, `AuthErrorBanner`. Both screens are built from it, so they cannot
  drift again without someone deleting the file.
- **`LoginView`** is rebuilt inside the card. Email and master password lead; the server field moves
  below a rule at a smaller label, because it is set once and never touched again while the other two
  are typed every time. Its placeholder is gone, replaced by a hint line under the field. A footnote
  under the card states what is actually sent to the server.
- **`UnlockView`** is rebuilt inside the same card and **gains the missing Unlock button**, wired to
  the existing `unlock()` path and disabled by the already-existing `isUnlockDisabled`.
- Both screens now declare a minimum window height that fits their own worst case, because
  `.windowResizability(.contentSize)` makes that number the difference between a form and a clipped
  form.
- Six new keys in `en` and `zh-Hans`.

## What this does not change

- **There is no "Unlock with Touch ID" button**, although the approved mockup drew one.
  `biometric-unlock` forbids it: the sensor is kept always armed, so a button would promise a press
  that does nothing. The inline `LAAuthenticationView` row stays, and the delta below moves it from
  the spec's fiction ("overlaid on the lock screen icon") to what the code has done for a year.
- No authentication logic. `LoginViewModel`, `UnlockViewModel`, the use cases and the crypto paths are
  untouched apart from nothing at all — this change moves no call.
- The vault browser, which was the previous change.

## Found while doing this, fixed separately the same day

**An Xcode build of this app shipped with no localisation files at all.**
`Vitrine.app/Contents/Resources/` contained `Assets.car`, the icon and the wordlist — no `en.lproj`, no
`zh-Hans.lproj`. `project.pbxproj` had zero references to `Localizable.strings` or `lproj`. Chinese
worked only because `build-app.sh` copies the `.lproj` folders into the bundle by hand — and that
script's comment said it is "exactly where Xcode would put them", which was not true.

The sharper symptom, which is what made it worth its own change: the Settings language picker and
"Follow System" both route through `LocalizationManager.applyOverride(for:)`, which asks
`Bundle.main` for the `.lproj`, gets `nil`, and clears the override. So in an Xcode build **choosing
简体中文 did nothing at all**, silently, by design.

Fixed the same day in `openspec/changes/xcode-localisation-resources/`. The Chinese captures below were
rendered while that defect was open, by pointing the test at the checkout's `.lproj` folders — which
proved the strings and the layout, and is now the thing the harness no longer falls back to.
