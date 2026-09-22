# Verification codes — Design

## Context

`TOTPCodeViewModel` already does the hard part: it recomputes from the secret on every refresh, injects
the clock so a countdown is testable at specific instants, and exposes the *derived* code as
`copyValue` rather than the seed. `TOTPCodeView` renders one row and takes a `RevealGateBinding` so the
master-password gate can cover it.

This feature is a list of those, which is mostly composition — and the composition is where the two
risks are.

## Decision 1 — the gate is reused, not reimplemented

A row for an item with `reprompt != 0` gets `RevealGateBinding.gated(...)` built the same way
`LoginDetailView` builds it: `isGated`, the gate's answer, a `request` closure, and a **`copyGated`**.

The last one is the one to get right, and `RevealGateBinding` already says so in its own comment: a
gated row that fell back to the ordinary copy is a gate walkable-around by clicking the value instead of
using the menu. In a list, where every row has a copy control a finger's width away, that is the
difference between the gate working and the gate being decoration.

`RevealGateBinding.gated` makes `copyGated` **required** rather than optional for exactly this reason,
so this feature inherits the protection by construction rather than by remembering.

## Decision 2 — the seed never enters the list

`TOTPCodeViewModel.copyValue` is the derived code. The seed is a credential that generates codes
forever, and Vitrine already treats it as one: the detail view never shows it and the copy commands never
put it on the clipboard. A list multiplies the opportunities to leak it, so the tests assert on the
copyable value rather than trusting that nobody would.

## Decision 3 — one view model per row, each keeping itself current

`TOTPCodeViewModel` already owns a timer and re-derives from the step boundary. Reusing it means the
list refreshes correctly for free, including the case a single shared timer would get wrong: two codes
with different periods (30s and 60s) do not expire together.

The cost is one timer per row. A vault with a hundred TOTP items would have a hundred timers — which is
why the rows are built when the sheet opens and released when it closes, rather than living for the
session. The sheet is not a background service.

## Decision 4 — Trash is excluded

`isDeleted` items are not in the vault. Listing them would put a code one click away for an item the
user believes they deleted.

## Decision 5 — a sheet, not a pane

Codes on screen are codes an onlooker can read. A sheet is present while the user is using it and gone
afterwards, which matches how the feature is used: reach for it when asked for a code, close it when the
code is entered. A toolbar toggle that stays on would leave the vault's second factors visible for the
rest of the session.

## Verification

Unit tests, on the view model rather than the view:

- only logins with a usable secret appear; notes, cards and items without a seed do not
- items in Trash do not appear
- a re-prompt item's row is **gated**, and its copy route is the gated one
- the value a row would copy is the **derived code**, never the stored seed
- a row whose secret cannot produce a code is marked unusable rather than shown as empty
- each row's countdown comes from that item's own period

The manual check is the one that matters for the security claim: an item with re-prompt protection must
ask for the master password when its row is revealed in the list, exactly as it does in the detail pane.
