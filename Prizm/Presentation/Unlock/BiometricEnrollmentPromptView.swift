import LocalAuthentication
import SwiftUI

/// Sheet prompt offering the user to enable biometric unlock.
///
/// Shown once after the first successful password unlock (`.firstTime`),
/// or after biometric invalidation (`.reEnrollAfterInvalidation`).
/// See spec `biometric-unlock` and design Decision 7.
struct BiometricEnrollmentPromptView: View {

    let reason: EnrollmentReason
    let onEnable: () -> Void
    let onDismiss: () -> Void

    // Sensor names ("Touch ID", "Face ID") are Apple product names and stay
    // untranslated; only the generic fallback is localised.
    private var biometryName: String {
        switch LAContext().biometryType {
        case .touchID: return "Touch ID"
        case .faceID:  return "Face ID"
        default:       return L("Biometrics")
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: biometrySystemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(heading)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            VStack(spacing: 10) {
                Button(enableButtonLabel) { onEnable() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])

                Button("Not now") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 380)
    }

    // MARK: - Copy

    private var heading: String {
        switch reason {
        case .firstTime:
            return L("Enable %@ to unlock faster", biometryName)
        case .reEnrollAfterInvalidation:
            return L("Re-enable %@", biometryName)
        }
    }

    private var bodyText: String {
        switch reason {
        case .firstTime:
            return L("You can also enable this in Settings at any time.")
        case .reEnrollAfterInvalidation:
            return L(
                "Your %@ settings changed — a fingerprint was added or removed. For your security, Prizm disabled %@ unlock. Would you like to re-enable it?",
                biometryName, biometryName
            )
        }
    }

    private var enableButtonLabel: String {
        switch reason {
        case .firstTime:
            return L("Enable %@", biometryName)
        case .reEnrollAfterInvalidation:
            return L("Re-enable %@", biometryName)
        }
    }

    private var biometrySystemImage: String {
        switch LAContext().biometryType {
        case .touchID: return "touchid"
        case .faceID:  return "faceid"
        default:       return "person.badge.key"
        }
    }
}
