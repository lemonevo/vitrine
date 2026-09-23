# Tasks — unlock error named the enum, not the password

## 1. The mapping

- [x] 1.1 `AuthRepositoryImpl.unlockWithPassword` — `decryptSymmetricKey` wrapped, rethrown as
      `AuthError.invalidCredentials`; the underlying error logged with `privacy: .public` because it
      names no key material, and the comment says why the message is not shown.
- [x] 1.2 `PrizmCryptoServiceError: LocalizedError` — all four cases worded; `vaultLocked` reuses the
      existing `L("The vault is locked. Please unlock to continue.")` rather than adding a second
      wording of the same sentence.
- [x] 1.3 Three new keys in `en.lproj` **and** `zh-Hans.lproj`.

## 2. Tests

- [x] 2.1 `testUnlockWithPassword_storedKeyWillNotDecrypt_throwsInvalidCredentials` — seeds a real
      session, makes the crypto mock fail the stored-key decrypt, asserts the thrown error is
      `AuthError.invalidCredentials`.
- [x] 2.2 `testCryptoServiceErrors_localizeToASentenceNotAnEnumIndex` — all four cases, asserted by
      negation so the test does not pin a locale.
- [x] 2.3 Red-first: both tests run against the unmodified files → **5 failures**, one naming each of
      the four cases plus the unlock comparison. Restored from a copy taken before the revert.
- [x] 2.4 The first draft of 2.2 asserted `text == error.errorDescription`, which does not compile
      against the un-fixed code — the member it names is the conformance being added. That made the
      red run a build failure rather than a failing test, so the assertion was dropped: a regression
      test has to be able to fail.
- [x] 2.5 `AuthRepositoryImplTests` (21) and `PrizmCryptoServiceTests` (11) → **32 tests, 0 failures**.

## 3. Delivery

- [x] 3.1 Full suite: **1587 tests, 0 failures** — 1585 before this change plus the 2 new ones, which
      is how the new tests were confirmed to have run rather than been filtered out.
- [x] 3.2 `./build-app.sh` and a relaunch (PID 58046 → 65280). The shipped binary was checked rather
      than the build's "complete" line trusted: `strings` on `dist/Vitrine.app/Contents/MacOS/Prizm`
      contains the new `Could not decrypt the stored vault key` wording.
- [x] 3.3 Localisation parity re-checked mechanically after the three new keys: 611 keys each side,
      zero one-sided.
