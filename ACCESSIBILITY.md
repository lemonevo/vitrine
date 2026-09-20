# Accessibility Conformance Statement

**Product**: Prizm (macOS)
**Version**: 1.4.3
**Date**: 2026-09-20
**Standard**: EN 301 549 v3.2.1 / WCAG 2.1 Level AA
**Format**: Based on VPAT 2.4 Rev (Voluntary Product Accessibility Template)

---

## Summary

Prizm is a native macOS SwiftUI application. It inherits platform accessibility features (VoiceOver, keyboard navigation, focus rings, Dynamic Type) from SwiftUI and AppKit. This document reports conformance against WCAG 2.1 Level A and Level AA success criteria as mapped to native software by EN 301 549 Chapter 11.

---

## WCAG 2.1 Level A

| Criterion | Status | Remarks |
|---|---|---|
| 1.1.1 Non-text Content | Supports | All icon-only buttons have `accessibilityLabel`, including the ones added in 1.4 (password-history reveal and copy, fingerprint copy). Decorative images are hidden via `accessibilityHidden(true)`. |
| 1.2.1 Audio-only and Video-only | Not Applicable | No audio or video content. |
| 1.2.2 Captions | Not Applicable | No audio or video content. |
| 1.2.3 Audio Description or Media Alternative | Not Applicable | No audio or video content. |
| 1.3.1 Info and Relationships | Supports | Section headers use `.isHeader` trait. Form fields use native SwiftUI controls with labels. |
| 1.3.2 Meaningful Sequence | Supports | Reading order follows visual layout via SwiftUI's declarative view hierarchy. |
| 1.3.3 Sensory Characteristics | Supports | Instructions do not rely solely on shape, size, or visual location. |
| 1.4.1 Use of Color | Supports | Color is not the sole means of conveying information. Error states include text labels alongside colour indicators. |
| 1.4.2 Audio Control | Not Applicable | No audio playback. |
| 2.1.1 Keyboard | Partially Supports | All major actions have keyboard shortcuts. Drag-and-drop folder operations do not have a keyboard-only alternative. |
| 2.1.2 No Keyboard Trap | Supports | No keyboard traps. Standard macOS focus behaviour applies. |
| 2.1.4 Character Key Shortcuts | Not Applicable | No single-character key shortcuts. All shortcuts use modifier keys. |
| 2.2.1 Timing Adjustable | Not Applicable | No time limits on user actions. Auto-lock is a security feature, not a content timeout. |
| 2.2.2 Pause, Stop, Hide | Not Applicable | No auto-updating or moving content. |
| 2.3.1 Three Flashes or Below Threshold | Supports | No flashing content. All animations respect the macOS Reduce Motion preference. |
| 2.4.1 Bypass Blocks | Supports | Three-pane NavigationSplitView allows direct navigation to sidebar, content, or detail. |
| 2.4.2 Page Titled | Supports | Window title reflects the application name. |
| 2.4.3 Focus Order | Supports | Focus order follows the logical reading order of the three-pane layout. |
| 2.4.4 Link Purpose (In Context) | Supports | The "Open in browser" link includes the field label for context. |
| 2.5.1 Pointer Gestures | Supports | No multi-point or path-based gestures required. |
| 2.5.2 Pointer Cancellation | Supports | Standard macOS button behaviour (activation on mouse-up). |
| 2.5.3 Label in Name | Supports | Accessible names match visible text labels. |
| 2.5.4 Motion Actuation | Not Applicable | No motion-based input. |
| 3.1.1 Language of Page | Supports | App language is determined by macOS system language settings. |
| 3.2.1 On Focus | Supports | No context changes on focus. |
| 3.2.2 On Input | Supports | No unexpected context changes on input. Search filtering is expected behaviour. |
| 3.3.1 Error Identification | Supports | Errors are identified in text — including a rejected master password in the re-prompt sheet, a certificate the pinned fingerprint does not match, and a TOTP seed that will not produce a code. VoiceOver announcements are posted for error banners. |
| 3.3.2 Labels or Instructions | Supports | All form fields have visible labels. The two-factor prompt states which method is being asked for — a code field labelled only "Code" would leave a user with three configured methods guessing which one is wanted. |
| 4.1.1 Parsing | Not Applicable | Not applicable to native applications. |
| 4.1.2 Name, Role, Value | Supports | All interactive controls expose name, role, and value to the accessibility API. Stateful controls (favorite star) expose current value. |

## WCAG 2.1 Level AA

| Criterion | Status | Remarks |
|---|---|---|
| 1.3.4 Orientation | Supports | App adapts to window resizing. No fixed orientation. |
| 1.3.5 Identify Input Purpose | Supports | Login fields use standard text field types. |
| 1.4.3 Contrast (Minimum) | Supports | Uses macOS system colours and semantic styles (`.primary`, `.secondary`). Custom opacity values on banners and borders have been raised to meet 3:1 non-text contrast. Increase Contrast preference further raises opacity values. |
| 1.4.4 Resize Text | Supports | SwiftUI semantic fonts respect the macOS text size accessibility setting. |
| 1.4.5 Images of Text | Supports | No images of text. All text is rendered as native text. |
| 1.4.10 Reflow | Supports | Three-pane layout reflows with window resizing. No horizontal scrolling required. |
| 1.4.11 Non-text Contrast | Supports | Icon buttons use system accent colour against system backgrounds. Custom opacity values on borders and indicators meet 3:1 non-text contrast. Increase Contrast preference raises values further. |
| 1.4.12 Text Spacing | Supports | SwiftUI respects system text spacing preferences. |
| 1.4.13 Content on Hover or Focus | Supports | Hover-revealed actions (copy, open, save) do not obscure other content and are dismissible. |
| 2.4.5 Multiple Ways | Supports | Items accessible via sidebar navigation, search (⌘F), and keyboard shortcuts. |
| 2.4.6 Headings and Labels | Supports | Section headers have `.isHeader` trait. All form fields have descriptive labels. |
| 2.4.7 Focus Visible | Supports | macOS provides default focus rings on all focusable controls. |
| 3.2.3 Consistent Navigation | Supports | Sidebar navigation is consistent across all views. |
| 3.2.4 Consistent Identification | Supports | Same actions use same labels throughout (e.g. "Copy", "Reveal", "Delete"). Reveal is consistently an eye icon with "Reveal" / "Hide", including in the password-history list. |
| 3.3.3 Error Suggestion | Supports | Error messages include corrective suggestions where an actionable fix is known (e.g. "Check your network connection", "Make sure to include https://", "Choose a .pem, .crt or .cer file exported from your server", "Sign in from another Bitwarden client"). Where no fix is available in Prizm, the message says so rather than suggesting something the user cannot do — an account protected by Duo cannot be switched to an authenticator app from here. |
| 3.3.4 Error Prevention (Legal, Financial, Data) | Supports | Destructive actions (delete, permanent delete) require confirmation dialogs. |
| 4.1.3 Status Messages | Supports | Error banners and sync status changes are announced to VoiceOver via `AccessibilityNotification.Announcement`. Copying the account fingerprint phrase is announced too: its button's icon becomes a tick, which confirms the copy visually and says nothing to a screen reader. |

---

## Controls Added in 1.4

Every control below carries an `accessibilityIdentifier`, so it is addressable by UI tests, and a
label a screen reader can read.

| Surface | Controls | Notes |
|---|---|---|
| Vault Health Report (⌘⇧H) | five sections, per-item rows | Section headers use `.isHeader`. **All five sections are drawn even when a check finds nothing** — an absent section is indistinguishable from a check that never ran. The count badge carries the answer. |
| Password history | reveal, copy, per-entry rows | Reveal is behind the master-password gate; the label switches between "Reveal this previous password" and "Hide this previous password". |
| Master-password re-prompt sheet | item name, `SecureField`, Cancel, Confirm | A rejected password leaves the sheet open and announces why, so the difference between "wrong password" and "cancelled" is audible. |
| Two-factor prompt | method name, code field, Resend (email only), Remember, Continue, Cancel | The field's allowed characters depend on the method — a YubiKey emits letters, so a digits-only field would silently discard the tap. |
| Settings ▸ Account | fingerprint phrase, copy | Copy is announced (4.1.3). |
| Settings ▸ Security ▸ certificate trust | pinning toggle, fingerprint row, Trust Certificate…, Stop Trusting, Forget Pinned Certificate | The fingerprint row shows "Not recorded yet" rather than nothing while no pin exists. |
| Edit form ▸ Options | **Master password re-prompt** toggle | Present on every item type, not only logins. |
| Edit form ▸ Login | **Authenticator Key (TOTP)** field, plus a warning when the seed will not produce a code | The warning is advisory: the seed still saves. Refusing to save it would strand a user whose service emits an unusual shape. |

---

## Known Gaps

1. **Drag-and-drop lacks keyboard alternative** (2.1.1) — Folder drag-and-drop operations cannot be performed via keyboard alone. Items can be moved to folders via the edit form as a workaround.

---

## Testing

Accessibility was tested with:
- VoiceOver on macOS 26
- Keyboard-only navigation
- Xcode Accessibility Inspector

---

## Contact

To report an accessibility issue, [open an issue](https://github.com/b0x42/prizm/issues) with the "accessibility" label.
