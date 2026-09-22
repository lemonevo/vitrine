# Favicon trust session — Tasks

## 1. Fix

- 1.1 `FaviconLoader.init`: drop the `session` default; document why the parameter is required (D1).
- 1.2 `PrizmAPIClientImpl.init`: drop the defaults on `session` and `trustDelegate` (D2).
- 1.3 `AppContainer`: pass the API session to `FaviconLoader`, with the reason at the call site.
- 1.4 Update the three test/harness call sites that relied on a default.

## 2. Verification

- 2.1 App target builds with no defaulted session anywhere — the compiler is the guard.
- 2.2 Full `PrizmTests` suite: 1446 passed, 0 failed.
- 2.3 Probed against the account's server: `/api/alive` 200, `/icons/...` 404 (web-vault SPA page),
      `/api/icons/...` 404 (empty), TLS verifies clean. **The session defect is not the reason this
      vault has no icons** — see proposal, "What this does not claim".
- 2.4 Still to confirm by eye: nothing. The icon absence is server-side routing, and no in-app
      setting would change it.

## 3. Deliberately not done

- 3.1 No test constructing `AppContainer` to assert session identity — see design D1 for why the
      type signature was chosen over the test.
- 3.2 No change to silent degradation of icon failures (D3).
