# Design

## Context

`LAAuthenticationView` is not a widget that happens to look native — pairing it with an `LAContext`
before `evaluatePolicy` is the switch that decides *where the prompt appears*. With a paired,
on-screen view, macOS draws the fingerprint inside the app's window; without one, the security agent
raises its own dialog. The whole embedded path existed to choose the first option, so the change is a
deletion, not a re-skin.

## Decisions

### 1. Delete the embedded path rather than re-plumb it

The alternative was to keep `EmbeddedBiometricUnlock` and call it with an unpaired context, which
would produce the system dialog anyway. That leaves a protocol, an overload and a second copy of the
unlock tail whose only distinguishing feature is a parameter nobody sets. `AuthRepositoryImpl` already
conformed to `AuthRepository.unlockWithBiometrics()`, and that path funnels through `completeUnlock()`
— the shared tail the embedded copy had duplicated line for line. Removed, not renamed.

### 2. Ask once on appearance; the button is the retry

`UnlockView` calls `requestBiometricUnlock()` from `.task`, which has no `id:` and so fires once per
appearance of the screen. The button calls the same method.

The previous rule — "always armed": re-evaluate on every cancellation — came from
`2026-04-12-touch-id-inline` and is inverted here. With an inline glyph, a re-arm was invisible and
useful: the user could put a finger down again at any moment. With a modal, the same rule means the
dialog reappears the instant it is dismissed, so a user who wants the keyboard instead has to fight
it. Retry becomes the user's action.

### 3. The in-flight guard is a swallow, not a disabled control

`evaluatePolicy` queues a dialog per call, so three clicks would mean three dialogs.
`isBiometricPromptInFlight` drops concurrent requests. It is a plain `var`, not `@Published`: the
button does not change appearance while a modal is up (the modal has the focus anyway), and
publishing it would make the control blink for no information.

### 4. The reason string names the sensor

`BiometricKeychainServiceImpl.promptReason` reads `LAContext().biometryType`. The docs say
`canEvaluatePolicy` must be called before `biometryType` is meaningful; on the macOS this project
targets (26+) the probe was verified to report `.touchID` on a fresh context without it, so the
extra call is not made. The fallback `L("Biometrics")` covers a device with no enrollment, where
the prompt is unreachable in practice.

Presentation cannot use this: `CONSTITUTION.md` forbids Presentation importing Data, and the
subtitle and button label already resolve the sensor name locally.

### 5. What the dialog's "Enter Password" button does not unlock

`.biometryCurrentSet` on the Keychain item means the *read* needs a successful biometric no matter
what the dialog's fallback option does. Entering the account password into the system prompt does not
release the vault key; the read fails and the user is back at the card. This is inferred from the
access-control class, not verified on hardware, and is recorded as a thing to check manually.

## Out of scope, found while doing this

The canonical spec requires the lockout message to read
`Too many failed Touch ID attempts — enter your master password`. No such string exists: the ViewModel
surfaces `error.localizedDescription`, and `BiometricUnlockJourneyTests.testBiometricUnlock_lockout_showsErrorMessage`
asserts it inside `if error.waitForExistence(...)`, so it passes when the banner never appears. Left
alone — deciding whether to add the copy or amend the spec is a separate call, and fixing the vacuous
assertion belongs with that decision.
