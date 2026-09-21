## Context

`TOTPGenerator.code(for:at:) -> String?` is the whole generator interface today, and it is enough for
the one call site that exists: `CopyableField.totp` calls it at the moment of copying, because a code
generated when the menu was built would be a code generated at the wrong time.

Displaying the code needs two things the string cannot carry: **when it stops being valid**, and the
length of the step so the row can show progress rather than a bare number. Both are already parsed
inside `TOTPGeneratorImpl.Parameters`; neither is reachable from outside.

The row also lands in a detail view that already has a masking rule and a gate, and the interesting
decisions are about matching those rather than about drawing a countdown.

## D1 — The generator returns a window, not a code

```swift
nonisolated struct TOTPWindow: Equatable, Sendable {
    let value: String        // the zero-padded code
    let expiresAt: Date      // the instant it stops being valid
    let period: TimeInterval // the length of the whole step
}

nonisolated protocol TOTPGenerator: Sendable {
    func window(for secret: String?, at date: Date) -> TOTPWindow?
}

extension TOTPGenerator {
    func code(for secret: String?, at date: Date) -> String? { window(for: secret, at: date)?.value }
    func code(for secret: String?) -> String? { code(for: secret, at: Date()) }
}
```

**Why not a second method.** A `code(for:at:)` *and* a `window(for:at:)` would be two parsers of the
same secret with two chances to disagree about the period — and the disagreement would show up as a
countdown that does not match the code, which looks like a broken clock rather than a broken parser.
One requirement, with the old signature kept as a convenience, means the period that produced the
code is by construction the period shown beside it.

**Why `expiresAt` and not `secondsRemaining`.** A generator that returned seconds would be computing
a duration at generation time and the caller would then be rendering it later, so the number would be
stale by exactly the render latency — small, but unbounded in principle and wrong by construction.
An instant is an instant.

## D2 — The row is masked until revealed, and the gate covers it

The password row directly above is masked by default, reveals on request, and for a re-prompt-
protected item the reveal asks for the master password. A code shown openly in the same card would be
a **second, unexamined rule about which secrets may be shown** — and a worse one, because a live
code is the thing an attacker at the keyboard actually wants.

So: masked by default; for a gated item the reveal is `gate.request`, and the value shown is
`gate.isRevealed`. The masking rule itself is not re-implemented — the row uses `MaskedFieldState`,
whose `displayValue(peeking:)` is already the tested answer to "what do we print".

**A consequence worth stating:** for a gated item, the code cannot be read without answering the
prompt, which is stricter than the menu command (which also prompts, but only because it copies).
That is deliberate. Reading a code is enough to use it.

## D3 — The countdown is visible only when the code is

When masked, the row is label + bullets + the reveal control, with **no timer**. A countdown ticking
next to eight bullets is a timer for something the user cannot see, and it leaks the step boundary —
the one piece of information that is genuinely useful to an attacker with a view of the screen.

## D4 — Remaining seconds are ceiled to the boundary and never reach zero

```swift
let remaining = max(1, min(period, Int(ceil(expiresAt.timeIntervalSince(now)))))
```

Two failure modes this avoids, both of which look like a bug in the code rather than in the display:

- **`0` while the code is still valid.** A countdown showing 0 invites the user to wait for a code
  that has already rolled. `ceil` means the last second reads 1, not 0.
- **A float that lands just past the boundary** and yields `period + 1` for one tick, which a progress
  bar renders as a full bar that then jumps. Clamping keeps it inside `1...period`.

## D5 — A seed that produces no code is reported, not hidden

`LoginContent.totp` non-nil but unusable (malformed Base32, an unknown algorithm, a period of zero)
currently has no user-visible expression. The row shows the reason instead of disappearing.

Hiding it would be worse than useless: the seed *is* stored, the edit form already warns that it
produces no code, and a missing row reads as "this item has no authenticator key" — which is a
different claim, and the one that makes a user give up on the item.

This is the same call the passkeys section and the SSH agent pane make: a capability that cannot be
used says so where the user is looking.

## D6 — No Option-key peek on this row

`MaskedFieldView` supports holding Option to peek at a password without revealing it, and suppresses
the peek when gated. The TOTP row does not implement it.

The peek exists for a field the user is transcribing by hand and does not want to leave revealed. On
this row, revealing is what starts the countdown — the countdown is the reason to reveal — so the
peek would show a code with no indication of how long it lasts, which is the one thing the row exists
to add. Fewer ways to show a secret is the better default when the feature has nothing to gain.

## D7 — The code is grouped for transcription

Six digits are rendered `123 456`, eight as `1234 5678`, seven as `1234 567`. Grouping is a pure
function of the code, so it is a static on the view model and tested without rendering.

The **copied** value is not grouped. `ssh`, a browser and a paste target all want the bare digits, and
the existing `⌃⌘C` already copies them bare — the row must not introduce a second convention for the
same value.

## D8 — The tick is a timer the view model owns, with the clock injected

The view model takes `now: () -> Date = Date.init` and exposes the update as
`refresh(at date: Date)`. Tests drive `refresh(at:)` directly with fixed instants; the running app
gets a one-second `Timer` started by the view's `.task` and cancelled when it goes away.

The same shape as `VaultIdleMonitor`, and for the same reason: a countdown tested by sleeping is a
test that is slow, flaky and unable to reach the boundary cases that matter. Every boundary case here
is a specific instant.

**The timer is owned by the view model, not the view**, so the view model's `deinit` can stop it
without the view having to remember. `Timer` retains its target, so the timer holds the view model
weakly and the view model cancels in `deinit`; without one of the two the row would keep deriving
codes for the lifetime of the process.

## D9 — `hasCredentials` has to include the code

`LoginDetailView.hasCredentials` is `username != nil || password != nil`, and it hides the whole
Credentials card. An item with an authenticator key and neither a username nor a password is a real
shape — an item that exists only to hold a seed — and it would render an empty detail view.

`login.totp != nil` joins the condition.
