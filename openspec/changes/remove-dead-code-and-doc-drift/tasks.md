# Remove dead code and doc drift — Tasks

## 1. Verified before deleted

Every item below was checked with a repo-wide search for the symbol name and confirmed to appear only at
its own declaration. Anything that could not be confirmed that way was left in place.

- [x] 1.1 `enum Config` removed; `DebugConfig` and `vaultDidLock` kept.
- [x] 1.2 `VerticalLabeledContentStyle.swift` deleted, with its four `project.pbxproj` entries.
- [x] 1.3 `Opacity.listSelection` removed.
- [x] 1.4 `FaviconLoader.clearCache()` removed.
- [x] 1.5 `PrizmCryptoServiceError.hkdfFailed`, `EncStringError.invalidIVLength` removed.
- [x] 1.6 11 design tokens removed.
- [x] 1.7 7 accessibility identifiers removed.

## 2. Comments and docs that asserted false things

- [x] 2.1 `DraftVaultItem.customFields` "out of scope" → describes what `CustomFieldsEditSection` does.
- [x] 2.2 `VaultExportDocument` format note: the enum is no longer `Int`-backed, and why that matters.
- [x] 2.3 `CLAUDE.md` token tables: 8 dead rows dropped, `detailLabelWidth` corrected 120 → 130,
      `listRowVertical` kept (only its pair-mate was dead).
- [x] 2.4 `CLAUDE.md` gained the two rules this session learned the hard way: item-level commands do not
      go in the window toolbar; a view must observe the model whose published values it renders.

## 3. Strings

- [x] 3.1 4 duplicate entries removed from each table, after confirming each pair had identical values.
- [x] 3.2 Key parity between the tables re-checked with an exact set comparison: 584 each, no
      one-sided keys.
- [ ] 3.3 **Not done on purpose:** the 15 orphan-key candidates. See the proposal — the search cannot
      distinguish an interpolated `Text("…\(x)…")` call from an unused key, and deleting a live key fails
      silently into showing the raw key.

## 4. Performance

- [x] 4.1 Audited: five hot spots identified, with the trigger for each established by reading the call
      chain rather than guessed.
- [ ] 4.2 **Reverted:** the `.nameAscending` pass-through. Two existing tests feed `sort()` an unsorted
      array, and they are correct to. Recorded in the proposal rather than quietly dropped.
- [ ] 4.3 **Not done:** sidebar tree rebuilds in `body`, per-row org lookup. Not measurable at this
      vault's size; the fixes are structural.
- [ ] 4.4 **Not done, and the one that would matter:** attachment encryption/decryption and whole-file I/O
      run on the main actor. A 2.4 MB attachment is a UI freeze proportional to size. This needs the
      repository and its view models moved off main-actor isolation, which is a change with its own design
      question, not a sweep item.

## 5. Verification

- [x] 5.1 App builds after every deletion.
- [x] 5.2 Full suite: **1505 passed, 0 failed, 0 skipped**.

## 6. README

- [x] 6.1 Added: verification-codes list, PIN unlock, CSV export, username generator, interface languages.
- [x] 6.2 Roadmap: "offline vault read" and "background refresh" moved out of **Now**; a line says what
      shipped since the table was written.
- [x] 6.3 The TOTP line now describes what both screens actually show.
- [ ] 6.4 **Not verified:** the Homebrew tap (`b0x42/prizm`) still points at the upstream owner's tap while
      every other link in the file points at this fork. Left alone — I cannot check whether that is
      intentional without trying an install.
