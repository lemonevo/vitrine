# Item actions in the detail header — Design

## D1 — The rule, stated once

Toolbar = commands about the window and the vault (settings, sidebar, sort order, sync, new item).
Detail header = commands about the selected item (favourite, edit).

The test I applied to each control: *does it still mean the same thing when nothing is selected?* ⚙
does. Edit does not — it is disabled-by-absence, and that is the tell that it belongs to the item.

## D2 — The star becomes a control, and the display glyph goes away

The header had `if item.isFavorite { Image("star.fill") }` — a picture, not a button, while the
toolbar held the real toggle. Showing state twice, once inert, is worse than showing it once: a user
who clicked the header star and got nothing would conclude the app is broken.

So the header's star is now the toggle, and it renders empty-and-secondary when unfavourited. That is
a visible change for unfavourited items (an extra grey star where there was nothing), which is the
price of the control being discoverable at all — `toggle-favorite` already requires the empty star in
the toolbar, so the affordance was always meant to be there.

## D3 — Where the rule is knowingly broken: the trash

Restore and Delete Permanently are item-level commands and stay in the toolbar.

Three reasons, in order of weight: they are a *pair*, and splitting them across two surfaces would
separate a destructive action from its safe alternative; `destructive-action-styling` governs how the
destructive one is drawn, and that requirement is written against the toolbar; and Trash is a place
you visit, not the pane you work in, so the shape-change problem that motivated this — a titlebar that
redraws itself as you browse — does not bite.

If this ever gets unified, the whole pair moves together and the destructive-styling spec moves with
it.

## D4 — One countdown drawing, not two

`CountdownRing` was a private computed view inside `TOTPCodeView`. The verification-codes list needs
the same thing, so it is now a file-scope view in that same file rather than a copy, and rather than a
new file: the ring is the TOTP countdown's shape, and a `Components/CountdownRing.swift` would need
registering in `project.pbxproj` for a 20-line view that has no business being used by anything that
is not counting a TOTP step down.

The list previously used `ProgressView(value:)`, which is not wrong so much as unreadable at a glance:
a bar a third full is a shape, and the user has to already know the step length to turn it into a
number. The ring plus `28s` states the number.

`Spacing.codesCountdownWidth` (26pt) exists so the copy button does not slide sideways as the seconds
count from 10 to 9. That is the same reason the detail pane's number is monospaced-digit.

## D5 — `Edit` was never localised

`Button("Edit")` in the toolbar took a string literal, so `L("Edit")` — "编辑" — never ran. Moving the
button was the moment it surfaced; the fix is one word. The other two toolbar buttons in that block
(`"Restore"`, `"Delete Permanently"`) are literals too and are **not** fixed here, because they are
outside the scope the user chose. They are listed in tasks §5 rather than left for the next reader to
find.

## D6 — A ticking view cannot be tested by waiting for it

The screenshot harness drives the UI with `RunLoop.current.run(until:)`. That pumps **timers**, but a
timer block that hops with `Task { @MainActor … }` lands on the main dispatch queue — and the test
method is itself a block on that queue, so the continuation cannot run until the test returns. Verified
by measurement rather than by argument: a plain `Timer` fired four times in two seconds in exactly this
situation while the view model's `secondsRemaining` did not move at all.

So `testCodesCountdownReachesTheView` does not wait. It captures one window, calls `refresh(at:)` on
every row's view model with a date six seconds on, spins the run loop long enough for SwiftUI to redraw,
and captures again. The only variable left is whether a model change reaches this view — which is the
thing that was broken.

Two windows would not have worked, and that is how the first attempt at this test passed with the defect
still in place: each window builds its own view model at its own moment, so two fresh windows differ
for reasons that have nothing to do with ticking. Comparing them proved nothing and looked like proof.

## D7 — Not verified

- **The toolbar after the change was not captured.** The design variants were rendered from a mock
  `NavigationSplitView` (which, usefully, does produce a real AppKit toolbar in a hand-made window),
  and the production `VaultBrowserView` needs a fully wired view model the screenshot harness does not
  build. What is verified is the code change and the detail header's own render; that the titlebar now
  shows five controls has to be looked at in the running app.
- **VoiceOver was not run** on the new header cluster, so the announcement order — star before Edit,
  both after the name and breadcrumb — is inferred from the view order, not heard.
- **⌘E was not pressed.** The shortcut moved with the button; whether it still fires when focus is
  inside the list, the search field, or an open sheet is unchanged behaviour I could not exercise here.
