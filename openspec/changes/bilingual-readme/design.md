# Bilingual README — Design

## Decision 1: two files, not one bilingual file

A single file holding both languages would make drift visible in one diff, which matters in a
repository whose most common defect is documentation that stopped being true. It was still rejected:
the README is the landing page, and a landing page that is twice as long and half in a language the
reader does not have is worse at the only job it has.

So: `README.md` (English) and `README.zh-Hans.md`, each with a one-line switcher at the top. The
suffix matches the application's own localisation directories — `en.lproj` and `zh-Hans.lproj` — so
the project does not acquire a second spelling of its own language code.

**The cost, stated rather than discovered later:** two files can drift. The mitigation is that they
carry the same section order and the same tables, so a diff of one against the other is mechanical.

## Decision 2: the Chinese file is written, not translated

The application's README already claims that "nothing is machine-translated; the strings are written
for both". A Chinese README produced by translating the English one would make that claim false in the
one place a reader is most likely to check it.

In practice that means sentence structure follows Chinese rather than tracking the English clauses,
and a few headings are chosen rather than transliterated ("为什么做 Vitrine" rather than "为什么选择
Vitrine"). The facts — versions, limits, commands — are identical, because they are facts.

## Decision 3: the shortcut table is derived from the menu definitions

The table that was there listed nine shortcuts and one of them was wrong. The replacement was read out
of `PrizmApp.swift`'s command definitions and `VaultBrowserView`'s hidden shortcut buttons, one line at
a time, and it lists fifteen entries. Where the app binds a shortcut the old table did not mention
(`⌥⌘N` for a new window, `⌘R`, `⌘D`, `⇧⌘H`, `⇧⌘E`, `⇧⌘I`, `⌃⌘C`, `⌘,`), the entry is new.

`⌃⌘C` is Copy **Code** — the one-time code, not the seed. That distinction is the whole of
`critical-integrity-fixes` §2.1, and a README that named it "Copy TOTP" would leave a reader guessing
which of the two they were about to paste into a website.

## Decision 4: the badge says the language mode, not the toolchain

The old badge claimed "Swift 6.2", which is a version of the compiler. The project sets
`SWIFT_VERSION = 6.0` and its manifest targets `swift-tools-version: 6.0`; what a reader can actually
check is the language mode. The badge now says **Swift 6**, and the capability it stands for is the one
the project enforces.

## What was checked before writing

- Every shortcut, against the command definitions.
- Every limitation: notarisation (there is no Developer ID — `security find-identity` reports none on
  the machine this was written on), the sandbox and the SSH agent, the 500 MB attachment cap, offline
  writing, passkeys.
- The install section against reality: no tap exists, `gh release list` held nothing at the time it was
  written, and `Casks/prizm.rb` is upstream's formula.
- The feature list against the code, which is how the duplicated generator entry and the missing
  verification-codes destination were found.
