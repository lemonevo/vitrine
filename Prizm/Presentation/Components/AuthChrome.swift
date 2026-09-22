import AppKit
import SwiftUI

// MARK: - Authentication screen chrome
//
// The parts the two entry screens share: the card they sit in, the header that identifies the app,
// a labelled field, the primary action, and the error banner.
//
// **Why a shared file rather than two copies.** Login and unlock are the same app answering the same
// kind of question at two different moments, and they were drifting: the login screen drew a stock
// `lock.shield.fill` in the accent colour while the unlock screen drew the real application icon. Two
// screens, two identities, one app. Everything that would otherwise be pasted twice lives here
// instead.

// MARK: - AuthCard

/// The card both entry screens are built inside.
///
/// **Content-sized, not window-sized.** It used to fill the window so that the form appeared
/// centred; that worked while the card was the only thing on screen, and stopped working as soon as
/// a caption sat under it — the caption was pushed to the bottom edge, far from the card it belongs
/// to. Callers now centre the card and anything below it as one group.
struct AuthCard<Content: View>: View {

    @ViewBuilder var content: () -> Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(Spacing.authCardPadding)
            .frame(width: Spacing.authCardWidth)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: Spacing.authCardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.authCardCornerRadius)
                    .stroke(Color.primary.opacity(Opacity.authCardBorder(contrast)))
            )
            .shadow(color: Color.black.opacity(0.10), radius: Spacing.authCardShadowRadius,
                    y: Spacing.authCardShadowY)
    }
}

// MARK: - AuthHeader

/// The app's own icon, its name, and one line saying what is being asked.
struct AuthHeader: View {

    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.headerGap) {
            // The real application icon rather than an SF Symbol. `NSApp.applicationIconImage` is the
            // same source the unlock screen already used, so both screens now show the same thing —
            // and it is the thing the user saw in Launchpad a moment ago.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Spacing.authIconSize, height: Spacing.authIconSize)
                .accessibilityHidden(true)

            Text(title)
                .font(Typography.screenHeading)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(Typography.screenBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, Spacing.authHeaderBottom)
    }
}

// MARK: - AuthField

/// A field with its label above it, and an optional hint below.
///
/// **The hint exists because of the placeholder.** A `TextField` whose placeholder is a URL renders
/// that placeholder in blue, underlined, as a detected link — so an *empty* server field looked
/// pre-filled with something clickable. That is not a styling choice to refine; it is the wrong
/// widget for the job. The example belongs in a plain `Text` under the field, which is not
/// link-detected, and the placeholder goes.
///
/// The same trap catches `Text("https://…")` written as a string literal, because SwiftUI parses
/// Markdown in `LocalizedStringKey`. Anything that can be a URL reaches these views as a `String`
/// value, not a literal.
struct AuthField<Control: View>: View {

    let label: String
    var hint: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.fieldLabelGap) {
            Text(label)
                .font(Typography.fieldLabel)
                .foregroundStyle(.secondary)

            control()

            if let hint {
                Text(hint)
                    .font(Typography.utility)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AuthPrimaryButton

/// The screen's one filled action.
struct AuthPrimaryButton: View {

    let title: String
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .font(Typography.actionButton)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [])
    }
}

// MARK: - AuthErrorBanner

/// A failed attempt, in a box that says *this screen is still working*.
///
/// Previously a line of red text sitting between the fields and the button, which read as an
/// unlabeled caption and moved the button every time it appeared. The banner keeps the copy in one
/// place, and the card centring absorbs the height change.
struct AuthErrorBanner: View {

    @Environment(\.colorSchemeContrast) private var contrast

    let message: String
    let identifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.fieldLabelGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.screenBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.rowHorizontal)
        .padding(.vertical, Spacing.bannerVertical)
        .background(Color.red.opacity(Opacity.errorBanner(contrast)),
                    in: RoundedRectangle(cornerRadius: Spacing.authBannerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.authBannerCornerRadius)
                .stroke(Color.red.opacity(Opacity.cardBorder(contrast)), lineWidth: 1)
        )
        .accessibilityIdentifier(identifier)
    }
}
