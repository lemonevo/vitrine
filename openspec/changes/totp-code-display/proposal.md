## Why

Prizm can already derive a one-time code and copy it — `Item ▸ Copy Code` (⌃⌘C) generates from the
stored seed and puts the *code* on the clipboard, which is the fix that stopped it copying the seed
itself. What is missing is that the code cannot be **read**. The only way to see it is to copy it,
which is a round trip through the menu and, on a re-prompt-protected item, a master-password prompt
— to look at a number that expires in thirty seconds.

The detail view also gives no sign that an item has an authenticator key at all. `LoginContent.totp`
is populated and carried through sync, and its doc comment still says it is "never displayed in v1",
so the field is invisible to the user in every sense.

`FEATURE-GAP-ANALYSIS.md` records this as the one remaining TOTP gap: the generator, the seed
editing, the gate and the menu command all exist; the display does not.

## What Changes

- The login detail view gains a **Verification code** row in the Credentials card, showing the
  current code with the seconds it remains valid and a progress indicator for the time step.
- The code is **masked until revealed**, exactly like the password row above it. For an item that
  carries re-prompt protection the reveal goes through the master-password gate, so the row cannot
  become a way to read a protected secret without answering the prompt.
- **Copying the code from the row goes through the same gate as ⌃⌘C.** A row that copied without it
  would be the menu command's gate walked around in one click.
- The code is recomputed **once per second while the row is on screen**, from the stored seed. The
  timer stops when the row goes away, so nothing is being derived for an item nobody is looking at.
- A stored value that cannot produce a code is **reported** rather than silently omitted — the seed
  is present, and an absent row would read as "this item has no authenticator key".
- `TOTPGenerator` gains the **validity window** (`value`, `expiresAt`, `period`) instead of only the
  code, because a countdown cannot be derived from a string. The existing `code(for:at:)` becomes a
  convenience over the new method, so there is one implementation and one parser.
- `LoginContent.totp`'s doc comment is corrected: it now says the field is displayed, and where.

## Non-goals

- **Registering** a TOTP secret with a service. Prizm reads a seed the user pasted in; it does not
  perform enrolment.
- **Steam / Yandex / other non-RFC variants.** The generator supports what RFC 6238 defines plus the
  Key URI Format parameters; anything else still yields no code.
- Changing `⌃⌘C`'s behaviour. It keeps generating at the moment of copying.

## Capabilities

### New Capabilities

- `totp-code-display`: showing a login item's current one-time code in the detail view, with its
  remaining validity, behind the same masking and gate rules as the item's password.

### Modified Capabilities

_None._

## Impact

- `Prizm/Domain/Repositories/TOTPGenerator.swift` — the window type and the new requirement
- `Prizm/Data/Crypto/TOTPGeneratorImpl.swift` — returns the window; exposes the parsed period
- `Prizm/Presentation/Vault/Detail/TOTPCodeViewModel.swift` — **new**; the tick and the derived state
- `Prizm/Presentation/Vault/Detail/TOTPCodeView.swift` — **new**; the row
- `Prizm/Presentation/Vault/Detail/LoginDetailView.swift` — the row, and `hasCredentials`
- `Prizm/Presentation/Vault/Detail/ItemDetailView.swift`, `VaultBrowserView.swift` — pass the factory
- `Prizm/App/AppContainer.swift`, `Prizm/App/PrizmApp.swift` — build the view model
- `Prizm/Presentation/AccessibilityIdentifiers.swift` — identifiers for the row
- `Prizm/Domain/Entities/VaultItem.swift` — the `LoginContent.totp` doc comment
- `Prizm/Resources/{en,zh-Hans}.lproj/Localizable.strings` — new strings
- `Prizm/PrizmTests/Mocks/MockRootDependencies.swift` — `StubTOTPGenerator` follows the new method
