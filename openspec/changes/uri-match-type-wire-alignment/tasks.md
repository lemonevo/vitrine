# URI match type on the wire — Tasks

## 1. The type

- [x] 1.1 `URIMatchType`: explicit `init(rawValue:)` / `var rawValue`, `.defaultMatch` (0),
      `.baseDomain` (1) … `.never` (6), `unknown(Int)`.
- [x] 1.2 `URIMatchType.selectable` for the picker, mirroring `SecureNoteSubtype.selectable`.
- [x] 1.3 `CipherMapper` read side: `map` instead of `flatMap` now that the initialiser cannot fail.
- [x] 1.4 `VaultExportDocument+Import`: same, and the comment about "degrading to nil" replaced — an
      unknown integer is now carried, not dropped.

## 2. The form

- [x] 2.1 Picker iterates `selectable`; labels corrected ("Base domain").
- [x] 2.2 An unrecognised stored value gets its own row labelled with the number, without a force unwrap.
- [x] 2.3 Two keys added to both tables: `Base domain`, `Unknown (%d)`.

## 3. Tests

- [x] 3.1 `URIMatchTypeTests` — wire numbers asserted per case in both directions; "Never is not 5";
      unknown values survive; picker contents and order.
- [x] 3.2 Invariant fixture carries `match: 6` and `match: 7`; `test_uriMatchStrategiesSurviveAtTheirOwnValues`.
- [x] 3.3 **Mutation:** made the encoder write `nil` for `.never` → 3 failures, one naming the autofill
      consequence. Restored and confirmed green.
- [x] 3.4 The 13 `.domain` call sites in tests renamed to `.defaultMatch` (they were sample values; none
      asserted a number).

## 4. Verification

- [x] 4.1 App builds.
- [x] 4.2 Full suite: **1505 passed, 0 failed, 0 skipped**.
- [ ] 4.3 Outstanding: a live item with `match: 6` set in the web vault, opened and re-saved by Prizm.

## 5. Deliberately not done

- 5.1 No migration of previously-saved shifted values (D4).
- 5.2 `Prizm/UITests/` still reference the old sample values in files that belong to no target; not
      touched here.
