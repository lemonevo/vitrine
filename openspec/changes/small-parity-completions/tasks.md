# Small parity completions — Tasks

> **Prerequisite:** `openspec/changes/fix-test-target-buildability/`.

## 1. Username generation

- [x] 1.1 Failing tests for `UsernameGenerator`: it uses the configured word list, produces the
      configured number of words and digits, and is deterministic under a stubbed provider.
- [x] 1.2 Failing test: the separator shape matches what the generator documents.
- [x] 1.3 `UsernameGenerator` in `Prizm/Domain/Utilities/`, taking the word list and randomness
      provider the way `PasswordGenerator` does.
- [x] 1.4 `PasswordGeneratorConfig.Mode` gains `.username`, with its own word/digit settings — it must
      not reuse the passphrase's word count, which is a secret-length decision.
- [x] 1.5 Failing test: switching to the username mode does not disturb the other two modes' settings.
- [x] 1.6 `PasswordGeneratorViewModel` generates for the mode; the view offers it and shows the
      controls for it.
- [x] 1.7 Failing test: the value is copied through the same clipboard path as the other modes, so the
      clear timer applies to it too.

## 2. Trash notice

- [x] 2.1 Failing test: the notice is present when Trash has items.
- [x] 2.2 Failing test: it is absent when Trash is empty — an empty Trash has nothing to warn about.
- [x] 2.3 The notice says the deletion is automatic and gives no interval, with a comment recording
      why: the interval is a server setting Vitrine cannot read.
- [x] 2.4 Strings in both language files.

## 3. Verification

- [x] 3.1 Full suite green except the baseline recorded in `fix-test-target-buildability`.
- [x] 3.2 Manual: generate in each of the three modes and confirm the values are what the controls say.

> **3.2 is outstanding** — it needs a running signed app. The generator's three modes and the Trash
> notice are covered by `UsernameGeneratorTests`, `GeneratorModeIndependenceTests` and the existing
> trash suite; what is unverified is how the controls look and that the notice renders in the right
> place.

> **A test bug worth recording.** `testGenerated_usesWordsFromTheList` failed on first run because it
> split the value on `.` and treated every component without a digit as a word — but the digits are
> appended to the *final* word (`abacus.bucket2345`), so the last component looked like a word that was
> not in the list. The generator was correct and the assertion was wrong. The fix strips a trailing
> digit run before comparing.
