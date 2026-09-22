# Auth screens redesign — Design

## D1 — One chrome file, not two copies of the same card

`AuthCard`, `AuthHeader`, `AuthField`, `AuthPrimaryButton`, `AuthErrorBanner` live in
`Presentation/Components/AuthChrome.swift`.

The alternative was to style each screen in place, which is how they got out of step: login drew an
SF Symbol, unlock drew `NSApp.applicationIconImage`, and nothing failed when the two diverged. A
shared file makes divergence a deliberate edit rather than an accident of parallel work.

`AuthCard` is content-sized and callers centre it. It first filled the window (`.frame(maxHeight:
.infinity)`), which centred the form beautifully and threw the caption under it to the bottom edge of
the screen, 200 pt away from the card it belongs to.

## D2 — The Touch ID affordance stays a row, and the spec says so now

`openspec/specs/biometric-unlock/spec.md:13` requires the fingerprint badge to be "overlaid on the
lock screen icon". The code has not done that since the inline-authentication work: `LAAuthenticationView`
has an intrinsic size that SwiftUI's `.frame` does not constrain, so a 32 pt overlay produced a
fingerprint poking out past the shield. It became its own row.

The mockup the user approved drew an "Unlock with Touch ID" **button** in that slot. That is what the
archived change `2026-04-14-touch-id-inline` removed, and its reasoning still holds: evaluation is
kept always armed, so a button implies a press that changes nothing. The row is kept, the button is
not built, and the delta restates the badge's position as the row it is.

## D3 — The Unlock button is a gap, not a preference

`isUnlockDisabled` already existed and already gated `unlockIfReady()`. It gated it *silently*: a user
who typed a password and saw nothing happen had no way to know the screen was waiting for Return.

`:22` of the same spec reads "only the master password field SHALL be available". Read as a layout
rule that would forbid the submit control, which is not what it is for — it is contrasting the
password path with the *biometric* path in the scenario where biometrics are off. The delta narrows
the sentence to what it means and adds a requirement that the password path has a visible submit
affordance, so the next reader does not have to guess which of the two the button is.

## D4 — Field order on login: what is typed every day goes first

Server URL was the top field with the same visual weight as the password. It is entered once per
account and then never again; email and password are entered every time. The server field is now
below a rule, with a smaller label and a hint line instead of a placeholder.

It remains a live `TextField`, not the read-only row with an "Edit" affordance the mockup showed.
That mockup detail would add a display/edit mode — a second state, a second path through FR-001, and
a new way to be mid-edit when an error arrives — to save nothing at all over a field that is already
visually quiet. The proposal was approved as a layout, and this is the one part of it that was a
layout *and* a behaviour change.

## D5 — The placeholder is gone because AppKit linkifies it

`testPlaceholderLinkProbe` rendered a `TextField` with the placeholder
`https://vault.example.com` and the capture showed it blue and underlined. The same trap catches
`Text("https://…")` written as a literal, because SwiftUI parses Markdown in `LocalizedStringKey`.
Anything that can look like a URL reaches these views as a `String` variable.

## D6 — Minimum window sizes are measured, not chosen

`.windowResizability(.contentSize)` (PrizmApp.swift:193) makes each screen's `.frame(minHeight:)` the
smallest window the app can be shrunk to. With the card centred rather than top-pinned, a window
shorter than the card clips **both** ends.

Login: 520 pt. Unlock: 560 pt — enough for the worst case (sensor row + PIN field + error banner at
once), captured as `auth-unlock-min`. Both were set by rendering at the declared minimum and looking,
not by arithmetic.

## D7 — The footnote on login is a claim, so it was checked first

"Your master password is never sent to the server — only a hash derived from it."

`AuthRepositoryImpl` computes a server hash with `makeServerHash(...)`, and
`PrizmAPIClient.identityToken` sends that value in the form field named `password`. The raw master
password is not on the wire. A sentence this pointed on a screen every user reads before they trust
the app with anything should not be a guess, and the field name being `password` is exactly the kind
of detail that makes a wrong version of this claim plausible.

## D8 — The card's edge is stronger than a vault hairline

In dark aqua the card fill (`controlBackgroundColor`) sits only a few levels off the window
background and the drop shadow is invisible, so the border is the only thing marking the panel.
`Opacity.authCardBorder` is 0.20 / 0.40 where the row dividers use 0.12 / 0.22.

## D9 — What was not verified

- **The Touch ID row renders empty in every capture here.** `LAAuthenticationView` draws nothing in a
  window that is not key in a test host, so the ~60 pt gap visible under the Unlock button in
  `auth-unlock-biometric` is the sensor's reserved space, not its appearance. What it actually looks
  like can only be confirmed on the real lock screen.
- **The Chinese captures read the checkout's `.lproj` folders, not the app bundle** — see "Found
  while doing this" in the proposal: an Xcode build carried no localisation files at all. Fixed the
  same day in `openspec/changes/xcode-localisation-resources/`, after which `useLanguage` resolves from
  `Bundle.main` only and these captures were re-run.
- **Focus rings are absent from every capture.** The harness window is never key, so
  `.onAppear { focusedField = .email }` cannot be seen working.
