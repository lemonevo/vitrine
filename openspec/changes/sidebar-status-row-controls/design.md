# Sidebar status row — Design

## Decision 1: the refresh moves to the leading end, it is not doubled beside the gear

The row has to hold three things in 216pt minus 40pt of horizontal padding. Two arrangements were
possible:

| | Result |
|---|---|
| `[status] …… [refresh] [gear]` | Keeps the refresh where it was, and puts the two controls side by side at the trailing end. Both actions read as one group, but the group is the only thing at that end and the status keeps the leading half to itself. |
| `[refresh] [status] …… [gear]` | Each end owns one action. The refresh is at the far end from the gear, so the two cannot be mistaken for a pair that belongs together. |

The second is what was asked for, and it also repairs the smaller defect above: with the refresh
leading, it is adjacent to the label it refreshes, which is the property the control was moved out of
the titlebar for. "Beside the state it refreshes" becomes true of the layout and not only of the
intent.

**Why not the first.** It is the smaller diff — one new control and nothing moved — and that was the
argument for it. It loses on reading: two glyph buttons touching at the end of a row, one of which
syncs and one of which opens a window, look like a segmented pair. Nothing about them is related.

## Decision 2: the status label is held to one line

`Spacing.sidebarHorizontal` is 20pt, so the row has 176pt to work with. The refresh glyph, the gear
and the two 8pt gaps take roughly 44pt, leaving about 132pt for the label.

- English `"Synced 2 minutes ago"` at `Typography.listSubtitle` (11pt) needs most of that, and at the
  sidebar's real 216pt it **wrapped onto a second line** — visible in the rendered probe.
- Chinese `"同步于 2 分钟前"` is about half the width and was never close to wrapping, which is why
  the defect is invisible in the language the author reads.

A row whose height depends on which of the two supported languages is in force is the kind of defect
that survives review, so it is closed here rather than noted: `.lineLimit(1)` with
`.minimumScaleFactor(0.85)`. The label shrinks by at most 15% instead of wrapping.

**Truncation was the other candidate and it is worse.** The label *is* the row's content; losing its
tail loses the answer ("Synced 2 minu…" tells the user nothing they can act on). Shrinking keeps every
character, and 11pt → 9.35pt at the worst is still legible at this size.

## Decision 3: the entry point is resolved, not constructed

`@Environment(\.openSettings)` in `VaultBrowserView` hands the button the app's existing `Settings`
scene. The alternative — a second window built and shown by hand — would be a second thing to keep in
step with the scene, and the two routes would eventually disagree about which window is "Settings".
The button and ⌘, now reach the same object by construction.

## What was checked, and how

- **The rendered row is the real one.** `SyncStatusView` is internal, so the probe supplies it
  directly — no private control had to be copied, which is the fidelity problem the toolbar shots
  carry and this one does not.
- **The layout was measured, not eyeballed**: the token values above were read out of
  `DesignSystem.swift`, and the wrap was confirmed by rendering the English string at 216pt.
- **Both languages were considered.** The Chinese label was checked against the same budget, which is
  what established that this is an English-only regression.
