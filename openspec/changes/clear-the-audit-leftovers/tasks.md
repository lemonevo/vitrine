# Tasks — the rest of the audit list

## 1. Dead code

- [x] 1.1 `GlyphControl` deleted. Verified zero references repo-wide (the surviving name in the tree is
      `GlyphControlStyle`, a different type, which is what the deleted doc comment was actually
      describing).
- [x] 1.2 `AccessibilityID.Vault.verificationCodesButton` deleted — the toolbar button the sidebar
      destination replaced. `Sidebar.verificationCodes` is the live one and is untouched.

## 2. Warnings

- [x] 2.1 `KeychainPinUnlockService.isSet` — the always-true `!= nil` comparison replaced with the
      check the code actually performs (read, or fall into `catch`). Comment says why the old form was
      harmless *and* still worth removing.
- [x] 2.2 `AuthRepositoryImpl` — `if let pending` → `if pendingTwoFactor != nil`, with the reasoning
      about CoW copies and force-unwrapping preserved rather than dropped.
- [x] 2.3 `OpenSSHPrivateKey` — `publicKey`, `n`, `e` to `let`. The four values that are zeroized stay
      `var`, so the distinction between public and private material is now visible in the bindings.
- [x] 2.4 Build warning count: 7 → 2. The two that remain are the deprecated APIs, left on purpose.

## 3. The duplicated date rule

- [x] 3.1 `Domain/Utilities/ISO8601WireDate.swift` — the pair and the either-form fallback, once.
- [x] 3.2 `VaultExportDocument.formatISO8601` / `.parseISO8601` and `VaultRepositoryImpl.parseISODate`
      delegate to it. Their own doc comments kept, because each explains a different reason for
      tolerating both forms.
- [x] 3.3 `CipherMapper` and `SyncTimestampRepositoryImpl` left alone, and the new file names that
      decision so the next reader does not treat the remaining two as an oversight.
- [x] 3.4 Registered in `project.pbxproj` (file reference, group child, build file, Sources phase).

## 4. Layering

- [x] 4.1 `AccountFingerprintPhrase.swift` → `Data/Crypto/`. Its only production caller was already in
      `Data/UseCases/`, so nothing had to change to reach it.
- [x] 4.2 `GeneratorHistory.swift` → `Presentation/Vault/Edit/`, beside the environment key that hands
      it to the views that observe it.
- [x] 4.3 Both test files moved with their subject; the test target picks them up from its synchronised
      folder group, so no project edit there.
- [x] 4.4 Rule re-checked rather than assumed: every `import` under `Prizm/Domain` is now
      `import Foundation`, and no `CryptoKit` / `CommonCrypto` / `Security` / `Argon2Swift` import
      exists outside `Prizm/Data/`.

## 5. Error wording

- [x] 5.1 `AttachmentCryptoError`, `EncStringError`, `KeychainError`, `IdentityTokenError` conform to
      `LocalizedError`. Reachability was checked first: these four can arrive inside
      `L("Upload failed: %@", …)`-style interpolation; the two mapper errors cannot and were not given
      text nobody would read.
- [x] 5.2 `KeychainError.unexpectedStatus` keeps the OSStatus number in the message — it is the only
      thing a user can quote.
- [x] 5.3 Terminology matched to the tables already in use: "two-factor" in English (not "second
      factor", which was the first draft) and 两步验证 in Chinese, matching the four existing keys.
- [x] 5.4 17 keys added to **both** tables. Parity checked mechanically: 628 each side, zero one-sided.
- [x] 5.5 `DataErrorWordingTests` — 6 tests. The wording assertions are by negation (must not contain
      the type name) so they hold in any locale; the `zh-Hans` assertion requires the value to *differ*
      from the key, which is what catches an English column pasted into the Chinese table.

## 6. Verification

- [x] 6.1 `xcodebuild build` clean, 2 remaining warnings both being the deprecated APIs left on purpose.
- [x] 6.2 `DataErrorWordingTests` — 6 tests, 0 failures, including the bundle-resource lookup that
      would fail loudly if the localisation tables were not copied into the test host.
- [x] 6.3 Full suite: `xcodebuild test` with the signing flags CI passes, run clean.
- [x] 6.4 **1593 tests executed, 0 failures** — read from the log. 1587 before this change plus the 6
      new wording tests, which is how they were confirmed to have run rather than been filtered out.
- [x] 6.5 `./build-app.sh` and a relaunch (PID 65280 → 69865). The shipped binary was checked by
      content, not by the build's own summary: `strings` finds the new attachment-error sentence, the
      new passkeys pane identifier and the new crypto-error sentence in
      `dist/Vitrine.app/Contents/MacOS/Prizm`, and its timestamp post-dates the last edit.

## 7. Note on what "red first" could not mean here

The unlock-error fix in `unlock-error-named-the-enum-not-the-password` was demonstrated red by running
its tests against the unmodified code. These four enums cannot be demonstrated the same way: the test
constrains its helper to `Error & LocalizedError`, so removing a conformance is a **compile failure**
rather than a test failure. That is a stronger guarantee than a red test — the code cannot ship
unworded — but it is a different kind, and it is stated so nobody reads the absence of a red run as an
absence of a check.
