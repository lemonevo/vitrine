<div align="center">

# Prizm

[![CI](https://github.com/lemonevo/prizm/actions/workflows/ci.yml/badge.svg)](https://github.com/lemonevo/prizm/actions/workflows/ci.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org/)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue.svg)](https://www.apple.com/macos/)
[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Native macOS client for Vaultwarden and self-hosted Bitwarden, built in Swift.

*Your secrets. Your server. Our user interface.*

</div>

---

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshot_dark.png">
  <img alt="Prizm screenshot" src="assets/screenshot.png">
</picture>

---

## Why Prizm

The official Bitwarden desktop app is built with Electron — a Chromium-based web wrapper. It works, but it doesn't feel like a Mac app.

Prizm fills that gap: a fully native macOS client, built in SwiftUI, that connects to the same self-hosted Vaultwarden or Bitwarden server you already run. It looks and behaves like a real Mac app because it is one.

If you self-host your passwords and care about software quality on your own machine, Prizm is for you.

### Mission & Principles

Prizm exists to give macOS users a native, auditable, trustworthy interface to their self-hosted password vault.

**Native-first.** SwiftUI only. No Electron, no web views, no compromise on the Mac experience.

**Security-first.** No hand-rolled crypto. Every algorithm is a vetted standard with a public specification. Every security decision is documented so you can verify it.

**Radical transparency.** This is security software. You should be able to read the code, understand the cryptography, and decide whether to trust it. That's why it's open source and why the security documentation is thorough.

**Simple and honest.** Build what's needed. Say what's not supported. No dark patterns, no growth hacks, no telemetry.

## Features

- **Full vault management** — browse, create, edit, delete, and restore all item types (logins, cards, identities, secure notes, SSH keys) with Trash and favourites support
- **Organisation & collection support** — view and manage items across organisations; collections shown as a collapsible tree in the sidebar with item counts; create, rename, and delete collections (admin/manager role); org items encrypted with RSA-unwrapped organisation keys
- **Folder organization** — create, rename, and delete folders; nested subfolders via `/` naming convention with collapsible tree view; drag-and-drop items onto folders; folder-scoped search
- **Built for power users** — ⌘F global search with match highlighting, ⌘N new item, ⌘L lock, one-keystroke copy for username / password / website, Option to reveal masked fields. [Full shortcut list](#shortcuts)
- **File attachments** — upload, download, open, and delete encrypted file attachments on any vault item; drag-and-drop batch upload; two-layer AES-256-CBC + HMAC-SHA256 encryption with per-attachment keys
- **Password & passphrase generator** — configurable length, character sets, and word separators
- **Touch ID / Face ID unlock** — unlock your vault with biometrics; auto-prompts on lock; graceful re-enrollment when fingerprints change
- **Auto-lock** — locks on sleep and screensaver; sync status always visible in the sidebar
- **TOTP codes** — shows the current 6-digit code with a live countdown for any login carrying a TOTP secret
- **Two-factor login** — authenticator app (TOTP), YubiKey OTP, and email challenges, plus a per-account public-key fingerprint you can verify out of band
- **Vault import & export** — Bitwarden-compatible unencrypted JSON, with a per-item report of what was imported and what was skipped
- **Vault health report** — flags weak, reused, and old passwords, and items with no second factor
- **Password strength & history** — per-item strength estimate, and the previous passwords kept on a login
- **Master-password re-prompt** — per-item gate that asks for the master password before revealing or copying a protected field
- **Certificate pinning** — per-server trust decision, recorded on first use and re-verified on every connection
- **Passkey viewer** — passkeys attached to a vault item are listed, read-only
- **SSH agent** — serves SSH keys from the vault over a local socket. Requires a build without the App Sandbox; see [Known Limitations](#known-limitations)
- **Accessible** — VoiceOver labels and hints on all controls, keyboard navigable, respects Reduce Motion and Increase Contrast; targets WCAG 2.1 AA. See [ACCESSIBILITY.md](ACCESSIBILITY.md)

## Install

### Requirements

- macOS 26 or later
- A self-hosted [Vaultwarden](https://github.com/dani-garcia/vaultwarden) or [Bitwarden](https://bitwarden.com/) server

Tested against Vaultwarden 1.35.4. Older versions may work but are not validated.

### Homebrew (recommended)

```bash
brew tap b0x42/prizm
brew install --cask prizm
```

### Direct Download

**[Download Prizm](https://github.com/lemonevo/prizm/releases/latest)**

The app is not notarized. After downloading, right-click (Control-click) the `.app` and choose **Open**, then confirm. You only need to do this once. After that, you can open it normally.

macOS will also show a **"Prizm wants to use your login keychain"** prompt on first launch — click **Allow**. This is expected for unsigned apps; Prizm uses it to store credentials securely.

Alternatively, from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Prizm.app
```

### Build from source

```bash
git clone https://github.com/lemonevo/prizm.git
cd prizm
cp Prizm/LocalConfig.xcconfig.template Prizm/LocalConfig.xcconfig
# Fill in your Apple Team ID in LocalConfig.xcconfig, then:
open "Prizm/Prizm.xcodeproj"
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for full setup instructions, including how to get a free Team ID.

## Privacy & Security

Prizm collects nothing. No telemetry, no analytics, no crash reporting, no usage data. There is no Prizm server — the app talks exclusively to your Vaultwarden or Bitwarden instance. Nothing leaves your server.

All cryptography runs locally on your device:

- **Argon2id key derivation** (RFC 9106, memory-hard) — makes offline brute-force attacks computationally infeasible
- **AES-256-CBC + HMAC-SHA256** authenticated encryption — all vault data stays encrypted in memory and in transit
- **RSA-OAEP-SHA1 organisation key unwrapping** (Security.framework) — organisation symmetric keys are RSA-wrapped per member; Prizm unwraps them at sync time using your account's private key, following the Bitwarden protocol
- **macOS Keychain** storage (device-only, `WhenUnlockedThisDeviceOnly`) — session keys never touch iCloud

The app is open source. Verify these claims by reading the code. See [SECURITY.md](SECURITY.md) for the full threat model, algorithm specifications, and what the app does not protect against. See [ACCESSIBILITY.md](ACCESSIBILITY.md) for the WCAG 2.1 conformance statement.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌘F | Global search |
| ⌘N | New item |
| ⌘L | Lock vault |
| ⌘E | Edit selected item |
| ⌘S | Save edits |
| ⇧⌘C | Copy username |
| ⌥⌘C | Copy password |
| ⌥⇧⌘C | Copy website |
| ⇧⌘Q | Sign out |
| ⌥ (hold) | Reveal masked fields |

Any shortcut can be remapped in **System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts**. Add a rule for Prizm with the exact menu item name and your preferred key combination.

## Roadmap

| Now | Next | Later |
|---|---|---|
| Background sync | Offline vault read / write | Browser auto-fill extension |
| Multiple accounts | Bitwarden cloud login | Full support for KDBX 4 (KeePass) |
| | Passkey creation & login | |

**Now** — actively in development. **Next** — planned for the following 3–6 months. **Later** — on the list with no fixed timeline.

> **Breach checking is deliberately not on this list.** Telling you whether a password appears in a breach dump means sending part of that password to a third party. For a client whose whole premise is that your secrets stay on your own server, that is not a trade worth making.

Want to shift something up the list? [Open an issue](https://github.com/lemonevo/prizm/issues) — priorities are driven by user feedback.

## Known Limitations

- **Not notarized** — The app is not signed with an Apple Developer ID. On first launch, right-click and choose Open to bypass Gatekeeper.
- **No browser auto-fill** — There is no browser extension. Copy-paste is the current workflow.
- **macOS 26 required** — The app uses SwiftUI features only available in macOS 26.
- **Passkeys are read-only** — Passkeys attached to a vault item are listed, but Prizm cannot create one or use one to log in.
- **SSH agent needs an unsandboxed build** — The agent listens on a Unix socket that `ssh` has to be able to reach, which a build with the App Sandbox enabled cannot create. In that case Prizm reports the agent as unavailable rather than failing silently. Builds produced by `./build-app.sh` disable the sandbox and can run it.
- **No offline vault creation** — Creating or editing items requires an active server connection.
- **Attachment size limit** — Files larger than 500 MB are rejected. Bitwarden-hosted servers require a premium subscription for attachments; Vaultwarden is unaffected.

## Contributing

See [DEVELOPMENT.md](DEVELOPMENT.md) for prerequisites, build instructions, and the architecture overview.

Changes follow an **openspec** workflow: each feature lives in `openspec/changes/<name>/` with a proposal, design, and task list before any code is written. See `openspec/` for active and archived changes.

Pull requests welcome. Please open an issue first for anything significant.

---

*Not affiliated with Bitwarden, Inc., 8bit Solutions LLC, or the Vaultwarden project.*
