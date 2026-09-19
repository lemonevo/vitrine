## 1. Wire-model the fields the write path currently drops

- [x] 1.1 Add `JSONValue` to `Prizm/Domain/Utilities/JSONValue.swift` — `Codable`/`Equatable`/`Hashable`/`Sendable`, hand-written decode/encode, no `Any`
- [x] 1.2 Add `PreservedCipherFields` to `Prizm/Domain/Entities/VaultItem.swift` — `passwordHistory`, `archivedDate`, `cipherKey`, `fido2Credentials`, `passwordRevisionDate`, `autofillOnPageLoad`, all opaque, with a doc comment stating why they exist
- [x] 1.3 Add `VaultItem.preserved` (default `.empty`) and thread it through the memberwise init
- [x] 1.4 Extend `RawCipher` with `passwordHistory` and `archivedDate`; extend `RawLoginData` with `fido2Credentials`, `passwordRevisionDate` and `autofillOnPageLoad`
- [x] 1.5 Add unit tests: `RawCipher` decodes a payload containing all six fields, and re-encodes them unchanged

## 2. Populate and merge in the mapper

- [x] 2.1 `CipherMapper.map` fills `VaultItem.preserved` from the raw cipher
- [x] 2.2 `CipherMapper.toRawCipher` merges `draft.preserved` back into the outgoing `RawCipher`
- [x] 2.3 `toRawCipher` resolves the effective field key from `preserved.cipherKey` (decrypt with the wrapping key) and returns that EncString as `key`
- [x] 2.4 `DraftVaultItem` carries `preserved` through `init(_ item:)`, the memberwise init and `blank(type:)`
- [x] 2.5 Unit tests: passkey round trip, password-history round trip, `archivedDate` round trip, per-item key reused for encryption and echoed back, personal item unaffected

## 3. Make cache patches field-wise

- [x] 3.1 Add `VaultItem.with(…)`; document the nested-optional convention for `folderId` / `organizationId`
- [x] 3.2 Rewrite `deleteFolder` to use `with(folderId: .some(nil))` — keeps `organizationId` / `collectionIds`
- [x] 3.3 Rewrite `moveItemToFolder` and `moveItemsToFolder` the same way
- [x] 3.4 Convert the remaining four rebuild sites (`deleteItem`, `restoreItem`, `updateAttachments`, the org `collectionIds` patch in `update`) to `with(…)`
- [x] 3.5 Throw `VaultError.decryptionFailed` in `update`/`create` when an org item's org key is missing
- [x] 3.6 Unit tests: org item keeps org membership after folder delete and after move; org item without an org key refuses to save

> 3.4 实际排查出 **7 处**手工重建（不止 4 处）：`deleteItem`、`restoreItem`、`updateAttachments`、
> `deleteFolder`、`moveItemToFolder`、`moveItemsToFolder`、`update` 的 `collectionIds` 补丁。全部已改写。

## 4. Generate TOTP codes

- [x] 4.1 Add `TOTPGenerator` protocol in `Prizm/Domain/Repositories/`
- [x] 4.2 Add `TOTPGeneratorImpl` in `Prizm/Data/Crypto/` — parse `otpauth://` and bare Base32, HMAC-SHA1/256/512, period and digits from the URI
- [x] 4.3 ~~Add `TOTPError` with a typed failure for an unusable secret~~ → **改为**：不可用的密钥直接返回 `nil`（协议签名是 `String?`）。复制命令因此变成 no-op，菜单项自动置灰，不需要引入一个新的错误类型
- [x] 4.4 Unit tests: RFC 6238 test vectors (SHA-1/256/512), bare-secret input, padded/lower-case Base32, custom digits/period, malformed secret returns nil

## 5. Point Copy Code at the generated code

- [x] 5.1 Add the generator to `RootViewModelDependencies` and `AppContainer`
- [x] 5.2 `RootViewModel.selectedFieldValue(.totp)` returns the generated code; `selectedFieldAvailable(.totp)` is false when no code can be derived
- [x] 5.3 Add a test asserting the copied value is the code, not the seed

> 5.3 在 `RootViewModelCopyCommandTests` 中驱动真实命令并读取真实 `NSPasteboard`：
> 注入桩生成器返回固定值，断言剪贴板拿到的是它而不是种子；并有一条「任何复制命令都不得写入种子」的遍历断言。

## 6. Fetch icons from the account's own server

- [x] 6.1 `FaviconLoader`: remove the hardcoded default, add `configure(iconsBase:)` (`nil` disables), return `nil` immediately when disabled
- [x] 6.2 Add the `showWebsiteIcons` preference (default on) and read it in the loader
- [x] 6.3 `AppContainer.refreshWebsiteIcons()` — resolve `{base}/icons` from `authRepository.serverEnvironment`
- [x] 6.4 Call it at vault transition (`RootViewModel`) and when the Settings toggle changes
- [x] 6.5 `SettingsView`: "Show website icons" toggle in the ~~General~~ **Privacy** section
- [x] 6.6 Unit tests: disabled loader performs no request; enabled loader uses the configured base and never `icons.bitwarden.net`

## 7. Localisation and verification

- [x] 7.1 Add every new user-visible string to both `Localizable.strings` files; keep key parity
- [x] 7.2 `plutil -lint` both files; run the key-coverage check
- [x] 7.3 `swift build` with zero warnings
- [x] 7.4 Full test suite — no new failures
- [x] 7.5 Rebuild `dist/Prizm.app`; confirm the new strings are in the binary and the bundle
- [x] 7.6 Update `FEATURE-GAP-ANALYSIS.md` §2 to mark the five items fixed

## 8. Found while implementing (not in the original plan)

- [x] 8.1 `CipherMapper.map` decrypted a cipher's fields with the vault/org key even when the cipher
      carried a per-item key. Bitwarden's `Cipher.decrypt` uses the **unwrapped per-item key** for
      every field and the vault/org key only to unwrap it, so such items failed MAC verification —
      unreadable, and therefore un-editable, which made the 2.2/2.3 write fix unreachable for them.
      Fixed by resolving the effective key before any decryption. Covered by
      `test_mapDecryptsFieldsWithThePerItemKeyNotTheVaultKey` and the full-round-trip test.
