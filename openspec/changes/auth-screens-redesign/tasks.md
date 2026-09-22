# Auth screens redesign — Tasks

## 1. Shared chrome

- [x] 1.1 `Prizm/Presentation/Components/AuthChrome.swift` — `AuthCard`, `AuthHeader`, `AuthField`,
      `AuthPrimaryButton`, `AuthErrorBanner` (D1).
- [x] 1.2 `DesignSystem.swift`: the `auth*` spacing tokens, and `authFootnoteGap`.
- [x] 1.3 `ContrastAwareOpacity.swift`: `authCardBorder` (D8).
- [x] 1.4 Register `AuthChrome.swift` in `project.pbxproj` — the app target's sources are listed
      individually, so a new production file needs a build file, a file reference, a group entry and a
      Sources-phase entry. (The test target is a synchronised folder and needs none.)

## 2. Login

- [x] 2.1 Rebuild in the card: icon + name + subtitle, then email, then master password (D4).
- [x] 2.2 Server field below the rule, at a smaller label, with a hint line instead of a placeholder
      (D5). Still a live `TextField`; the mockup's read-only + "Edit" row was not built.
- [x] 2.3 Error moved into `AuthErrorBanner`; `login.errorMessage` identifier kept.
- [x] 2.4 `AuthPrimaryButton` with the existing disabled rule and the `login.signIn` identifier.
- [x] 2.5 Footnote under the card, checked against the code before it was written (D7).

## 3. Unlock

- [x] 3.1 Rebuild in the card, same header component (D1).
- [x] 3.2 **Add the missing submit control** — `unlock.unlock`, disabled by the pre-existing
      `isUnlockDisabled` (D3).
- [x] 3.3 Keep the biometric view as its own row, below the button and above the rule (D2).
- [x] 3.4 PIN field and its remaining-attempts line moved onto the same labelled-field component.
- [x] 3.5 "Sign in with a different account" inside the card, under the rule.

## 4. Window sizing

- [x] 4.1 Login minimum height 520, unlock 560, both set by rendering at the declared minimum and
      looking (D6).
- [x] 4.2 Harness cases `auth-login-min`, `auth-login-min-error`, `auth-unlock-min` pin the worst case
      for each screen.

## 5. Strings

- [x] 5.1 Six keys added to `en.lproj` and `zh-Hans.lproj`: the login subtitle, `Server`, the two
      server hints, the footnote, and `Unlock`.
- [x] 5.2 `testBothScreensInChinese` asserts the switch took effect before it captures, because the
      failure mode of a broken language switch is a screenshot that looks fine.

## 6. Verification

- [x] 6.1 App target builds; `swift build --disable-sandbox` clean.
- [x] 6.2 Full `PrizmTests` suite at this point: **1487 passed, 0 failed, 0 skipped**. (Superseded twice
      over; the current count is in `remove-dead-code-and-doc-drift` §5.2.)
- [x] 6.3 Eleven captures in `/tmp/prizm-design/` reviewed: login empty / error / minimum / dark /
      Chinese, unlock plain / biometric / PIN / error / minimum / dark / Chinese.
      Contact sheet: `auth-final.png`.
- [x] 6.4 `CLAUDE.md`: the auth spacing tokens, an `Opacity.*` table, and the string-lookup gotcha
      found in 5.2.

## 7. Not verified — stated rather than hidden

- 7.1 **The Touch ID row renders as empty space in every capture.** `LAAuthenticationView` draws
      nothing in a non-key window in a test host, so the gap under the Unlock button is the sensor's
      reserved space, not its appearance. Only the real lock screen can confirm that.
- 7.2 **The Chinese captures initially read the checkout's `.lproj` folders**, because an Xcode-built
      `Vitrine.app` contained no localisation files at all. Fixed the same day in
      `openspec/changes/xcode-localisation-resources/`; the captures were re-taken with the harness
      resolving from `Bundle.main` only.
- 7.3 Focus rings are absent from every capture — the harness window is never key, so
  `.onAppear { focusedField = .email }` cannot be seen working.
- 7.4 VoiceOver ordering of the new card was not exercised.

## 8. Deliberately not done

- 8.1 No Touch ID button (D2).
- 8.2 No display/edit mode for the server field (D4).
- 8.3 The Xcode localisation defect found here is not fixed here. It went into its own change the same
      day: `openspec/changes/xcode-localisation-resources/`.
- 8.4 `UnlockViewModel` / `LoginViewModel` each still set one hardcoded English string,
      `"Invalid password encoding."`. It is the failure branch of `String.data(using: .utf8)`, which
      cannot fail for any Swift `String`, so it was left alone rather than localised.
