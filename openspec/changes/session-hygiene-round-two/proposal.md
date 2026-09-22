# Session hygiene, round two — Proposal

## Why

Four defects found while answering "can this ship", all of the same family: **state that outlives the
thing that justified it** — a per-process default that should have been per-account, key bytes that
should have been zeroed, plaintext that should have gone when the app did, and a dialog that promised
more than the code does.

Three of the four are recorded in the running defect inventory (`§7`, `§8`, `§9`); the first is a
regression this repository introduced the same day, in `unlock-credential-layering`.

## What changes

**1. The unlock credential default is per account, not per process.**
`UnlockCredentialPreference` keyed a single value for the whole launch, so account A unlocking with a
PIN handed that default to whoever signed in next. It is now keyed by account email — the same identity
`SyncTimestampRepositoryImpl` scopes by — and the doc comment says why a global flag on a security
screen is the wrong shape. Covered by `testDefault_isNotSharedBetweenAccountsOnTheSameLaunch`.

**2. The login and unlock paths zero what they derive.**
`loginWithPassword` derived a master key and never discarded it, under a comment that claimed the
`Data` form existed "so we can zero it after the KDF call". Both it and `unlockWithPassword` now
`defer` the discard, which also covers the throw paths — a wrong master password is precisely the case
where the buffers were filled and nothing else runs.

The **input** password bytes are zeroed by their owner, in `LoginViewModel` and `UnlockViewModel`. Not
inside the repository: `Data` is copy-on-write, so a callee that calls `zeroize()` on a parameter
uniques the buffer first and wipes only its own private copy, leaving the caller's bytes untouched. The
old comment described an action that could not have worked where it stood.

**3. Quitting cleans up what only a running process could.**
`AttachmentTempFileManager` observed foreground transitions but not termination, and its sweep honours
a 30-second deadline enforced by a timer that dies with the app — so a decrypted attachment opened a
moment before ⌘Q left plaintext on disk indefinitely. `removeAllForTermination()` ignores the deadline,
which is only correct at that moment.

The clipboard had the same shape: every copy schedules a timed clear that checks "is our value still
there" before wiping, and that check is a `Task`. `SecretClipboard` now owns the write and the claim,
so the same rule runs at termination — and it will **not** wipe a clipboard the user has since written
to from another app. Both view models that copy secrets route through it.

**4. The sign-out dialog says what sign-out does.**
It read "All local data will be cleared." It does not clear `bw.macos:deviceIdentifier`, the
UserDefaults preferences, or the pinned certificate decisions — and those omissions are deliberate:
the device identifier is an installation identity that Bitwarden's own clients keep, so deleting it
would make the server see a new device at every login, and silently revoking a pinned-certificate
choice would replace a security decision with a surprise. The copy now names what goes and what stays,
with the reasoning at the call site.

## Deliberate limits

- `makeServerHash` returns a `String`, and `pendingTwoFactor.passwordHash` is one too — Swift `String`
  storage is immutable and cannot be zeroed. That residue is unchanged here; removing it means changing
  those signatures, which is its own change.
- The user-facing `password` field is a `String` for the same reason. The `Data` copy is what gets
  zeroed.
- Termination handlers do not run on a force-quit, a crash, or a power loss. Both hooks are an
  improvement on "never", not a guarantee, and the doc comments say so.
- The timed clipboard clear still lives in each view model. Moving the scheduling into
  `SecretClipboard` would have rewritten four existing tests for no behavioural gain.

## Impact

- New production types: `SecretClipboard` (App layer, registered in `project.pbxproj`).
- `TempFileManaging` gains no requirement — `removeAllForTermination()` is on the concrete type, which
  is the only thing that observes the notification.
- 8 new tests; suite 1536 / 0 / 0, and the count of `func test` declarations in `PrizmTests` equals the
  count that executed, which is the assertion worth keeping.
- Strings: one key replaced in both tables (the old one is no longer used anywhere).
