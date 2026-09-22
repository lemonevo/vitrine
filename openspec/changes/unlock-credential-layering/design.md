# Design — unlock credential layering

## D1. One field, not two

**Decision.** The screen asks for exactly one credential. Everything that could describe "which one"
derives from a single value, `UnlockViewModel.credentialMethod`.

**Why.** With two fields at equal weight, the attempt count — which counts PIN failures only — had
nowhere correct to sit. Under the PIN it is invisible to someone using the password; under both, as it
was, it reports a limit for the wrong input.

**Considered and rejected.**

- *Left/right split of the two fields.* Still two questions on screen, and the count still has no
  single owner. Rejected before it was drawn.
- *A/B/C were drawn, not argued.* `UnlockCredentialLayering` (a throwaway probe in the test target)
  rendered three directions in a real `NSWindow` — A: password first with PIN behind a link; B: an
  explicit `PIN | Password` segmented control; C: default to the last method that worked. The render
  is what settled it, because two of the three had a defect that only showed up as a picture:
  - **A says the wrong thing in its failure state**: the attempts line appears under a *master
    password* field, because A's default never moves and the user who keeps failing is failing on a
    PIN the screen is not showing.
  - **B's subtitle contradicts its own selection.** In the drawing, with PIN selected, the header still
    read "Enter the password for …". That is not the mock being sloppy — it is B's state surface: the
    subtitle, the field label and the button must all follow the picker, and every one of them is a
    place to be wrong. B also puts a solid blue segment beside a solid blue primary button, i.e. two
    primary actions on one screen.
  - C is self-consistent at rest and after a failure, and its switch link is always visible, so the
    mode is not hidden state.

## D2. The preference is per-launch and never persisted

**Decision.** `UnlockCredentialPreference` is a reference type held by `AppContainer`; it records the
credential that last *succeeded*, and only for the life of the process.

**Why not disk.** A stored "this user unlocks with a PIN" is a hint, available to anyone holding the
machine, that a four-digit code rather than the master password is the gate in front of these secrets.
That is the opposite of what a short code is for. In-memory also means the default after a restart is
always the strongest of the two, and the shortcut appears only once the user has proven it on this
launch — which lines up with `AuthRepository.pinUnlockAvailable`, already refusing a PIN on a freshly
restarted app until something has authenticated in full.

**Why not the view model.** `RootViewModel` builds a new `UnlockViewModel` on every lock
(`PrizmApp.swift:803`), so per-launch state cannot live there. Same reason `SessionEpoch` is owned by
the container.

**Considered and rejected.** *Always default to the master password* (variant A's rule). Costs the PIN
user a click on every unlock, which is the everyday path they chose, and it is the reason A's failure
state has nowhere to put the count.

## D3. Switching carries nothing between the fields

`toggleCredentialMethod()` clears the error and flips the ask; the text already typed stays where it
was typed. Pushing a PIN through the password path would be a wrong-master-password attempt the user
never meant to make, and the two fields are separate `String`s precisely so one cannot be cleared by
the other's success.

## D4. A live button that answers, rather than an inert one that prevents

**Decision.** Neither entry screen disables its primary button for empty fields. The view model returns
the first missing field, the banner names it, and `fieldRequiringAttention` moves the insertion point
to it. The button is disabled only while a submission is actually in flight, and shows a spinner then.

**Why.** `.borderedProminent` in its disabled state renders as a grey pill with grey text — on the
shipped screen that was the appearance of the primary action from launch until the last character was
typed. `error-placement` and `focus-management` both want the answer near the field, not the removal of
the control.

**Considered and rejected.** *Keep the disabled button and add a hint under it.* macOS does disable
submit controls often, but here the disabled state was not "this is unavailable", it was "you have not
finished", which is a fact about the form the user was in the middle of filling.

## D5. Text contrast is a token, and one value covers both appearances

`Foreground.muted` is `Color.primary.opacity(0.62)`: 6.20:1 in light, 7.13:1 in dark, on both the window
and the control background. It needs no `colorScheme` branch because `Color.primary` itself resolves
per appearance — which is exactly what `.secondary` fails at (3.95:1 light, 5.89:1 dark).

The warning colour cannot be one value: `#8C4700` is 6.97:1 on a light surface and 2.39:1 on a dark
one, and `#E9A23B` is the reverse (7.69:1 dark, 2.17:1 light). So `Foreground.warning` is an
`NSColor(name:dynamicProvider:)` that picks at draw time from the effective appearance. This was found
by rendering the recommended variant in dark aqua — the amber chosen to fix the light-mode failure was
almost invisible in the mode it was not measured in.

Neither colour is ever the only signal: the attempts line carries a warning glyph and plain words.

## D6. Four whole-sentence localisation keys for the subtitle

The subtitle is a function of `(credentialMethod, biometricName)`, so it has four cases. They are four
complete sentences in both tables, not a prefix spliced onto a verb phrase — word order and the
position of the email are not portable between languages, and the existing
`"%@ or enter the password for %@ to unlock."` key is kept verbatim so the
`biometric-unlock` spec's mandated wording still holds in password mode.
