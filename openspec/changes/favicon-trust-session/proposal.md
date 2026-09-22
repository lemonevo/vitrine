# Favicon trust session — Proposal

## Why

Every login row in the vault shows the same fallback key glyph, and has apparently always done so.

`AppContainer` built the icon loader as `FaviconLoader()`. That parameterless form resolved to
`URLSession.shared`, while the API client is built on a private `URLSession` carrying
`ServerTrustDelegate` — the delegate that makes a self-hosted Vaultwarden with a non-system
certificate work at all.

So the icon request and the API request go to **the same host** over **two different sessions**, and
only one of them knows how to trust that host. Against such a server every `/icons/...` fetch fails
TLS validation.

What makes this invisible is a deliberate design decision elsewhere: `FaviconLoader` treats all
failures as "show the placeholder", because a password manager must not raise an alert over an icon.
That is the right behaviour and it is also why the defect produced no symptom anyone could act on —
not an error, not a log line anyone read, just a uniformly greyer vault.

This was written while that defect was believed to be why one account shows no icons. It is not — see
"What this does not claim" below. The defect stands on its own.

## What changes

- `FaviconLoader.init`'s `session` parameter **loses its default**. `FaviconLoader()` no longer
  compiles, so the wrong value cannot be reached by omission again.
- `AppContainer` passes the same session it gives the API client, with a comment at the call site
  saying why it must be that one.
- `PrizmAPIClientImpl.init` gets the same treatment for both `session` and `trustDelegate`: no
  defaults. It was already wired correctly; the defaults were the same latent trap waiting for a
  second call site.

## What this does not claim

**This was not the cause of the missing icons. That hypothesis was tested against the account's own
server and is dead.**

Probing `https://vault.example.com` directly:

| Path | Result |
|---|---|
| `/api/alive` | **200** JSON — the API is reachable, and lives under `{base}/api` |
| `/icons/google.com/icon.png` | **404**, body is the Bitwarden **web vault SPA**'s "Page not found" |
| `/api/icons/google.com/icon.png` | **404**, empty body — a different 404, from the proxy upstream |
| TLS | verifies clean; served by Cloudflare |

So the certificate was never the problem, and the icon service simply is not reachable at the URL
Prizm builds. Prizm's construction — `ServerEnvironment.iconsURL` = `{base}/icons`
(`Account.swift:28`) — is the canonical Bitwarden/Vaultwarden path, so this is a server-side routing
choice: the reverse proxy exposes Vaultwarden under `/api` and leaves `/icons` to the web vault's
static catch-all.

The change stays, because the defect it fixes is real independent of this account: two network paths
to one host must not differ in trust, and on a deployment whose certificate *does* need pinning the
old wiring would have failed exactly as described. What it does not do is explain this vault.

## The consequence that matters

There is no in-app way to point the icon service elsewhere. `ServerURLOverrides.icons` exists on the
model but is always `nil` in production and has no UI — recorded in
`FEATURE-GAP-ANALYSIS.md` §3. So a user on this style of deployment cannot turn icons on from inside
Prizm at all, and **the item list has to be designed assuming favicons are absent.**

## Non-goals

- **Surfacing icon failures to the user.** The silent degradation is correct and stays.
- **A retry or diagnostics screen** for the icon service.
- **An icons-URL override UI.** Real, and now demonstrably useful — but it is its own change.
- **Any change to how icons are rendered** — the layout work is in `ui-redesign`.
