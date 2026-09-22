# Small parity completions — Design

## The username shape

`word.word<digits>` — two words from the EFF list and a short run of digits. Three properties decided
it:

- **Typable.** A username is often said aloud or typed on a phone; `correct-horse-42` is, and a
  base64 blob is not. The generator's job here is a *suggestion* the user may keep or edit, not a
  secret to be memorised.
- **Not a secret.** Unlike the other two modes this value needs no entropy argument, because sites
  treat usernames as public. So the words are drawn plainly from the same list rather than from the
  password alphabet, and the digit count is small — a long random string would be security theatre on
  a value that is displayed.
- **Distinct from the passphrase mode.** That one is a secret and is shaped accordingly (six words by
  default, separator configurable). Sharing the list is fine; sharing the *configuration* would not
  be, so the username mode has its own.

The word list is `PasswordGenerator.effWordList`, already vendored for the passphrase mode. No new
data, no new dependency.

## Why the Trash notice refuses to name a number

The purge interval lives in the server's configuration. Prizm's sync response does not carry it and no
endpoint Prizm implements returns it, so any figure printed here would be a guess about a deployment
the client cannot observe.

A guessed number is not a harmless approximation: it is the number a user would plan around when
deciding whether an item "is fine in the Trash for now". Saying that the deletion is automatic, and
not saying when, is the honest half of the information and the half that changes behaviour.

## Verification

- The username mode produces a value from the configured word list, with the configured digits, and
  does so deterministically when the randomness provider is stubbed — the same seam the other two
  modes use.
- The generator's other two modes are unchanged.
- The Trash notice appears when there is something in the Trash, and not when it is empty.
