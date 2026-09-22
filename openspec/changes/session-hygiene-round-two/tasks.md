# Tasks — session hygiene, round two

## 1. Per-account unlock credential default

- [x] 1.1 `UnlockCredentialPreference` keyed by lowercased email; `lastUsedMethod(for:)` /
      `recordSuccess(of:for:)`.
- [x] 1.2 `UnlockViewModel` reads and writes through the account it was built for.
- [x] 1.3 `testDefault_isNotSharedBetweenAccountsOnTheSameLaunch` — the regression test for the bug
      `unlock-credential-layering` shipped the same day.

## 2. Zeroing the derivation

- [x] 2.1 `loginWithPassword`: `var masterKey` + `defer { masterKey.zeroize() }`. The comment claiming
      the `Data` parameter existed so the repository could zero it was corrected — under copy-on-write
      that would only ever wipe a private copy.
- [x] 2.2 `unlockWithPassword`: both `masterKey` and `stretched` discarded via the existing
      `discardDerivedKeys`, in a `defer` so the wrong-password throw is covered too.
- [x] 2.3 `LoginViewModel` / `UnlockViewModel`: `defer { passwordData.zeroize() }` inside the Task —
      the owner releases the bytes.
- [ ] 2.4 **Not covered by a test, and it cannot be covered the obvious way.** A mock repository that
      records the `Data` it was handed keeps a second reference alive, so the view model's `zeroize()`
      uniques the buffer and the mock's copy survives — a test written that way would fail while the
      production behaviour is correct. Verified by reading the call graph instead: the view model's
      `Task` is the only owner at the point the `defer` runs. `Data.zeroize` itself is already covered
      by the slice-overlap regression test.
- [ ] 2.5 Out of scope, named rather than fixed: `makeServerHash` returns a `String`, and Swift `String`
      storage cannot be zeroed. Same for the user-facing `password` field.

## 3. Quit-time cleanup

- [x] 3.1 `AttachmentTempFileManager.removeAllForTermination()` + a `willTerminate` observer. The
      deadline is deliberately ignored there; the comment says why that is only correct at quit.
- [x] 3.2 `SecretClipboard` — owns the write, the claim, and `clearIfStillOurs()`. Both view models that
      copy secrets route through it; their timed clears now ask it whether the value is still theirs.
- [x] 3.3 5 `SecretClipboardTests` over **named pasteboards**. `NSPasteboard.general` is shared by every
      process in the login session while classes run in parallel processes — asserting on it would
      reproduce the coupling `fix-test-preference-isolation` exists to prevent.
- [x] 3.4 2 termination tests: a file with ten minutes left on its deadline is still removed at quit,
      and the sweep is idempotent.
- [ ] 3.5 **Cannot be verified offline:** that `willTerminate` actually fires before the process is gone
      in a real ⌘Q (and does not fire on force-quit or crash, which the doc comments state as a limit).
      Needs the app run and `~/Library/Caches`/temp inspected.

## 4. Honest sign-out copy

- [x] 4.1 Verified what `signOut()` actually removes: 7 per-user Keychain items, `activeUserId`, the
      remembered 2FA token/email pair, the PIN's wrapped material, the biometric key, the vault cache,
      then lock + in-memory token clear.
- [x] 4.2 Verified what survives, on purpose: `bw.macos:deviceIdentifier` (`:995-1003`, never deleted),
      UserDefaults preferences (no removal call anywhere), and `KeychainServerTrustStore` entries
      (`removeConfiguration(forHost:)` is never called from sign-out).
- [x] 4.3 The alert now names both halves, with the reasoning at `PrizmApp.swift` — including why
      deleting the device identifier would be worse than the promise being narrower: Bitwarden's clients
      treat it as an installation identity, so a new one per login makes the server see a new machine.
- [x] 4.4 Old key removed from both tables rather than left orphaned (the parity test fails on a
      zh-Hans key English no longer uses).

## 5. Verification

- [x] 5.1 Full suite: **1536 passed, 0 failed, 0 skipped**. Cross-checked by counting `func test`
      declarations in `PrizmTests` — also 1536, so the executed set is the whole set. (The UITests' 78
      are not in that target and still never run.)
- [x] 5.2 `SecretClipboard.swift` registered in `project.pbxproj` (4 entries); the app target's
      synchronised group covers only `Prizm/Prizm`.
