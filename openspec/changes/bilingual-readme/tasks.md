# Bilingual README — Tasks

## 1. The English README, rewritten from the code

- [x] 1.1 Structure kept to the spec's order, with the shortcut table and the language switcher added.
- [x] 1.2 **Every shortcut read out of the menu definitions** rather than carried forward. The table
      went from nine entries to fifteen; `⌥⌘N` (new window) was absent before, and `⌘N` was described
      as New Item without saying which of the two it was.
- [x] 1.3 The badge changed from a compiler version to the language mode, which is the part a reader
      can check from the repository.
- [x] 1.4 Roadmap rewritten: the old "Now" column listed attachments, folders and TOTP display, all of
      which shipped. It now names offline writing and conflict handling, which have not.
- [x] 1.5 Known Limitations checked one by one. "Org/collection ciphers not yet decrypted" was removed
      — organisation items have been readable for months, and it was the one entry that understated
      the application rather than overstating it.
- [x] 1.6 The duplicated generator entry removed; the verification-codes destination added, in the same
      list, once.
- [x] 1.7 Install section rewritten: no tap, the command that installs a different app named, the
      build-from-source route given, and the release expectations stated (unsigned, not notarised, and
      how to open it) so the section stays true whether or not a release is published.

## 2. The Chinese README

- [x] 2.1 `README.zh-Hans.md` written rather than translated, with the application's own language code.
- [x] 2.2 Language switcher at the top of both files.
- [x] 2.3 Same section order and the same tables as the English file.

## 3. The record

- [x] 3.1 `project-documentation` delta: the structure requirement modified (two stale scenarios and
      the badge corrected), and a requirement added for the second language.
- [x] 3.2 What the rewrite found is in `proposal.md` — the wrong shortcut table, the duplicated
      entry, the roadmap that described shipped work as pending — because the next reader of that
      file should know it is a rewrite and why.

## 4. Verification

- [x] 4.1 The two files compared mechanically: same headings in the same order, same shortcut rows,
      same roadmap and limitation counts.
- [x] 4.2 No code changed, so no test run is owed. The facts in the files were checked against the
      code, which is the check that matters for a document.
- [ ] 4.3 **Not verified:** that every sentence reads well in Chinese — that is a reader's call, and
      the person who asked for the file is the reader.

## 5. Second pass: written for a reader

- [x] 5.1 Both files read again for anything addressed to the maintainer or to an agent, and removed:
      the openspec process paragraph under Contributing (now one clause), "and the name change is what
      says so" in the footer, "just as importantly" in Security, the roadmap's "so if something
      belongs higher up, say so", and the `./build-app.sh` route in the SSH-agent limitation, which is
      a developer fact and lives in DEVELOPMENT.md.
- [x] 5.2 The Gatekeeper command named `/Applications/Vitrine.app`, which is not the file a release
      ships. It now names `Prizm.app` and says in one clause why the bundle is called that.
- [x] 5.3 `AGENTS.md` added at the root: the two build paths and which one delivers a change, the
      ad-hoc-signing keychain behaviour, the verification traps, the Vitrine-outside/Prizm-inside
      boundary, and the documents that have drifted.
- [x] 5.4 `CLAUDE.md` pointed at it, and the two claims in `CLAUDE.md` that had gone stale — the logging
      subsystem (`com.prizm`) and the active-changes table — corrected and replaced with a directory
      listing. `cd prizm` corrected to `cd vitrine` in `DEVELOPMENT.md` and `CONTRIBUTING.md`.
- [x] 5.5 This delta extended: a scenario for the register, and a requirement for `AGENTS.md`.
- [x] 5.6 The facts in `AGENTS.md` checked against the repository rather than recalled: the product
      names in `project.pbxproj` and `build-app.sh`, the executable the release workflow packages, the
      keychain services in `reset-keychain.sh`, and the absence of `UITests` from the target graph.
