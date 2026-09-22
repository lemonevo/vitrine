# Favicon trust session — Design

## D1 — Remove the default rather than add a test

The obvious guard is a test asserting the loader and the API client share a session. It was rejected
for two reasons.

It would need `AppContainer` to be constructible in a test. Nothing constructs it today: it opens
keychain services, builds the SSH agent coordinator and creates the vault cache directory. A test
whose first job is to make that safe to instantiate is a larger change than the bug.

And it would test the wiring rather than the shape. With `session` defaulted, the wrong value is one
forgotten argument away in any future call site; with no default, it has to be typed out as
`.shared`, which is a decision someone writing that line can see they are making.

So the enforcement is the type signature. The comment at the one production call site carries the
reason.

## D2 — Apply it to the API client too

`PrizmAPIClientImpl.init(session:trustDelegate:)` had defaults for both parameters and was already
being called correctly. Left alone, the codebase would contain two network constructors where one
silently opts out of certificate trust and the other does not — and the difference would be invisible
until someone hit it. Both are now required arguments.

## D3 — Silent degradation stays

`website-icons` requires that a failed fetch returns nil and shows a placeholder, without an alert.
That behaviour is what hid this defect for however long it has been in, and it is still the right
call: an icon host being down is not worth interrupting somebody unlocking their vault.

The fix therefore does not make failures visible. It makes one particular failure not happen, which
is the version of "noticeable" that costs the user nothing.
