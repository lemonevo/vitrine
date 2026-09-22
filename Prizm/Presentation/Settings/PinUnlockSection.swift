import SwiftUI

// MARK: - PinUnlockSection

/// The PIN settings: whether there is one, and whether it may open a restarted app.
///
/// Mirrors `BiometricUnlockToggle`'s shape deliberately — same placement, same "unlock your vault
/// first" hint, same refusal to flip a switch back in silence. Two unlock settings that behaved
/// differently would be worse than either of them separately.
struct PinUnlockSection: View {

    let authRepository: any AuthRepository

    @State private var isEnabled: Bool
    @State private var requiresMasterPasswordOnRestart: Bool
    @State private var isProcessing = false
    @State private var showVaultLockedHint = false
    @State private var failureReason: String?

    /// The set-PIN sheet, presented when the user turns the switch on.
    @State private var isSettingPIN = false

    init(authRepository: any AuthRepository) {
        self.authRepository = authRepository
        _isEnabled = State(initialValue: authRepository.pinUnlockAvailable)
        _requiresMasterPasswordOnRestart = State(
            initialValue: PinUnlockSettings.requiresMasterPasswordOnRestart()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("Unlock with a PIN"), isOn: $isEnabled)
                .disabled(isProcessing || showVaultLockedHint)
                .accessibilityIdentifier(AccessibilityID.PinSettings.toggle)
                .onChange(of: isEnabled) { _, newValue in
                    if newValue {
                        // Setting one needs a PIN in hand, so the switch only opens the sheet. It is
                        // flipped back if the sheet is cancelled, so the control never claims a state
                        // that is not stored.
                        isSettingPIN = true
                    } else {
                        Task { await disable() }
                    }
                }

            // Only meaningful when a PIN exists; showing it otherwise invites the user to reason about
            // a setting that does nothing yet.
            if isEnabled {
                Toggle(L("Require the master password after restarting Vitrine"),
                       isOn: $requiresMasterPasswordOnRestart)
                    .disabled(isProcessing)
                    .accessibilityIdentifier(AccessibilityID.PinSettings.requirePasswordOnRestart)
                    .onChange(of: requiresMasterPasswordOnRestart) { _, newValue in
                        PinUnlockSettings.setRequiresMasterPasswordOnRestart(newValue)
                    }

                Text(L("With this on, a PIN cannot unlock Vitrine until you have entered your master password once since it started."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L("A PIN is shorter than your master password, so it protects the local vault less. Five wrong PINs remove it and sign you out."))
                .font(.caption)
                .foregroundStyle(.secondary)

            if showVaultLockedHint {
                Text(L("Unlock your vault to change this setting"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let failureReason {
                Text(failureReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isSettingPIN, onDismiss: {
            // The truth is on disk, not in the switch: re-read it rather than assuming the sheet
            // succeeded.
            isEnabled = hasStoredPIN
        }) {
            SetPinSheet(
                minimumLength: PinUnlockSettings.minimumPINLength,
                onCancel: { isSettingPIN = false },
                onSubmit: { pin in try await enable(pin: pin) }
            )
        }
    }

    private var hasStoredPIN: Bool { authRepository.pinUnlockAvailable || pinWasStoredThisSession }

    /// `pinUnlockAvailable` is false on a launch that has not had a full authentication yet, which is
    /// exactly the state the settings screen is *not* in — so within a session it is a fine proxy. This
    /// flag keeps the switch honest during the one moment it is not.
    @State private var pinWasStoredThisSession = false

    private func enable(pin: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await authRepository.enablePinUnlock(pin: pin)
            pinWasStoredThisSession = true
            isSettingPIN = false
            showVaultLockedHint = false
            failureReason = nil
        } catch {
            isSettingPIN = false
            isEnabled = false
            if (error as? AuthError) == .vaultLocked {
                showVaultLockedHint = true
            } else {
                failureReason = error.localizedDescription
            }
            throw error
        }
    }

    private func disable() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await authRepository.disablePinUnlock()
            pinWasStoredThisSession = false
            failureReason = nil
        } catch {
            // Never flip the switch back in silence: an unexplained revert is indistinguishable from
            // a control that does not respond.
            isEnabled = true
            failureReason = error.localizedDescription
        }
    }
}

// MARK: - SetPinSheet

/// Asks for a PIN twice.
///
/// Twice because a PIN is not displayed back to the user — there is nothing to check against later,
/// and a typo would produce a code that never works and cannot be inspected. And because the second
/// entry is the only thing standing between the user and a vault they can no longer open.
private struct SetPinSheet: View {

    let minimumLength: Int
    let onCancel: () -> Void
    let onSubmit: (String) async throws -> Void

    @State private var pin = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var isSubmitting = false
    @FocusState private var pinFocused: Bool

    private var isTooShort: Bool { pin.count < minimumLength }
    private var isMismatched: Bool { !confirmation.isEmpty && pin != confirmation }
    private var canSubmit: Bool { !isTooShort && pin == confirmation && !isSubmitting }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Set a PIN"))
                .font(Typography.screenHeading)

            Text(L("At least %d characters. It unlocks Vitrine on this Mac only.", minimumLength))
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField(L("PIN"), text: $pin)
                .textFieldStyle(.roundedBorder)
                .focused($pinFocused)
                .accessibilityIdentifier(AccessibilityID.PinSettings.pinEntry)
            SecureField(L("Confirm PIN"), text: $confirmation)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityID.PinSettings.pinConfirmation)

            if isTooShort {
                Text(L("Your PIN must be at least %d characters.", minimumLength))
                    .font(.caption).foregroundStyle(.secondary)
            } else if isMismatched {
                Text(L("The two PINs do not match."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L("Cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AccessibilityID.PinSettings.pinCancel)
                Button(L("Set PIN")) {
                    Task {
                        isSubmitting = true
                        defer { isSubmitting = false }
                        do {
                            try await onSubmit(pin)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .accessibilityIdentifier(AccessibilityID.PinSettings.pinConfirm)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { pinFocused = true }
    }
}
