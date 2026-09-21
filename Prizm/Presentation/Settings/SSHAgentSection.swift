import AppKit
import SwiftUI

// MARK: - SSHAgentSection

/// The SSH agent: whether it runs, where its socket is, and which keys it serves.
///
/// The pane has one job the rest of the feature cannot do for itself — **make the failure visible**.
/// Every way this feature can go wrong has the shape of a silent failure: a socket that was never
/// created, a key quietly left out, an agent that is off while the user believes it is on. `ssh`
/// reports none of them; it says the agent refused and nothing else. So the status line here is not
/// a convenience, and the "not offered" list is not a debug aid.
struct SSHAgentSection: View {

    /// Observed rather than snapshotted: the status changes while this pane is open — the vault
    /// locks, a start fails, a key is added in the other window — and a snapshot would leave the
    /// pane describing a state that has moved on.
    @ObservedObject var coordinator: SSHAgentCoordinator

    /// Which value the tick is currently showing, so a copy has a visible *and* an announced
    /// confirmation. Without the announcement the tick says nothing to VoiceOver.
    @State private var copied: CopiedValue?

    private enum CopiedValue { case socket, exportLine }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("Serve SSH keys from this vault"), isOn: enabledBinding)
                .accessibilityIdentifier(AccessibilityID.SSHAgent.settingsToggle)

            statusRow

            LabeledContent(L("Socket")) {
                HStack(spacing: 8) {
                    Text(verbatim: coordinator.socketPath)
                        .font(Font.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityIdentifier(AccessibilityID.SSHAgent.socketPath)

                    copyButton(text: coordinator.socketPath,
                               kind: .socket,
                               label: L("Copy the socket path"),
                               identifier: AccessibilityID.SSHAgent.copySocket)
                }
            }

            LabeledContent(L("Shell setup")) {
                HStack(spacing: 8) {
                    Text(verbatim: exportLine)
                        .font(Font.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityIdentifier(AccessibilityID.SSHAgent.exportLine)

                    copyButton(text: exportLine,
                               kind: .exportLine,
                               label: L("Copy the shell command"),
                               identifier: AccessibilityID.SSHAgent.copyExportLine)
                }
            }

            Text(L("Put that line in your shell profile and open a new terminal. Prizm has to be running with the vault unlocked; anything that reads the key asks Prizm to sign with it, and the first request for each key asks for your master password."))
                .font(.caption)
                .foregroundStyle(.secondary)

            keyLists
        }
        .task { await coordinator.refreshKeys() }
        .onChange(of: copied) { _, value in
            if value != nil { AccessibilityNotification.Announcement(L("Copied")).post() }
        }
    }

    // MARK: - Status

    /// The one line that says what the agent is doing, or why it is not.
    @ViewBuilder
    private var statusRow: some View {
        let status = SSHAgentStatus.of(isEnabled: coordinator.isEnabled,
                                       isRunning: coordinator.isRunning,
                                       failure:   coordinator.failure)

        switch status {
        case .off:
            Text(L("Off. Turn it on to serve the SSH keys in this vault."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.SSHAgent.status)

        case .waitingForUnlock:
            Text(L("Waiting for the vault to be unlocked."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.SSHAgent.status)

        case .listening:
            Label { Text("Listening") } icon: { Image(systemName: "checkmark.circle") }
                .font(.caption)
                .accessibilityIdentifier(AccessibilityID.SSHAgent.status)

        case .failed(let reason):
            // Red, with the reason rather than the word "unavailable". This is the state the spec
            // singles out: an agent that is off with no explanation looks exactly like one that is
            // on and protecting nothing.
            Label {
                Text(verbatim: reason)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier(AccessibilityID.SSHAgent.status)
        }
    }

    // MARK: - Keys

    @ViewBuilder
    private var keyLists: some View {
        if coordinator.usableKeys.isEmpty && coordinator.unusableKeys.isEmpty {
            Text(L("This vault holds no SSH keys."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.SSHAgent.noKeys)
        } else {
            if !coordinator.usableKeys.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Keys offered to ssh (%lld)", Int64(coordinator.usableKeys.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(coordinator.usableKeys, id: \.itemId) { key in
                        // The item's name, which is what `ssh-add -l` will print — so the pane and
                        // the terminal agree about which key is which.
                        Text(verbatim: key.comment)
                            .font(Font.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier(AccessibilityID.SSHAgent.usableKey)
                    }
                }
            }

            if !coordinator.unusableKeys.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Not offered (%lld)", Int64(coordinator.unusableKeys.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(coordinator.unusableKeys, id: \.itemId) { key in
                        // Name and reason together, never one without the other: a key listed as
                        // omitted with no reason is the same to the user as no list at all.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: key.name)
                                .font(Font.system(.caption, design: .monospaced))
                            Text(verbatim: key.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(AccessibilityID.SSHAgent.unusableKey)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Writing through `setEnabled` rather than a local `@State`: the coordinator owns the flag, and
    /// a copy here would be a second answer to "is it on" that survives a failed write.
    private var enabledBinding: Binding<Bool> {
        Binding(get: { coordinator.isEnabled },
                set: { coordinator.setEnabled($0) })
    }

    private var exportLine: String {
        SSHAgentShellSetup.exportLine(socketPath: coordinator.socketPath)
    }

    private func copyButton(text: String,
                            kind: CopiedValue,
                            label: String,
                            identifier: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = kind
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = nil
            }
        } label: {
            Image(systemName: copied == kind ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - SSHAgentStatus

/// What the pane says about the agent, derived from the coordinator's published state.
///
/// A separate value rather than a chain of `if`s in the view, so the ordering rule can be tested.
/// **A recorded failure outranks everything.** Presenting a failed start as "listening" is the one
/// mistake this pane must not make, and an `if` written in the other order would make it.
nonisolated enum SSHAgentStatus: Equatable {

    /// Switched off. Nothing is listening, and nothing was asked to.
    case off

    /// Switched on, vault locked.
    ///
    /// Named rather than collapsed into `off`, because it is the state a user is most likely to
    /// misread: the switch is on, the pane agrees, and nothing is listening until the vault opens.
    case waitingForUnlock

    /// Switched on, vault unlocked, socket bound.
    case listening

    /// Switched on and unable to listen. `reason` is what the coordinator recorded.
    case failed(reason: String)

    static func of(isEnabled: Bool, isRunning: Bool, failure: String?) -> SSHAgentStatus {
        guard isEnabled else { return .off }
        if let failure { return .failed(reason: failure) }
        return isRunning ? .listening : .waitingForUnlock
    }
}

// MARK: - SSHAgentShellSetup

/// The shell line that points `ssh` at Prizm.
nonisolated enum SSHAgentShellSetup {

    /// `export SSH_AUTH_SOCK="…"`, quoted.
    ///
    /// **The quotes are load-bearing.** The default path is
    /// `~/Library/Application Support/Prizm/ssh-agent/agent.sock`, and an unquoted space turns the
    /// assignment into two words — leaving `SSH_AUTH_SOCK` empty and `ssh` silently falling back to
    /// the keys in `~/.ssh`. That failure looks like the agent being broken, which is the hardest
    /// kind to diagnose from the terminal.
    static func exportLine(socketPath: String) -> String {
        "export SSH_AUTH_SOCK=\"\(socketPath)\""
    }
}
