import AppKit
import SwiftUI
@testable import Prizm

// MARK: - Auth screen proposal
//
// A drawn proposal for the two authentication screens, in one image so they can be judged together:
// they are the same app and currently do not look like it — the login screen uses a stock SF Symbol
// where the unlock screen uses the real app icon.

private struct FieldBox: View {
    let label: String
    let value: String
    var placeholder: String? = nil
    var isSecret: Bool = false
    var isFocused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                if isSecret {
                    Text(value.isEmpty ? "••••••••••" : value)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.7) : .primary)
                } else {
                    Text(value.isEmpty ? (placeholder ?? "") : value)
                        .font(.system(size: 13))
                        .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.7) : .primary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.accentColor
                                      : Color.primary.opacity(0.14),
                            lineWidth: isFocused ? 2 : 1)
            )
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var body: some View {
        HStack {
            Spacer()
            if !isEnabled {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .frame(height: 34)
        .background(isEnabled ? Color.accentColor : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.red.opacity(0.28)))
    }
}

private struct AuthCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(24)
            .frame(width: 400)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.09)))
            .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
    }
}

private struct Header: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            Text(title).font(.system(size: 21, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 22)
    }
}

// MARK: - Login

struct ProposedLogin: View {
    var filled = false
    var error: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            AuthCard {
                Header(title: "Prizm",
                       subtitle: filled ? "vault.example.com"
                                        : "Sign in to your self-hosted vault")

                VStack(spacing: 12) {
                    FieldBox(label: "Email",
                             value: filled ? "alice@example.com" : "",
                             placeholder: "you@example.com",
                             isFocused: !filled)
                    FieldBox(label: "Master password",
                             value: "", isSecret: true)
                }

                if let error {
                    ErrorBanner(message: error).padding(.top, 12)
                }

                PrimaryButton(title: "Sign In", isEnabled: filled)
                    .padding(.top, 14)

                // The server is set once and then forgotten. It stays a real field — FR-001 — but it
                // sits below a rule and at a smaller size, so it stops competing with the two values
                // the user is actually typing every time they open the app.
                Divider().padding(.vertical, 16)

                HStack(spacing: 7) {
                    Image(systemName: "server.rack").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(filled ? "https://vault.example.com" : "https://vault.example.com")
                        .font(.system(size: 11.5))
                        .foregroundStyle(filled ? Color.primary : Color.secondary.opacity(0.7))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("Edit").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
                }
            }

            Text("Your master password never leaves this Mac — only the key derived from it does.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 400)
        }
    }
}

// MARK: - Unlock

struct ProposedUnlock: View {
    var body: some View {
        AuthCard {
            Header(title: "Prizm Is Locked",
                   subtitle: "Enter the password for alice@example.com to unlock.")

            VStack(spacing: 12) {
                FieldBox(label: "Master password", value: "", isSecret: true, isFocused: true)
                // The screen previously had no submit control at all — Return was the only way in,
                // and `isUnlockDisabled` was computed and then never shown to anyone.
                PrimaryButton(title: "Unlock", isEnabled: false)
            }

            Button {
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "touchid").font(.system(size: 13))
                    Text("Unlock with Touch ID").font(.system(size: 12))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            Divider().padding(.vertical, 16)

            Button {
            } label: {
                Text("Sign in with a different account").font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Sheets

struct ProposedLoginSheet: View {
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                caption("登录 · 空")
                ProposedLogin()
            }
            VStack(alignment: .leading, spacing: 10) {
                caption("登录 · 已填 + 报错")
                ProposedLogin(
                    filled: true,
                    error: "The server could not be reached. Check the URL and your network connection."
                )
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func caption(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }
}

struct ProposedUnlockSheet: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("解锁").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ProposedUnlock()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
