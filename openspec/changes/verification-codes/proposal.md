# Verification codes — Proposal

## Why

Two-factor codes live one per item, behind a click. Bitwarden ships a separate app whose whole purpose
is a screen listing them together, and the mobile clients surface codes without opening an item —
because the moment a user needs a code is the moment they are being asked for it by something else and
want it in front of them, not three interactions away.

Prizm derives TOTP codes already (`TOTPCodeViewModel`, with a live countdown) but only inside the
detail pane of one item.

## What Changes

- A **Verification Codes** sheet listing every login in the vault that carries a TOTP secret, each with
  its live code and countdown.
- **Re-prompt-protected items stay locked in the list** until the master password is given, through the
  same gate the detail view uses.
- Copied codes go through the same path the rest of the app uses, so the clipboard-clear timer applies.
- Reachable from the toolbar and from a menu command.

## The security question this feature has to answer

A list of every code is exactly what an item's re-prompt protection exists to withhold. Built naively,
this screen would be a bypass: the gate would still be asking for a password on the item, while the list
handed the same code over without it.

So the list **does not get its own rule**. A gated row renders masked, reveals only through
`RevealGateBinding`, and copies only through `copyGated` — the same three things the detail view uses.
`RevealGateBinding`'s own comment says why this matters: a gated row that fell back to the ordinary copy
would be "a gate you can walk around by clicking the value instead of using the menu".

The other rule that carries over: **the stored seed is never on screen and never on the clipboard.**
The row shows a derived code, and `TOTPCodeViewModel.copyValue` is the code, not the secret. A list is
a larger surface for getting that wrong, so it is asserted.

## Non-goals

- **Editing or adding seeds here.** The item's edit form owns that.
- **Being a general authenticator.** No import from other authenticator apps, no accounts that are not
  vault items — Bitwarden ships that as a separate product.
- **A persistent window or a menu-bar item.** A sheet, closed when it is no longer needed, so codes are
  not on screen by default.
- **Items in Trash.** A deleted item is not in the vault, and its code should not be one click away.

## Impact

- `Prizm/Presentation/Vault/VerificationCodes/VerificationCodesViewModel.swift` — **new**
- `Prizm/Presentation/Vault/VerificationCodes/VerificationCodesSheet.swift` — **new**
- `Prizm/Presentation/Vault/VaultBrowserViewModel.swift` — the sheet's state and the row factory
- `Prizm/App/PrizmApp.swift` — the menu command
- `Prizm/Presentation/Vault/VaultBrowserView.swift` — the toolbar button and the sheet
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings`
