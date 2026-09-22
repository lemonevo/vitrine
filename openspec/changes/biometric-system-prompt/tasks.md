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

- [x] 3.1 Add `Unlock with %@` and `Open your Prizm vault with %@` to both tables; remove the now
      unused `unlock your Prizm vault`
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
- [ ] 5.2 Rebuild `dist/Prizm.app` and confirm the system dialog is what appears, on real hardware
- [ ] 5.3 Verify Decision 5: that the dialog's password fallback does not release the vault key
