# Remember two-factor device — Design

## Decision 1 — keyed by email, stored globally, matched on replay

The token belongs to an account, but at login time Prizm knows only the **email** — the user id comes
back in the token response, after the challenge has already been decided. So a per-user key
(`bw.macos:<userId>:…`, the convention every other session item uses) cannot be looked up at the moment
it is needed.

Two global keys instead: the token, and the email it belongs to.

The email is not decoration. Replaying account A's remembered token for account B would be handing the
server a credential for the wrong account — the outcome depends on the server, and there is no reason
to send it. The stored email is compared against the login email, trimmed and case-insensitively,
because that is the same normalisation the rest of the login path uses.

**A global key is safe here because the app is single-account.** One active session, so at most one
remembered device. If multiple accounts are ever added, this becomes per-account and the email match
turns into an exact lookup — worth stating so it is not rediscovered.

## Decision 2 — the failure to store is logged, not swallowed

`rememberDevice: true` with no `twoFactorToken` in the response means the checkbox did nothing again,
in a different way. That is logged at `error`.

The user is not shown anything: they will find out at the next login, and a banner about a token they
never saw would be noise. But an inert control that also leaves no trace is how this got shipped the
first time.

## Decision 3 — the token is stored only when the user asked

Storing it unconditionally would be worse than the bug: a user who deliberately did *not* tick the box
would silently get a remembered device. The response carries a token either way, so the flag is what
decides.

## Decision 4 — lock on sleep stays unconditional

Recorded here because it was in the same batch and deliberately not changed.

The official client lets "On system lock" and "On system sleep" be selected as timeout modes, which
means a user who picks `Never` does not get locked by closing the lid. Prizm locks on
`willSleepNotification`, the screensaver, and screen lock regardless of the timeout setting
(`PrizmApp.swift:603-621`).

That is **stricter than the official client, and it is a protection rather than a deficiency.** A vault
timeout is the thing a user configures to protect a walked-away machine; the lid closing is the most
common way a machine is walked away from. Making this configurable would be parity in the dropdown and
a weaker guarantee in fact — and the guarantee is one `SECURITY.md` describes in terms of what a locked
session leaves behind.

Left as-is. If it is ever revisited, it needs its own change and its own security note, not a row in a
settings list.

## Verification

The unit tests drive the whole path through the real repository with a Keychain double and an API
double: the token is stored on a remembered login, replayed on the next login for the same email, not
replayed for a different one, not stored when the box was unticked, and removed on sign-out.

What they cannot show is the server's side — that a replayed token actually suppresses the challenge.
The manual check is: tick the box, sign out, sign in again, and confirm no code is requested.
