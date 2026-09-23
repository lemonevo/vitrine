<div align="center">

<img src="assets/icon.png" width="128" alt="Vitrine icon">

# Vitrine

[![CI](https://github.com/lemonevo/vitrine/actions/workflows/ci.yml/badge.svg)](https://github.com/lemonevo/vitrine/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org/)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue.svg)](https://www.apple.com/macos/)
[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Native macOS client for Vaultwarden and self-hosted Bitwarden, built in Swift.

*Your secrets. Your server. Our user interface.*

[English](README.md) · [简体中文](README.zh-Hans.md)

</div>

---

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshot_dark.png">
  <img alt="Vitrine screenshot" src="assets/screenshot.png">
</picture>

---

## Why Vitrine

The official Bitwarden desktop app is built with Electron, a Chromium-based web wrapper. It works, but
it does not feel like a Mac app: its menus, its keyboard handling, its scrolling and its autofill are
the browser's, not the system's.

Vitrine is a native SwiftUI client for the same self-hosted server, built from the platform's own
frameworks instead.

If you self-host your passwords and care about the software on your own machine, Vitrine is for you.

## Privacy

Vitrine collects nothing. No telemetry, no analytics, no crash reporting, no usage data. There is no
Vitrine server: the app talks only to your Vaultwarden or Bitwarden instance, and nothing leaves it.

Two features the official clients have are deliberately absent for the same reason. **Breach
reporting** would send part of your password to a third party. **Forwarded-email aliases** would route
your signup through one. Both are refused, not deferred.

## Security

- **Argon2id key derivation** (RFC 9106, memory-hard), plus PBKDF2 for accounts that were set up with
  it: the server decides, and this client follows.
- **AES-256-CBC with HMAC-SHA256**, encrypt-then-MAC, a fresh IV per field. No hand-rolled
  cryptography anywhere; every algorithm is a public standard.
- **Keys live in the macOS Keychain**, device-only and never synchronised, and they are zeroed when
  the vault locks.

What it does not protect against: a compromised or hostile server, malware already running as you, and
anyone with physical access to an unlocked Mac.

## Features

**Your vault**

- Every item type — logins, cards, identities, secure notes (all nine subtypes), SSH keys — readable,
  editable, duplicable, deletable and restorable
- Folders with nesting and drag-and-drop, favourites, and Trash with restore and permanent delete
- Organisations and collections, including creating and renaming collections where your role allows it
- Attachments: upload, download, open and delete, with drag-and-drop batch upload for the common case
- Full-text search across the vault, with matches highlighted in the list

**Getting in**

- Master password, PIN or Touch ID. The PIN is wrapped with a key rather than remembered as a flag, so
  five wrong attempts remove it and sign you out
- Two-factor login by authenticator app, YubiKey OTP or email, with a per-account fingerprint phrase
  you can check out of band
- Auto-lock on idle, sleep and screensaver, with the interval and the action configurable
- Per-item master-password re-prompt, so a protected item stays protected

**Codes and keys**

- TOTP codes for any login carrying a one-time-code key, derived on the device with a live countdown
- A **Verification Codes** destination that lists every code in the vault in one place, searchable and
  sortable, so you do not have to find the item first
- A password, passphrase and username generator, and a read-only viewer for passkeys stored on an item
- An **SSH agent** that serves the keys in your vault to `ssh` and `git` over a local socket, so a key
  that already lives in the vault does not have to be copied into `~/.ssh`
- Certificate pinning, decided per server, recorded on first use and re-verified on every connection

**Everything else**

- Offline reading from a cached copy of the last sync, and a plain statement of how old that copy is
- A vault health report: weak, reused, old and unsecured passwords
- Import and export in Bitwarden's unencrypted JSON, plus CSV for logins, with a report of any item
  that was skipped rather than a silently smaller file
- English and 简体中文, switchable at runtime or following the system
- VoiceOver labels on every control, keyboard navigation, and respect for Reduce Motion and Increase
  Contrast

## Requirements

- macOS 26 or later
- A self-hosted [Vaultwarden](https://github.com/dani-garcia/vaultwarden) or
  [Bitwarden](https://bitwarden.com/) server

Tested against Vaultwarden 1.35.4. Newer versions generally work; older ones are not validated.

## Install

`brew install --cask prizm` installs a **different application** — the upstream project this one was
forked from, which still carries the old name and its own releases. There is no Homebrew tap for
Vitrine.

**Build from source** is the only route today:

```bash
git clone https://github.com/lemonevo/vitrine.git
cd vitrine
cp Prizm/LocalConfig.xcconfig.template Prizm/LocalConfig.xcconfig
# Fill in your Apple Team ID in LocalConfig.xcconfig, then:
open "Prizm/Prizm.xcodeproj"
```

A free Apple ID works as the Team ID; Xcode's Settings → Accounts shows it after your name.

**Prebuilt downloads** appear in [Releases](https://github.com/lemonevo/vitrine/releases) when one is
published. They are **unsigned and not notarised**, because there is no Apple Developer account behind
this project, so macOS will refuse the app on first launch. Right-click (or Control-click) it, choose
**Open**, and confirm; you only have to do that once. macOS will also ask to use your login keychain
the first time: click **Allow**. Or do it from a terminal, with the app where you put it (the bundle
is named `Prizm.app` after the build target):

```bash
xattr -dr com.apple.quarantine "/Applications/Prizm.app"
```

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌘F | Search the vault |
| ⌘N | New item |
| ⌥⌘N | New window |
| ⌘E | Edit the selected item |
| ⌘S | Save the item being edited |
| ⌘D | Duplicate the selected item |
| ⇧⌘C | Copy username |
| ⌥⌘C | Copy password |
| ⌃⌘C | Copy the selected item's one-time code |
| ⌥⇧⌘C | Copy website |
| ⌘R | Sync now |
| ⌘L | Lock the vault |
| ⇧⌘H | Vault health report |
| ⇧⌘E | Export the vault |
| ⇧⌘I | Import a vault |
| ⇧⌘Q | Sign out |
| ⌥ (hold) | Reveal masked fields |
| ⌘, | Settings |

Any of them can be remapped in **System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts** by
adding a rule for Vitrine with the exact menu item name.

## Roadmap

| Now | Next | Later |
|---|---|---|
| Offline vault writing | Multiple accounts | Native macOS autofill |
| | Bitwarden cloud accounts | Passkey creation and sign-in |
| | Conflict merging — detection ships | KDBX 4 (KeePass) reading |

**Now** is in progress, **Next** is planned, **Later** has no schedule.

## Known Limitations

- **Not notarised.** There is no Developer ID, so the app arrives unsigned and needs the right-click →
  Open above.
- **No browser autofill.** There is no Safari extension and no system credential provider, so
  copy-paste is the workflow. This is the largest gap against the official client, and it needs an
  Apple Developer account to close.
- **Passkeys are read-only.** A passkey stored on an item is listed, but Vitrine cannot create one or
  use one to sign in.
- **The SSH agent needs an unsandboxed build.** It listens on a socket `ssh` has to be able to reach,
  which a sandboxed build cannot create. Vitrine says so in Settings rather than failing quietly.
- **No offline writing.** Reading works from the cached copy of the last sync. Creating and editing
  need a connection.
- **Attachments are capped at 500 MB**, and Bitwarden's own hosted service requires a paid plan for
  attachments at all. Vaultwarden has no such limit.
- **macOS 26 is required.** The interface uses SwiftUI features that do not exist earlier.

## Contributing

Open `Prizm/Prizm.xcodeproj` in Xcode: ⌘R builds and runs, ⌘U runs the tests. Changes are proposed in
`openspec/changes/` before the code is written.

Pull requests are welcome.

## Mission & Principles

Vitrine exists to give macOS users a native, auditable, trustworthy interface to their self-hosted
password vault.

**Native-first.** SwiftUI, the system's controls, the platform's conventions. No Electron, no web
views, no compromise on what a Mac app should be.

**Security-first.** No hand-rolled cryptography, and every security decision written down where you
can check it — including the ones that cost a feature.

**Radical transparency.** This is security software. You can read the code, follow the cryptography,
and decide for yourself whether to trust it.

**Simple and honest.** Build what is needed. Say what is not supported. No dark patterns, no growth
hacks, no telemetry.

---

*Not affiliated with Bitwarden, Inc., 8bit Solutions LLC, or the Vaultwarden project.*

*Vitrine began as a fork of [Prizm](https://github.com/b0x42/prizm) by Benjamin, who remains the
copyright holder under its MIT licence. It has since been redesigned and largely rewritten.*
