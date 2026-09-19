import SwiftUI

/// Toggle for enabling/disabling biometric vault unlock in Settings.
///
/// Rendered by `SettingsView` only when biometrics are actually usable. Disabled with
/// an explanatory label when the vault is locked (enabling requires vault keys in memory).
struct BiometricUnlockToggle: View {

    let authRepository: any AuthRepository

    /// User-facing label for the available biometry ("Touch ID", "Face ID").
    /// Resolved once by `SettingsView` so the toggle does not re-probe `LAContext`.
    let biometryName: String

    @State private var isEnabled: Bool = UserDefaults.standard.bool(forKey: "biometricUnlockEnabled")
    @State private var isProcessing = false
    @State private var showVaultLockedHint = false
    /// Why the last attempt failed, when it was not the "vault is locked" case.
    @State private var failureReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("\(biometryName) unlock", isOn: $isEnabled)
                .disabled(isProcessing || showVaultLockedHint)
                .onChange(of: isEnabled) { _, newValue in
                    Task { await toggleBiometric(enabled: newValue) }
                }

            if showVaultLockedHint {
                Text("Unlock your vault to change this setting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let failureReason {
                Text(failureReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleBiometric(enabled: Bool) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            if enabled {
                try await authRepository.enableBiometricUnlock()
            } else {
                try await authRepository.disableBiometricUnlock()
            }
            showVaultLockedHint = false
            failureReason = nil
        } catch {
            isEnabled = !enabled
            if (error as? AuthError) == .biometricUnavailable {
                showVaultLockedHint = true
            } else {
                // Never flip the switch back in silence. An unexplained revert is
                // indistinguishable from a control that does not respond, which is exactly
                // how the missing-entitlement failure presented itself.
                failureReason = error.localizedDescription
            }
        }
    }
}
