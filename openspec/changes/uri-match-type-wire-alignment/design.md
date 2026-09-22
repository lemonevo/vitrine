# URI match type on the wire — Design

## D1 — Explicit mapping, not a raw-value enum

`case host = 2` would have been the smaller diff. It was not chosen because the failure mode is a
*number*, and an `Int`-backed enum makes the number the definition: the next person to add a strategy
inserts a case, and everything below it shifts again, silently, with no test able to see it because both
directions move together.

`init(rawValue:)` / `var rawValue` with a `default:` arm puts the numbers in one place each, and the
`unknown(Int)` arm is what makes a future Bitwarden addition a display gap rather than a deletion.

## D2 — `.defaultMatch` is kept distinct from `nil`

The wire can say "default" two ways: `null`, or an explicit `0`. Collapsing them would turn an explicit
choice into an absent one, and the encoder-side difference is visible to Vaultwarden. `nil` stays "the
user chose nothing"; `.defaultMatch` is 0 preserved as 0. The picker shows one "Default" entry bound to
`nil`, so the distinction is invisible where it should be and exact where it is stored.

## D3 — The tests assert numbers, not round trips

`URIMatchTypeTests` states `rawValue: 2 == .host` and `.host.rawValue == 2` separately. That is
deliberately repetitive: the property that would have caught the original bug is the *value*, and a
round-trip assertion is satisfied by any mapping, right or wrong.

`CipherEncoderInvariantTests` carries `match: 6` and `match: 7` in its login fixture. Before this, its
URIs used `1` and `nil` — which round-trip identically under both the wrong and the right mapping, so
the guard that exists precisely to catch this class of loss was blind to it.

## D4 — No migration, and why that is the right call

Items Vitrine previously saved carry the shifted numbers on the server. After this change Vitrine reads them
the way every other client does — which is the truth of what the browser will act on. Re-writing them
would mean guessing what the user had meant to choose, and the app has no record of that. The
consequence is stated plainly: **a rule the user set through Vitrine's picker before this fix was never
what they asked for, and this change does not retroactively repair it.** Anyone who set a match type in
Vitrine should re-check those entries once.

## D5 — Not verified

- **No autofill was observed.** The claim "the browser reads 5 as regular expression and will autofill
  accordingly" comes from the wire contract documented in `RawURI.match` and Bitwarden's own enum, not
  from watching an extension act on a rule.
- **No server round trip.** Nothing was sent to a real Vaultwarden; the assertions are on the encoded
  body. A live item with `match: 6` set in the web vault, opened and re-saved by Vitrine, is the check
  still outstanding.
- **Old exports.** A JSON export written by a previous build contains the shifted numbers. They will now
  be read as their literal values, which is what any other client would do with them. Not tested.
