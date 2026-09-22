# Verification codes — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`.

## 1. Which items appear

- [x] 1.1 Failing test: a login with a TOTP secret appears.
- [x] 1.2 Failing test: a login without one does not — an empty row would be a lie about the item.
- [x] 1.3 Failing test: a card, a note, an identity and an SSH key never appear, even with a `totp`
      field set on a non-login type.
- [x] 1.4 Failing test: an item in Trash does not appear.
- [x] 1.5 Failing test: a login whose secret is present but unusable gets a row marked unusable, rather
      than being dropped silently or shown as an empty code.
- [x] 1.6 `VerificationCodesViewModel` building the rows from `VaultRepository.allItems()`.

## 2. The security properties

- [x] 2.1 Failing test: a re-prompt item's row reports itself gated.
- [x] 2.2 Failing test: the value the row offers to copy is the **derived code**, and the stored seed
      appears nowhere the row exposes.
- [x] 2.3 Failing test: a gated row routes its copy through `copyGated` rather than the ordinary path —
      the walk-around the gate exists to prevent.
- [x] 2.4 Failing test: an item the gate covers shows nothing until the gate is satisfied.
- [x] 2.5 Reuse `RevealGateBinding`, built the way `LoginDetailView` builds it.

## 3. Presentation

- [x] 3.1 `VerificationCodesSheet`: the list, the countdown, the copy control, and an empty state
      saying the vault holds no codes rather than showing an empty list.
- [x] 3.2 A toolbar button and a menu command opening it.
- [x] 3.3 Rows are built when the sheet opens and released when it closes — one timer per row must not
      outlive the screen.
- [x] 3.4 Accessibility identifiers and a label per row that reads as a sentence.
- [x] 3.5 Strings in both language files.

## 4. Verification

- [x] 4.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
- [ ] 4.2 Manual: a re-prompt item must ask for the master password when its row is revealed here, the
      same as in the detail pane. This is the check the security claim rests on.
- [ ] 4.3 Manual: copy from the list and confirm the clipboard still clears on the configured interval.

> **Done.** 1425 tests / 0 failures, and `./build-app.sh` produces a runnable bundle.
>
> **4.2 and 4.3 are outstanding.** 4.2 is the one the security claim rests on: an item with re-prompt
> protection must ask for the master password when its row is revealed in this list, exactly as it does
> in the detail pane. Both need a running signed app against a vault with a protected TOTP item.
>
> **A deliberate difference from the detail pane, recorded.** There, a code is masked until the user
> reveals it. Here an **unprotected** item's code is shown immediately — the screen exists to show codes,
> and masking all of them would make it a list of names with extra steps. What is not relaxed is the
> gate: an item the user marked as requiring the master password stays masked until it is given. That is
> the user's explicit instruction about that item, and a convenience screen does not get to overrule it.
