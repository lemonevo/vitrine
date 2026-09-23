# Tasks — passkeys as a destination

## 1. The selection

- [x] 1.1 `SidebarSelection.passkeys` — display name `L("Passkeys")`, an explicit `==` arm, and a hash
      arm. The `==` arm is not optional: the operator falls through to `default: return false`, so a
      case added without it compares unequal to itself and the row can never be selected.
- [x] 1.2 `VaultItem.hasPasskey` / `.passkeyCount` in `Domain/Entities/VaultItem.swift` — existence and
      count read off the still-encrypted credential list, so no key is needed to answer either.
- [x] 1.3 `VaultRepositoryImpl.buildIndexes()` lists `.passkeys` among the pre-built selections and
      counts it, which is what `vault-actor-isolation` already requires of a selection that the sidebar
      shows. `items(for:)` needed no change: its `default` arm reads the index.
- [x] 1.4 `MockVaultRepository` gained the matching `items(for:)` case and a real `.passkeys` count —
      its switch is exhaustive, so the compiler asked.

## 2. The destination

- [x] 2.1 `PasskeysPane` (`Presentation/Vault/Passkeys/PasskeysPane.swift`) — one row per item: name,
      username, how many credentials it carries, and the relying parties it could read.
- [x] 2.2 Rows arrive as `viewModel.displayedItems`, so the toolbar's search field and sort menu scope
      the destination through the existing vault search. No second query or sort state, unlike the codes
      destination — which owns its rows and therefore has to own its filtering.
- [x] 2.3 Each row owns a `PasskeysViewModel` — the detail section's type, reused unchanged — through
      `@StateObject`, loaded in `.task` and released in `.onDisappear`. A plain `let` would install no
      subscription and the row would draw once, while the read was still outstanding.
- [x] 2.4 ⌘F on this destination only focuses the field; `activateGlobalSearch()` would move the
      selection to `.allItems` and carry the user off the screen they are typing on.
- [x] 2.5 The row's count is what the item carries, not what decrypted, so an item with one damaged
      credential still reports three. A failed read is named on the row rather than shown as an empty
      list.
- [x] 2.6 The footer reuses the detail section's existing string and key — the same sentence in both
      places, so neither can drift from the other.

## 3. Wiring

- [x] 3.1 `AppContainer` / `PrizmApp`: nothing added. The pane is built from the `makePasskeysViewModel`
      factory the detail column already receives, so the two surfaces cannot disagree about what a
      failed read looks like.
- [x] 3.2 `VaultBrowserView` routes `.passkeys` to the pane only when that factory exists; without it
      the destination falls through to the ordinary item list rather than drawing an empty column that
      reads as an empty vault.
- [x] 3.3 `AccessibilityID`: `Sidebar.passkeys`, and a `Passkeys.destination*` namespace kept separate
      from the section's so a test aimed at one cannot be satisfied by the other.
- [x] 3.4 `PasskeysPane.swift` registered in `project.pbxproj` (file reference, group, group child,
      Sources phase) — the app target compiles from an explicit list. Confirmed compiled by the
      `SwiftCompile … PasskeysPane.swift` line in the build log.
- [x] 3.5 Six new keys in **both** `en.lproj` and `zh-Hans.lproj`. Checked mechanically: 608 keys each
      side, zero one-sided, and all seven `L(...)` literals in the pane resolve in both tables.
- [x] 3.6 The sidebar glyph: `key.horizontal.fill` is the literal passkey symbol and 19pt wide against
      `Spacing.sidebarIconWidth`'s 18pt column, so it ran into the label — visible in the render, not in
      the code. `touchid` fits and is not used by any other row.

## 4. Verification

- [x] 4.1 `VaultRepositoryPasskeysSelectionTests` — 7 tests against the **real** `VaultRepositoryImpl`,
      because the thing under test is `buildIndexes()`. Includes the case the whole design rests on:
      credentials encrypted with a key this repository does not hold are still listed, and the same
      test asserts reading them really does fail, so the assertion cannot pass by the fixture having
      become readable.
- [x] 4.2 `VaultScreenshotTests.testPasskeysPane` — the pane rendered for real: two credentials on one
      row, the singular "1 passkey", and a row whose read failed saying so.
- [x] 4.3 `testSidebarAlone` re-rendered to check the new row's spacing.
- [x] 4.4 Full suite: `xcodebuild test` with the signing flags CI passes, run clean.
- [x] 4.5 **1585 tests executed, 0 failures** — read out of the log rather than off the verdict line.
      The count is 1577 + the 7 selection tests + the 1 new render test, which is how the new tests were
      confirmed to have actually run rather than been filtered out.
- [x] 4.6 `./build-app.sh` and a relaunch (PID 58046). The shipped binary was checked rather than
      trusted: `nm`/`strings` on `dist/Vitrine.app/Contents/MacOS/Prizm` show `PasskeysPane`'s symbols
      and both new accessibility identifiers, and its mtime post-dates the last source edit.
- [ ] 4.7 **Not verified by anyone but a human:** the destination has not been opened with a real vault
      signed in. The renders in 4.2 and 4.3 are the offscreen harness, and `screencapture` yields a
      black image in this session, so no pixel of the running app has been looked at. Selecting
      Passkeys with live data — and seeing whether the rows name the sites they should — is the
      remaining check.

## 5. Known limits, stated rather than left to be found

- [x] 5.1 Search does not match a relying-party id. Those strings are EncStrings on the wire, so
      matching them would mean decrypting every credential in the vault to answer one keystroke. The
      no-matches message says "no item with a passkey matches", which is the truth.
- [x] 5.2 The destination lists items, not credentials: an item with three passkeys is one row. This is
      the shape that was chosen over flattening every credential into the list, and it is why the row
      carries a count.
- [x] 5.3 Nothing here can create, use, delete or export a passkey. That was already true of the detail
      section and `PasskeyCredential`'s shape; the destination inherits it rather than restating it.
