# Replace the hand-built Touch ID UI with the system prompt

## Why

The unlock screen drew its own fingerprint glyph via `LAAuthenticationView`
(`LocalAuthenticationEmbeddedUI`) and paired that view with the `LAContext` used for
`evaluatePolicy`. Pairing is what *suppresses* the system dialog: the prompt is routed into the app's
own view hierarchy instead. So the reason the authentication looked hand-built is the same mechanism
that made it not look like the rest of macOS.

The user asked for the system prompt — the dialog every other app raises — rather than Prizm's own
affordance.

Removing the pairing collapses most of the feature: the embedded view, the context-version re-arm
counter, the `EmbeddedBiometricUnlock` protocol, the `readBiometric(key:context:)` overload and a
near-duplicate copy of the unlock tail inside `AuthRepositoryImpl`. The plain
`AuthRepository.unlockWithBiometrics()` path already existed, already used `completeUnlock()`, and
already produced the system dialog. What was left to do was decide what happens when the user
declines a prompt that is now modal.

## What Changes

- **`Presentation/Components/EmbeddedTouchIDView.swift` — deleted**, with its project entries.
- **`Data/Repositories/EmbeddedBiometricUnlock.swift` — deleted.** So does
  `AuthRepositoryImpl.unlockWithBiometrics(context:)`, which was the same unlock with a second copy
  of the tail.
- **`BiometricKeychainService`** loses `readBiometric(key:context:)`; `BiometricPolicyEvaluating`
  loses `evaluate(on:reason:)`. Both existed only so a context pre-paired with an embedded view could
  be evaluated.
- **The unlock screen gains a `使用 Touch ID 解锁` button** (`unlock.biometricButton`) as the retry
  path, and still asks once automatically when the screen appears.
- **Cancelling no longer re-arms.** The old behaviour re-triggered evaluation on every cancellation;
  that was written for an inline glyph and becomes an inescapable loop when the prompt is modal.
- **The prompt reason names the sensor**: `Open your Prizm vault with Touch ID` /
  `使用 Touch ID 打开你的 Prizm 保险库`. A dialog that appears over whatever app the user was in has
  to say who is asking, and "unlock your Prizm vault" read as an unlabelled sentence.
- Four comments that asserted "no system modal appears" are corrected; they were the documentation of
  the removed mechanism.

## Impact

- Affected specs: `biometric-unlock` (one MODIFIED requirement, one scenario rewritten and one added)
- Affected code: `UnlockViewModel`, `UnlockView`, `AuthRepositoryImpl`, `BiometricKeychainService`,
  `BiometricKeychainServiceImpl`, `AppContainer`, `AccessibilityIdentifiers`, both `Localizable.strings`
- Supersedes the biometric wording in the still-unarchived `auth-screens-redesign` delta, which
  pinned "no separate Touch ID button SHALL be present"
- UI test `BiometricUnlockJourneyTests` now asserts on the button instead of the badge image
