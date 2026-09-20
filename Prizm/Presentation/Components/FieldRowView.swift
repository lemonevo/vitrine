import SwiftUI

// MARK: - FieldRowView

/// A single labeled field row with hover-activated action buttons (FR-023, FR-025).
///
/// Shows a label + value and reveals copy/reveal/open-in-browser controls on hover.
/// Background highlights on hover to indicate interactivity (FR-023).
///
/// For secret fields (password, card number, etc.) pass `isMasked: true` to show
/// a `MaskedFieldView` instead of plain text; the reveal button will be included automatically.
///
/// Usage:
/// ```swift
/// FieldRowView(label: L("Username"), value: item.username, itemId: item.id)
/// FieldRowView(label: L("Password"), value: item.password, itemId: item.id, isMasked: true)
/// FieldRowView(label: L("Website"), value: uri.uri, itemId: item.id, url: URL(string: uri.uri))
/// ```
struct FieldRowView: View {

    let label:    String
    let value:    String?
    let itemId:   String
    var isMasked: Bool  = false
    var isMultiLine: Bool = false
    var url:      URL?  = nil
    var onCopy:   ((String) -> Void)? = nil

    /// The master-password gate for this field, for the fields it covers — see `RepromptGating`.
    /// `.none` for everything else, which is the default and is correct for most rows.
    var gate: RevealGateBinding = .none

    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Field content
            if isMasked {
                Text(label)
                    .font(Typography.fieldValue)
                Spacer()
                hoverActions
                MaskedFieldView(
                    label:            label,
                    value:            value,
                    itemId:           itemId,
                    isGated:          gate.isGated,
                    isSecretRevealed: gate.isRevealed,
                    onRequestReveal:  gate.request
                )
            } else if isMultiLine {
                VStack(alignment: .leading, spacing: 2) {
                    if !label.isEmpty {
                        Text(label)
                            .font(Typography.fieldValue)
                    }
                    Text(value ?? "—")
                        .font(Typography.fieldValue.monospaced())
                        .textSelection(.enabled)
                }
                Spacer()
                hoverActions
            } else {
                Text(label)
                    .font(Typography.fieldValue)
                Spacer()
                hoverActions
                Text(value ?? "—")
                    .font(Typography.fieldValue.monospaced())
                    .lineLimit(1)
                    .textSelection(.enabled)
                browserLink
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, Spacing.rowHorizontal)
        .contentShape(Rectangle())
        .onTapGesture { copyValue() }
        .onHover { hovering in
            optionalAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityHint(value != nil && !(value?.isEmpty ?? true) ? L("Copies %@ to clipboard", label) : "")
        .accessibilityIdentifier(AccessibilityID.Field.row(label))
    }

    private func copyValue() {
        guard let copyValue = value, !copyValue.isEmpty else { return }
        // Tapping a row copies it (FR-023), so a protected row's tap has to take the same route as
        // the Copy Password command. Routing only the menu item would leave the gate walkable in
        // one click.
        if gate.isGated {
            gate.copyGated?(copyValue)
            return
        }
        onCopy?(copyValue)
        optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = false }
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        if isHovered || showCopied {
            if value != nil, !(value?.isEmpty ?? true) {
                Text(showCopied ? L("copied") : L("copy"))
                    .font(.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.accentColor)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var browserLink: some View {
        if let link = url {
            Link(destination: link) {
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.medium)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Open in browser")
            .accessibilityLabel("Open \(label)")
            .accessibilityHint("Opens in browser")
            .accessibilityIdentifier(AccessibilityID.Field.openButton(label))
        }
    }
}
