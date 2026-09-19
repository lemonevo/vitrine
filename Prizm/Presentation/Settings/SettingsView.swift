import LocalAuthentication
import SwiftUI

/// macOS Settings window (⌘,).
///
/// Three sections:
/// - **General** — interface language.
/// - **Privacy** — whether website icons are fetched at all.
/// - **Security** — the biometric unlock toggle.
///
/// The Security section is **always** rendered. It used to be hidden whenever the
/// device reported no usable biometrics, which left the Settings pane completely
/// empty — indistinguishable from a broken window. The pane now explains why the
/// toggle is unavailable instead of silently disappearing.
///
/// The toggle itself is offered whenever Touch ID / Face ID works at all. Which layer
/// enforces the biometric gate is reported as a footnote rather than as a dead control.
struct SettingsView: View {

    let authRepository: any AuthRepository

    /// The language is global state owned by the shared manager, so this observes the
    /// singleton directly rather than taking it as a parameter.
    @ObservedObject private var localization = LocalizationManager.shared

    /// Re-probed on appear so that enrolling a fingerprint in System Settings is picked
    /// up without relaunching the app.
    @State private var biometry: BiometryAvailability

    /// Whether website icons are fetched. `FaviconLoader` reads the same `UserDefaults` key on
    /// every request, so writing here takes effect immediately with no reconfiguration — and it
    /// keeps working when this window is closed, which a callback would not.
    @State private var showWebsiteIcons: Bool

    init(authRepository: any AuthRepository) {
        self.authRepository = authRepository
        _biometry = State(
            initialValue: .probe(systemEnforced: authRepository.biometricGateIsSystemEnforced)
        )
        _showWebsiteIcons = State(initialValue: WebsiteIconsPreference.isEnabled())
    }

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("General")
            } footer: {
                Text("Changing the language takes effect immediately for most of the interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show website icons", isOn: $showWebsiteIcons)
                    .onChange(of: showWebsiteIcons) { _, enabled in
                        WebsiteIconsPreference.setEnabled(enabled)
                    }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Icons are loaded from your own server, never from a third party. Turn this off to skip the request entirely — items then show a generic symbol.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Security") {
                switch biometry {
                case .available(let name, let systemEnforced):
                    BiometricUnlockToggle(authRepository: authRepository, biometryName: name)

                    if !systemEnforced {
                        Text(L("This build is not signed with an Apple Developer certificate, so macOS cannot protect the key itself. Prizm asks for %@ instead — the same prompt, checked by the app rather than by the system.", name))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .unavailable(let reason):
                    unavailableRow(reason)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
        .onAppear { biometry = .probe(systemEnforced: authRepository.biometricGateIsSystemEnforced) }
    }

    /// Bridges the manager's non-optional selection to `Picker`'s binding.
    ///
    /// Writing through `setLanguage` (rather than a plain `@AppStorage`) is what keeps
    /// `Bundle.main` and the persisted value in step.
    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { localization.selection },
            set: { localization.setLanguage($0) }
        )
    }

    /// A disabled stand-in for the toggle, so the pane always has visible content.
    private func unavailableRow(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Biometric unlock", isOn: .constant(false))
                .disabled(true)

            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - BiometryAvailability

/// Whether biometric vault unlock can be offered on this machine, and if not, why.
///
/// `LAContext.canEvaluatePolicy` returns `false` both when the hardware is absent and
/// when macOS refuses to bind biometrics to the calling binary. Keeping those apart lets
/// Settings state the real reason instead of hiding the toggle.
///
/// The storage question is deliberately *not* an availability question. A build that
/// cannot create a `.biometryCurrentSet` item still has a working feature — it just has
/// Prizm, not macOS, checking the fingerprint — so it is reported as `available` with
/// `systemEnforced == false` and a footnote, never as a dead switch.
enum BiometryAvailability: Equatable {

    /// Biometrics usable. `name` is the user-facing label ("Touch ID", "Face ID");
    /// `systemEnforced` says whether macOS or Prizm enforces the biometric gate.
    case available(name: String, systemEnforced: Bool)

    /// Biometrics unusable. `reason` is a short explanation safe to show in the UI.
    case unavailable(reason: String)

    /// - Parameter systemEnforced: whether macOS itself enforces the biometric gate
    ///   (`AuthRepository.biometricGateIsSystemEnforced`).
    static func probe(systemEnforced: Bool) -> BiometryAvailability {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        // `canEvaluatePolicy` is what populates `biometryType`, so read it only afterwards.
        let name: String?
        switch context.biometryType {
        case .touchID: name = "Touch ID"
        case .faceID:  name = "Face ID"
        default:       name = nil
        }

        if canEvaluate, let name {
            return .available(name: name, systemEnforced: systemEnforced)
        }
        return .unavailable(reason: reason(for: error, biometryName: name))
    }

    /// Describes why biometrics cannot be used, without over-claiming.
    ///
    /// The `LAError` code is reported verbatim rather than translated into a specific
    /// claim: the same code can mean different things depending on whether the build
    /// carries a signing Team ID, so a confident rewrite ("no fingerprints enrolled")
    /// would be wrong as often as it is right.
    ///
    /// The sensor names ("Touch ID", "Face ID") are Apple's own product names and are
    /// deliberately left untranslated.
    private static func reason(for error: NSError?, biometryName: String?) -> String {
        guard let biometryName else {
            return L("No biometric sensor is available on this Mac.")
        }
        guard let error, error.domain == LAError.errorDomain else {
            return L("%@ is unavailable for this build.", biometryName)
        }
        return L("%@ is unavailable — %@ (LAError %lld)", biometryName, error.localizedDescription, error.code)
    }
}
