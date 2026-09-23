# Codes as a destination — Design

## Decision 1: the security reasoning is replaced, not deleted

The sheet was not a convenience choice. `verification-codes` Decision 5: *"Codes on screen are codes an
onlooker can read. A sheet is present while the user is using it and gone afterwards… A toolbar toggle
that stays on would leave the vault's second factors visible for the rest of the session."*

A destination has exactly the property that decision rejected. So:

- **Superseded, and said so.** Decision 5 carries a `SUPERSEDED` note naming this change. A reader who
  finds the old reasoning must not find it still arguing for behaviour that no longer exists.
- **Quoted where the new code lives.** `VerificationCodesPane`'s doc comment states the cost in the same
  words: while this destination is selected, every second factor is on screen. Someone reading the pane
  in a year should not have to go looking for the argument that was made against it.
- **The guards inside the list are untouched.** The re-prompt gate, the seed-never-shown rule and the
  `copyGated` path were never about modality — they are about what a *list of codes* may show, which is
  a question a destination raises just as loudly as a sheet.

**What was considered instead, and rejected.** Masking every code while the Vitrine window is not the
active window would have preserved the sheet's protection — and broken the feature: the reason to open a
list of codes is to read one while typing it into *another* window. A protection that makes the screen
useless for its purpose is not a protection, it is a reason not to have the feature.

## Decision 2: the rows are laid out for the column, not the sheet

The sheet was 420pt wide and put the name on the left and the code on the right. The list column is
240–340pt (ideal 262), which does not fit a name, a six-digit code, a countdown ring, a seconds figure
and a copy button on one line.

So a row is two lines: the name (and username, when there is one), then the code with its countdown and
copy control. `VerificationCodeCell` is reused as it was — it is the row's second line now instead of
its right half — because the countdown has to look the same here as in the detail pane: two screens
counting the same thing down in two different ways is a thing the user has to learn twice.

## Decision 3: selecting a row selects the item

"Like a normal item" is the ask, and the item list's behaviour is: click a row, the detail column shows
it. The pane therefore calls `viewModel.selectItem(id:)` — the method already exists — rather than
carrying its own notion of selection. A tap gesture on the row *container* rather than a button, so the
copy button inside the cell keeps its own click.

## Decision 4: leaving the destination is the dismissal

The sheet's dismiss button is gone, and so is `isShowingVerificationCodes`. What the button was for is
now the sidebar selection: enter the destination and the rows are built, leave it and
`VerificationCodesPane.onDisappear` stops them. That keeps the sheet's one genuinely good property — a
vault's worth of one-second timers does not run behind another screen — without the modality that made
the row different from every other row.

## What is verified, and what is not

- Compiles against both targets; the mock repository's `items(for:)` switch gained the case, which is
  what forces the next reader to decide what this destination *is* (it returns none: the codes are not
  an item list).
- **Not verified by a test:** that clicking a row selects the item and the detail column follows, and
  that the timers stop on leaving. Both need a running, unlocked app. The same gap the sheet had.
