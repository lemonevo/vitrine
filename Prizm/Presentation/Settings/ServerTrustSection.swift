import SwiftUI

// MARK: - ServerTrustSection

/// The Security settings for one server's certificate: a private authority to trust, and an
/// opt-in pin on the leaf (design D8).
///
/// Everything here is scoped to `host`, which is the host of the server the user is signed in to.
/// It is passed in rather than looked up because the window can be open before a login finishes,
/// and a section that showed one server's material under another's heading would be worse than an
/// empty one.
struct ServerTrustSection: View {

    let store:     any ServerTrustStore
    let host:      String?
    /// Opens the file picker and returns the chosen URL. Injected from the App layer so this file
    /// stays free of AppKit (Constitution §II) and so a test can supply a URL without a panel.
    let pickCertificateFile: @MainActor () -> URL?
    /// Reads certificates out of the picked file. Injected for the same reason.
    let loadCertificates: (URL) throws -> [Data]

    @State private var configuration = ServerTrustConfiguration.empty
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let host {
                controls(for: host)
            } else {
                Text(L("Sign in to configure the certificate for your server."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.ServerTrust.noHost)
            }
        }
        .task(id: host) { await reload() }
    }

    // MARK: - Controls

    private func controls(for host: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("Pin this server's certificate"), isOn: $configuration.pinningEnabled)
                .onChange(of: configuration.pinningEnabled) { _, _ in
                    Task { await save() }
                }
                .accessibilityIdentifier(AccessibilityID.ServerTrust.pinningToggle)

            LabeledContent(L("Fingerprint")) {
                Text(configuration.pinnedLeafSHA256 ?? L("Not recorded yet"))
                    .font(Font.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.ServerTrust.fingerprint)
            }

            LabeledContent(L("Trusted authority")) {
                Text(configuration.trustedCACertificates.isEmpty
                     ? L("None")
                     : L("%lld certificate(s)", configuration.trustedCACertificates.count))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.ServerTrust.authorityCount)
            }

            HStack(spacing: 12) {
                Button(L("Trust Certificate…")) { trustCertificate() }
                    .accessibilityIdentifier(AccessibilityID.ServerTrust.trustButton)

                // Always reachable. A pin the user cannot revoke is how a reinstalled server
                // becomes an unrecoverable lockout, and the recovery would be a Keychain edit.
                Button(L("Forget Pinned Certificate")) { Task { await forgetPin() } }
                    .disabled(configuration.pinnedLeafSHA256 == nil)
                    .accessibilityIdentifier(AccessibilityID.ServerTrust.forgetPinButton)

                if !configuration.trustedCACertificates.isEmpty {
                    Button(L("Stop Trusting")) { Task { await forgetAuthority() } }
                        .accessibilityIdentifier(AccessibilityID.ServerTrust.stopTrustingButton)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(AccessibilityID.ServerTrust.error)
            }

            Text(L("Pinning is off until you turn it on. The fingerprint of the certificate your server presents is recorded on the next connection and checked from then on, so a changed certificate is refused instead of accepted."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func trustCertificate() {
        guard let url = pickCertificateFile() else { return }
        do {
            let certificates = try loadCertificates(url)
            // Replacing rather than appending: two authorities from different files would be
            // evaluated as one anchor set, and the user has no way to see or remove "the second
            // one" from here.
            configuration.trustedCACertificates = certificates
            errorMessage = nil
            Task { await save() }
        } catch {
            // Nothing is stored on this path — the file never reaches the configuration.
            errorMessage = error.localizedDescription
        }
    }

    private func forgetPin() async {
        configuration.pinnedLeafSHA256 = nil
        await save()
    }

    private func forgetAuthority() async {
        configuration.trustedCACertificates = []
        await save()
    }

    // MARK: - Storage

    private func reload() async {
        guard let host else { return }
        do {
            configuration = try await store.configuration(forHost: host)
            errorMessage   = nil
        } catch {
            // Left as .empty with the reason on screen. The delegate fails closed on its own, so
            // showing nothing stored is the honest state rather than a dangerous one.
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the current configuration, and re-reads when it does not take.
    ///
    /// The re-read matters: a toggle that stays on after a failed write is a control claiming a
    /// protection that was never stored, which is the same failure as a pin that silently never
    /// arms in the delegate.
    private func save() async {
        guard let host else { return }
        do {
            try await store.save(configuration, forHost: host)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }
}
