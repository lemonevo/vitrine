# Tasks — unlock credential layering

## 1. Evidence before the change

- [x] 1.1 Rendered the shipped screens with `AuthScreenScreenshotTests` (real views, real `NSWindow`)
      rather than reasoning about them: `auth-login-empty`, `auth-unlock-pin`, `auth-unlock-biometric`.
- [x] 1.2 Measured the resolved system foregrounds in both appearances (`xcrun swift`, WCAG relative
      luminance against the window and control backgrounds): `secondaryLabel` 3.95:1 light / 5.89:1
      dark; `tertiaryLabel` 1.88:1 / 2.26:1; `systemOrange` 2.31:1 / 7.47:1.
- [x] 1.3 Drew the three credential-layering directions as throwaway views in the test target and
      rendered them at rest, after a wrong PIN, and in dark aqua. The drawings, not the argument,
      settled it: A puts the PIN attempt count under a master-password field, and B's subtitle
      contradicts its own selection while adding a second solid-blue primary control.
      The probes were deleted once the direction was chosen (`UnlockCredentialLayering*.swift`).

## 2. One credential at a time

- [x] 2.1 `Domain/Utilities/UnlockCredentialPreference.swift` — per-launch record of the credential
      that last succeeded. Registered in `project.pbxproj` (the app target's synchronised group covers
      only `Prizm/Prizm`, so a new production file is invisible to the build until it is added).
- [x] 2.2 `UnlockViewModel`: `credentialMethod`, `toggleCredentialMethod()`, `submit()`,
      `credentialFieldLabel`, `switchCredentialTitle`, `unlockInstructionText(biometricName:)`;
      `shouldShowRemainingAttempts` gated on PIN mode; success recorded on the password and PIN paths.
- [x] 2.3 `AppContainer` owns one preference and passes it to every `UnlockViewModel` — the view model
      is rebuilt on each lock, so it cannot hold per-launch state.
- [x] 2.4 `UnlockView`: one field, the switch under it, the count directly under the PIN, subtitle
      following the ask, button live.
- [x] 2.5 `AccessibilityID.Unlock.switchCredential`.

## 3. Live submit, answered rather than prevented

- [x] 3.1 `LoginViewModel`: `LoginField`, `fieldRequiringAttention`, first-missing-field validation on
      `signIn()` (whitespace is not an answer), previous complaint cleared by a valid submission.
- [x] 3.2 `LoginView`: `.disabled(isSignInDisabled)` gone — only in-flight disables it now; focus moves
      to the field the message named; the view's private `Field` enum replaced by `LoginField` so the
      vocabulary cannot drift.
- [x] 3.3 The hardcoded `"Invalid password encoding."` on both entry view models now goes through `L()`
      — a leftover named in `auth-screens-redesign/tasks.md`.

## 4. Legible secondary text

- [x] 4.1 `Foreground.muted` = `Color.primary.opacity(0.62)` (6.20:1 light / 7.13:1 dark) and
      `Foreground.warning` resolving per appearance (`#8C4700` / `#E9A23B`).
- [x] 4.2 Applied to: `AuthField` label and hint, `AuthHeader` subtitle, the login footer sentence, the
      server icon, the sync message, the "sign in with a different account" link, the PIN attempt line.
- [x] 4.3 The attempt line gained a warning glyph and keeps its plain words, so the colour is not the
      only carrier.
- [x] 4.4 **A defect this change introduced and then caught.** The credential switch was first drawn in
      `Color.accentColor` at 10 pt — 4.02:1 light / 4.15:1 dark, failing the very rule this change adds.
      Measured the candidates and added `Foreground.action` = `linkColor` (5.26:1 / 5.89:1), which is
      also the platform's semantic "actionable" colour rather than a hand-picked blue.
- [ ] 4.5 **Not done here, same class of problem:** the sidebar's 10 pt section labels, the 11 pt list
      subtitles and the 9 pt org badge still use `.secondary` / `.tertiary`, and the detail pane's
      `Add Attachment` / `Retry` commands are still `accentColor` at 13 pt. They belong to the list
      redesign, and changing them there is cheaper than changing them twice.

## 5. Tokens

- [x] 5.1 New `Spacing` tokens: `authFieldGap`, `authActionTopGap`, `authDividerVertical`,
      `authProgressHeight`, `authProgressLabelGap`.
- [x] 5.2 Every raw spacing literal on the two entry screens replaced — `LoginView`, `UnlockView`,
      `AuthChrome` are now token-only.
- [x] 5.3 `CLAUDE.md`'s token tables updated, including three tokens (`screenHeading`, `screenBody`,
      `fieldLabelProminent`) the table had stopped listing while the code still used them.

## 6. Verification

- [x] 6.1 Red first: the two `testDefault_*` cases initially failed because they set a PIN without
      switching to PIN mode, so they were exercising the empty-password path — one failed loudly, the
      other **passed for the wrong reason**. Both now assert `lastAttemptedPIN` before drawing any
      conclusion from the wait.
- [x] 6.2 11 new `UnlockViewModelCredentialTests` + 4 login validation tests.
- [x] 6.3 After-screens re-rendered: `auth-unlock-pin-offered` (password asked, switch visible, **no**
      attempt count), `auth-unlock-pin` (PIN asked, count under it), `auth-login-error`,
      `auth-unlock-dark`.
- [x] 6.4 Established that a grey primary button in these captures is the inactive-window look, not the
      disabled state, by rendering both states in one window: enabled is grey with a black label,
      disabled is paler with a grey one. Recorded in `AuthScreenScreenshotTests`' header.
- [ ] 6.5 **Cannot be checked offline** — needs the app run: the accent fill of the enabled button,
      focus ring appearance, the real Touch ID prompt over the switched field, VoiceOver reading order
      for the new switch control, and whether the 560 pt minimum window still fits every combination
      once Chinese copy is in the switch link.
- [ ] 6.6 Reconciliation owed before archiving: `pin-unlock`'s spec describes the PIN as a second
      field and needs its delta reworded; `biometric-unlock:14`'s mandated subtitle wording is
      preserved verbatim in password mode and still holds.

## 7. Suite

- [x] 7.1 Full suite after the change: **1525 passed, 0 failed, 0 skipped** (`** TEST SUCCEEDED **`),
      against a 1508 baseline. Run as one `xcodebuild test` on the shared scheme, language pinned to
      English by `PrizmTests.xctestplan`.
