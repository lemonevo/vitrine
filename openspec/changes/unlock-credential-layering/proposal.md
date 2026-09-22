# Unlock credential layering and legible secondary text — Proposal

## Why

The unlock screen showed a master-password field and a PIN field stacked at the same weight, with
nothing on the screen saying which one to use, and the PIN's remaining-attempts line sitting under
both. The consequence is a specific kind of lie: type a wrong *master password* and the screen tells
you "4 attempts left before the PIN is removed" — a count of something you were not doing.

The second problem is measured rather than felt. Running the resolved system colours through the WCAG
relative-luminance formula on this Mac (`xcrun swift`, light and dark aqua, against both the window and
control backgrounds):

| Foreground | Light | Dark | AA (4.5:1) |
|---|---|---|---|
| `labelColor` | 14.94:1 | 12.23:1 | pass |
| `secondaryLabelColor` | **3.95:1** | 5.89:1 | **fails in light** |
| `tertiaryLabelColor` | **1.88:1** | **2.26:1** | fails in both |
| `systemOrange` | **2.31:1** | 7.47:1 | fails in light |

Those greys are what the entry screens use for copy a user has to act on: the field hint
("Required. For example …"), the sentence under the login card that states the master password never
leaves the machine, the field labels, the unlock subtitle, and the PIN attempt count in orange. At
10–13 pt that is text, not decoration, and `ACCESSIBILITY.md` claims WCAG 2.1 AA for this interface.
The claim and the numbers cannot both stand.

Third: both entry screens disabled their own primary button until every field was filled. A screen
whose single action looks inert for the whole time the user is filling the form teaches them it is not
for them — and on the login screen the field that was missing (the server address, at the bottom, below
a rule) was the one nobody would guess to look at.

## What changes

- **One credential at a time.** The unlock screen asks for one thing — whichever opened the vault last
  time *on this launch* — and names the alternative as a switch under the field. The subtitle, the
  field label, the attempt count and the submission all follow that one value.
- **The shortcut is earned, and never written to disk.** `UnlockCredentialPreference` lives in
  `AppContainer` for the length of the process. Default is the master password; a PIN becomes the
  default only after it has actually unlocked the vault. See design D2 for why this is not persisted.
- **The primary action is live; an incomplete submission is answered.** The view model names the first
  missing field, the banner says what it is, and the insertion point moves to it.
- **`Foreground.muted` = `Color.primary.opacity(0.62)`** — 6.20:1 light, 7.13:1 dark, one value that
  clears AA in both appearances. **`Foreground.warning`** resolves per appearance (`#8C4700` light /
  `#E9A23B` dark) because no single amber passes in both (2.39:1 / 2.17:1 the wrong way round).
- Spacing literals on the entry screens (`12`, `14`, `16`, `6`, `34`) become named tokens.

## Deliberate limits

- The login screen's *layout* is unchanged. Its field order was argued in `auth-screens-redesign` and
  is not what this fixes.
- The list, sidebar and detail panes are untouched — the site-identity list direction
  (`MainWindowProposalV2`) is its own change.
- No new colours are introduced anywhere except the two foreground tokens.

## Impact

- Affected specs: `unlock-credential-choice` (new), `accessibility-contrast` (one ADDED requirement —
  it currently covers background tints and borders at 3:1 and says nothing about text).
- Reconciliation owed at archive time: `openspec/specs/biometric-unlock/spec.md:14` mandates the
  subtitle wording, and `openspec/changes/pin-unlock/specs/pin-unlock/spec.md:3` describes the PIN as a
  second field. Both are written against the two-field screen. The password-mode wording is preserved
  exactly, so `biometric-unlock` still holds; `pin-unlock`'s does not and needs its delta reworded
  before either change is archived.
- 11 new view-model tests, 5 new strings in each table, one new production type.
- Suite: see tasks §6 for the recorded run.
