## T1. `TOTPGenerator` returns a window

- [x] Add `TOTPWindow` (`value`, `expiresAt`, `period`) to `Prizm/Domain/Repositories/TOTPGenerator.swift`.
- [x] Replace the protocol requirement with `window(for:at:)`; keep `code(for:at:)` and `code(for:)` as
      protocol-extension conveniences so the two existing call sites do not change.
- [x] `TOTPGeneratorImpl` returns the window. `expiresAt` is the next multiple of `period` strictly
      after `date` — computed from the same counter that produced the code, not from a second
      division.
- [x] Document that the period returned is the one that produced the code, which is the reason there
      is one method rather than two (design D1).

## T2. `TOTPCodeViewModel`

- [x] **New** `Prizm/Presentation/Vault/Detail/TOTPCodeViewModel.swift`, `@MainActor`,
      `ObservableObject`.
- [x] State: `code: String?`, `displayCode: String?` (grouped), `secondsRemaining: Int?`,
      `remainingFraction: Double`, `isUnusable: Bool`.
- [x] `init(itemId:secret:generator:now:)` with `now: () -> Date = Date.init` (design D8).
- [x] `refresh(at:)` as the testable update; `start()` / `stop()` for the timer; `deinit` stops it.
- [x] `remainingSeconds(until:at:period:)` and `grouped(_:)` as `nonisolated static` pure functions so
      the boundary cases are testable without a clock (designs D4, D7). `tickInterval` and
      `boundaryOffset` are `nonisolated static let` for the same reason.
- [x] The code is recomputed from the secret on every refresh, never extrapolated from the previous
      code — HMAC gives no way to advance a code, and a cached code past its step is a wrong code.

## T3. `TOTPCodeView`

- [x] **New** `Prizm/Presentation/Vault/Detail/TOTPCodeView.swift`.
- [x] Masked state: label + `MaskedFieldState.maskedPlaceholder` + reveal control, **no countdown**
      (design D3).
- [x] Revealed state: grouped code in a monospaced font, seconds remaining, and a progress bar for
      the step.
- [x] Reveal is `gate.request` when `gate.isGated`; the displayed value is `gate.isRevealed`.
- [x] Copy goes through `gate.copyGated` when gated, and copies the **ungrouped** code (design D7).
- [x] Unusable seed: the reason, in place of the code (design D5).
- [x] Accessibility: the code element announces the digits spelled out; the countdown is a separate
      element so the code's announcement does not change as the seconds tick.

## T4. Wiring

- [x] `LoginDetailView`: a `makeTOTPCodeViewModel` factory, the row inside the Credentials card after
      the password, and `hasCredentials` extended to include `login.totp` (design D9).
- [x] `ItemDetailView` and `VaultBrowserView`: carry the factory down.
- [x] `AppContainer.makeTOTPCodeViewModel(itemId:secret:)`; `PrizmApp` passes it.
- [x] Correct `LoginContent.totp`'s doc comment — it said "never displayed in v1", which is now false.
- [x] Accessibility identifiers for the row, its value, its mask, its reveal control and its
      unusable state (`AccessibilityID.TOTP`).

Two lifecycle details the plan did not anticipate, both of which would have been silent:

- **The row's task is keyed on `(itemId, secret)`, not on the item id.** An edit can replace the
  stored key for the same item, and a task keyed on the id alone would not re-run — the row would go
  on deriving codes from the key the user had just replaced.
- **The row restarts its timer on the view model *instance*, not on `itemId`.** For the same reason:
  a replaced key is a new view model with an unchanged id, and `onChange(of: itemId)` would not fire.
  A row that never started is a row that never updates.

## T5. Localisation

- [x] New keys into both `.lproj` files via `add_strings.py`, then `verify_keys.py` must report PASS.
      5 keys added, 521 → 526 in both, `git diff --numstat` shows 5/0 per file.

## T6. Tests

- [x] `TOTPCodeViewModelTests`: the window boundary in both directions, the last second reading 1 and
      never 0, the step rolling over, grouping for 6/7/8 digits, an unusable secret, and that
      `start()`/`stop()` drive and halt the refresh.
- [x] `TOTPGeneratorTests` (existing file — named for the impl, not the protocol): `expiresAt` is the
      next boundary strictly after the instant, `period` matches the Key URI parameter, and a code
      generated at `expiresAt - 1s` differs from one generated at `expiresAt`.
- [x] A test asserting the copied value is the code and not the seed, so the historical defect cannot
      come back through the new path.

## T7. Verify

- [x] `swift build --build-tests --disable-sandbox` clean, with `PrizmTests` in the log.
- [x] Full suite: 1211 tests / 10 assertion failures, the same 9 pre-existing cases as the baseline
      (asset catalog and word list absent from the SwiftPM test bundle), 0 unexpected.
- [x] Both `.lproj` at equal key counts (526), `plutil -lint` clean, `git diff --numstat` showing only
      additions.
- [x] Screenshot the detail view in both languages with a real TOTP item: masked, revealed, and one
      second before the step rolls. **Confirmed by the user on a running build** (2026-09-21) — the
      row renders, reveals and counts down against a real vault item. Static checks passing is not
      the same as the row looking right, which is why this step existed.
