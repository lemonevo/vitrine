# Tasks

## 1. Remove the embedded path

- [x] 1.1 Delete `Presentation/Components/EmbeddedTouchIDView.swift` and its four `project.pbxproj` entries
- [x] 1.2 Delete `Data/Repositories/EmbeddedBiometricUnlock.swift` and its four `project.pbxproj` entries
- [x] 1.3 Drop the `EmbeddedBiometricUnlock` conformance from `AuthRepositoryImpl` and delete
      `unlockWithBiometrics(context:)`, which duplicated the tail that `completeUnlock()` already owns
- [x] 1.4 Drop `BiometricKeychainService.readBiometric(key:context:)` and
      `BiometricPolicyEvaluating.evaluate(on:reason:)`, both of which existed only for a pre-paired context
- [x] 1.5 Stop `AppContainer.makeUnlockViewModel` injecting the removed dependency

## 2. The system prompt becomes the only prompt

- [x] 2.1 `UnlockViewModel.requestBiometricUnlock()` replaces the three trigger methods, the
      `LAContext` property and the context-version re-arm counter
- [x] 2.2 Cancellation stops re-triggering evaluation
- [x] 2.3 `isBiometricPromptInFlight` swallows concurrent requests without changing the control
- [x] 2.4 `UnlockView` asks once from `.task` and offers a `buttonStyle(.bordered)` control labelled
      with the sensor, identifier `unlock.biometricButton`
- [x] 2.5 `BiometricKeychainServiceImpl.promptReason` names the sensor

## 3. Copy and comments

- [x] 3.1 Add `Unlock with %@` and `Open your Vitrine vault with %@` to both tables; remove the now
      unused `unlock your Vitrine vault`
- [x] 3.2 Correct the four comments asserting "no system modal appears", and the one in
      `AuthRepositoryImpl` that justified the re-arm from the cancel path

## 4. Tests

- [x] 4.1 `UnlockViewModelBiometricTests`: the cancellation case now asserts exactly one call, and a
      held-open attempt proves the in-flight guard both blocks and releases
- [x] 4.2 `BiometricKeychainServiceTests`: drop the context overload case; assert the prompt line names
      the sensor rather than comparing against a deleted key
- [x] 4.3 Shrink `MockBiometricKeychainService` and `NoopBiometricPolicyEvaluator` to the surviving protocols
- [x] 4.4 `BiometricUnlockJourneyTests` queries the button instead of the badge image
- [x] 4.5 Full suite green

## 5. Ship

- [x] 5.1 Render the unlock card and check the button against the rest of the card
- [ ] 5.2 Rebuild `dist/Vitrine.app` and confirm the system dialog is what appears, on real hardware
- [ ] 5.3 Verify Decision 5: that the dialog's password fallback does not release the vault key

## 6. The lockout message this spec mandates (added 2026-09-22)

Found while answering "can this ship": the spec's `THEN the system SHALL display the message "Too many
failed Touch ID attempts — enter your master password"` had **no counterpart in the code**. The sensor
locked out, the raw `LAError` fell through `default: throw laError`, and `UnlockViewModel`'s generic
handler printed `error.localizedDescription` — an untranslated framework string naming neither the
cause nor the way out.

- [x] 6.1 `AuthError.biometricLockout` added, its `errorDescription` the spec's sentence verbatim, so
      the scenario is satisfiable as written.
- [x] 6.2 `AuthRepositoryImpl.unlockWithBiometrics` maps `LAError.Code.biometryLockout` to it. Nothing
      is disabled: lockout is the sensor resting, not the enrollment changing.
- [x] 6.3 Tests: the repository maps it (mutation-checked — removing the case turns it red), the
      repository leaves both biometric preferences alone, and the view model shows the exact sentence.
- [ ] 6.4 **Still open, and this change cannot close it:** `BiometricUnlockJourneyTests.swift:63` wraps
      its whole assertion in `if error.waitForExistence(timeout: 5) { … }`, so the banner's absence is a
      pass. Fixing that `if` without also giving `Prizm/UITests/` a target produces a test that is red
      in a suite nobody runs. Both halves belong to the UITest-target decision (§A#2), not to this one.
