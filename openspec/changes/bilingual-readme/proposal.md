# Bilingual README — Proposal

## Why

The README was the repository's front door and it had stopped describing the application:

- **The shortcut table was wrong.** It gave `⌘N` for "New Item" and listed nine shortcuts; the app
  binds fifteen, and `⌥⌘N` is New *Window*, which the table did not mention at all. A reader following
  it would have found that half the keys did nothing they were told.
- **The installer section pointed at a tap that belongs to someone else**, and at a download that 404s.
- **The roadmap and the known limitations described a much earlier build** — "add attachments",
  "folders", "TOTP code display" were listed as work still to come, and "org/collection ciphers not yet
  decrypted" as a limitation, when organisation items have been readable for months.
- **The generator was listed twice**, once under "Features" and once again four lines later.
- Nothing in it mentioned the two things the interface gained most recently: verification codes as a
  destination, and the sidebar's status row carrying both the refresh and the settings controls.

And it was English only, while the application ships in English and 简体中文 and its own rule is that
neither language is machine-translated.

## What Changes

- `README.md` rewritten against the code rather than against its previous self: every shortcut read out
  of the menu definitions, every limitation checked, every feature matched to something that exists.
- `README.zh-Hans.md` added, written in Chinese rather than translated into it, with a language
  switcher at the top of both files.
- The `project-documentation` requirement that specifies the README's structure is updated: the badge
  it demanded ("Swift 6.2") named a toolchain rather than the language mode the project compiles in,
  and two of its scenarios described the roadmap and the limitations as they were, not as they are.
- A new requirement covers the Chinese file.

## Non-goals

- **Translating anything else.** `DEVELOPMENT.md`, `SECURITY.md` and `CONTRIBUTING.md` stay in English
  for now; they are for contributors and for a security reviewer, and half-translating that set would
  be worse than leaving it coherent.
- **Changing what the app does.** Nothing here touches code.

## Capabilities

- `project-documentation` — the README's structure, its content, and now its second language.

## Impact

- The README says there is no published release and how to build instead. That stays true until a
  release is published; the section is written so that it remains true either way.
- The shortcut table is now generated from the menu definitions, so the next reader can check it the
  same way.
