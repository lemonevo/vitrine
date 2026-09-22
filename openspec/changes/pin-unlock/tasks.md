# PIN unlock — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`.

## 1. The crypto seam

- [x] 1.1 Failing test: deriving with the same PIN and salt twice gives the same 64-byte key; a
      different PIN or a different salt gives a different one.
- [x] 1.2 Expose PIN-key derivation on `PrizmCryptoService`, reusing the private `pbkdf2SHA256`.

## 2. The store

- [x] 2.1 Failing tests for `KeychainPinUnlockService`:
      - [ ] 2.1.1 the 64 bytes read back from storage are not the vault's key material — they cannot be
            used without the PIN
      - [ ] 2.1.2 set-then-unlock returns the original key material
      - [ ] 2.1.3 a wrong PIN throws and leaves the stored material intact, so the right PIN still works
      - [ ] 2.1.4 a PIN shorter than four characters is refused
      - [ ] 2.1.5 the salt is unique per installation
- [x] 2.2 `KeychainPinUnlockService`, storing the wrapped value, the salt and the failure count in
      `WhenUnlockedThisDeviceOnly` items.
- [x] 2.3 Failing tests for the attempt limit:
      - [ ] 2.3.1 four failures leave the material in place and the count at four
      - [ ] 2.3.2 a success resets the count
      - [ ] 2.3.3 the fifth failure wipes the material, the salt and the count
      - [ ] 2.3.4 **the count survives a new service instance** — the property that makes the limit a
            limit rather than a speed bump a restart clears
- [x] 2.4 Test that nothing stored is derived from the PIN by a route that could be tested offline:
      assert the stored items contain no value equal to the PIN.

## 3. The auth path

- [x] 3.1 Failing tests: `enablePinUnlock` requires an unlocked vault; `disablePinUnlock` removes the
      material; `unlockWithPIN` returns the same `Account` the master password would.
- [x] 3.2 Failing test: five failures drive the sign-out path, not just the wipe.
- [x] 3.3 Failing test: `signOut` removes the PIN material; `lockVault` does not.
- [x] 3.4 `pinUnlockAvailable` — false with nothing stored, false on a cold start when "require master
      password on restart" is on and the master password has not been entered this launch.

## 4. Presentation

- [x] 4.1 Settings: a PIN toggle that presents a set-PIN sheet (enter + confirm), and the
      "require master password on restart" setting with its default.
- [x] 4.2 `UnlockView`: a PIN field, offered only when `pinUnlockAvailable`.
- [x] 4.3 The failure count is visible while entering a PIN — a limit the user cannot see is a trap.
- [x] 4.4 Strings, including the warning shown beside the setting.
- [x] 4.5 Accessibility identifiers for the new controls.

## 5. Documentation

- [x] 5.1 `SECURITY.md`: the mechanism, what it is worth to an attacker, that it weakens local
      protection, and the two things the protection actually rests on.
- [x] 5.2 `README.md`: PIN listed among the unlock methods.

## 6. Verification

- [ ] 6.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
- [ ] 6.2 Manual: set a PIN, lock, unlock with it. Then quit, relaunch, and confirm the PIN is **not**
      offered with the default setting, and is offered once that setting is turned off.
- [ ] 6.3 Manual: five wrong PINs, and confirm the material is gone and the app is signed out.

> **Done so far: the security core and the auth path** (tasks 1–3, 5.1). 1389 tests, 0 failures.
>
> **Remaining: the presentation** (task 4) — the settings toggle and set-PIN sheet, the unlock screen's
> PIN field, the visible attempt count, and the strings. Also 5.2 (README) and 6.2–6.3.
>
> **Two things the tests cannot cover, stated so they are not assumed.** That the derivation is slow
> enough to matter is a judgement, not a measurement — 210,000 rounds is a starting point taken from
> general guidance, not a figure tuned here. And that a person who does not know the PIN cannot get in
> is the manual check: set one, quit, relaunch, and confirm neither the PIN nor the master password can
> be bypassed.

> **Code complete as of this pass.** 1389 tests / 0 failures, and `./build-app.sh` produces a runnable
> bundle. What remains is 6.2–6.3 (manual, below).
>
> **Deviations worth recording:**
> - `PinUnlockSettings` owns `minimumPINLength` and `maximumAttempts` rather than the service's
>   protocol. A `static` protocol requirement cannot be read from an `any` metatype, and the settings
>   screen would otherwise have to name a concrete Data-layer type to learn how many characters a PIN
>   needs. They are policy, so they live with the other policy.
> - `AuthRepositoryImpl` gained an injectable `UserDefaults`, because the restart setting reads one and
>   `PinUnlockSettings` defaulting to `.standard` would have re-created the cross-test contamination
>   fixed in `fix-test-preference-isolation`.
>
> **6.2–6.3 are outstanding and are the only checks that matter for this feature.** They need the app,
> which now exists: set a PIN, lock and unlock with it, quit and relaunch and confirm the PIN is not
> offered by default, then turn the setting off and confirm it is. Then five wrong PINs.
