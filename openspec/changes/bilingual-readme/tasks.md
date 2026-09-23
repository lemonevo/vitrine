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
