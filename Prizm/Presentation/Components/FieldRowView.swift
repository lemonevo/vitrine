import SwiftUI

// MARK: - Detail field label

/// The fixed-width label column at the head of a detail card row.
///
/// Shared by `FieldRowView` and `TOTPCodeView` because the two sit inside the same card, and the
/// column only works if they agree on its width to the point. A second copy of the frame would drift
/// the moment one was edited, and the drift would show as values that do not line up.
///
/// Long labels wrap to a second line rather than truncate: a custom field's name is user data, and a
/// row that silently cuts it off is worse than a row that is taller than its neighbours.
struct DetailFieldLabel: View {

    let text: String

    var body: some View {
        Text(text)
            .font(Typography.detailFieldLabel)
            .foregroundStyle(Foreground.muted)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Spacing.detailLabelWidth, alignment: .leading)
    }
}

// MARK: - FieldRowView

/// A single labeled field row with an always-visible copy affordance (FR-023, FR-025).
///
/// Shows a label in a fixed-width column and the value beside it, so a stack of rows reads as a
/// table rather than as a list of one-off sentences.
///
/// For secret fields (password, card number, etc.) pass `isMasked: true` to show
/// a `MaskedFieldView` instead of plain text; the reveal button will be included automatically.
///
/// **The copy affordance is visible, not revealed on hover.** It used to appear only while the
/// pointer was over the row, which on a Mac means the way to copy a password is invisible until you
/// already know it exists. The open-in-browser icon has always been visible for the same reason.
///
/// **Monospace is for what gets transcribed.** Passwords, card numbers, security codes, keys and
/// fingerprints are read out character by character, so they are monospaced; usernames, URLs and
/// dates are read as words, and setting them in a fixed-pitch face made the whole pane look like a
/// terminal. Pass `isMonospaced: true` for a visible value that is still transcribed.
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
    /// A visible value that is transcribed character by character — a fingerprint, a public key.
    var isMonospaced: Bool = false
    var url:      URL?  = nil
    var onCopy:   ((String) -> Void)? = nil

    /// The master-password gate for this field, for the fields it covers — see `RepromptGating`.
    /// `.none` for everything else, which is the default and is correct for most rows.
    var gate: RevealGateBinding = .none

    @State private var isHovered = false
    @State private var showCopied = false

    @Environment(\.colorSchemeContrast) private var contrast

    /// Whether this row has anything to copy. Drives the affordance and the tap gesture alike, so a
    /// row cannot advertise a copy that would do nothing.
    private var canCopy: Bool {
        guard let value, !value.isEmpty else { return false }
        return onCopy != nil || gate.isGated
    }

    var body: some View {
        HStack(spacing: 0) {
            if !label.isEmpty {
                DetailFieldLabel(text: label)
            }

            if isMasked {
                maskedValue
            } else if isMultiLine {
                multilineValue
            } else {
                singleLineValue
            }

            Spacer(minLength: Spacing.detailRowGap)

            // One reserved column for every trailing affordance, so the copy glyphs in all three cards
            // of a pane land on the same x rather than wherever their value happened to end.
            HStack(spacing: 2) {
                if !isMasked {
                    copyAffordance
                }
                browserLink
            }
            .frame(width: Spacing.detailActionSlotWidth, alignment: .trailing)
        }
        .frame(minHeight: Spacing.detailRowMinHeight)
        .padding(.vertical, Spacing.detailRowVertical)
        .padding(.horizontal, Spacing.detailRowHorizontal)
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

    // MARK: - Values

    private var maskedValue: some View {
        MaskedFieldView(
            label:            label,
            value:            value,
            itemId:           itemId,
            isGated:          gate.isGated,
            isSecretRevealed: gate.isRevealed,
            onRequestReveal:  gate.request
        )
    }

    private var multilineValue: some View {
        Text(value ?? "—")
            .font(Typography.detailFieldValue)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var singleLineValue: some View {
        Text(value ?? "—")
            .font(isMonospaced ? Typography.detailFieldValue.monospaced()
                               : Typography.detailFieldValue)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    // MARK: - Controls

    /// The trailing copy control: an icon normally, a confirmation for 0.8s after a copy.
    ///
    /// Absent for a masked row, where the reveal eye already occupies the trailing slot and the
    /// header's Copy password button is the discoverable way to copy the value.
    @ViewBuilder
    private var copyAffordance: some View {
        if canCopy {
            if showCopied {
                Text(L("copied"))
                    .font(Typography.utility)
                    .textCase(.uppercase)
                    // Not `Color.accentColor`: this is 10pt text, and the accent measures 4.02:1 in
                    // light aqua — under the floor `Foreground` exists to hold.
                    .foregroundStyle(Foreground.action)
                    .transition(.opacity)
                    .accessibilityIdentifier(AccessibilityID.Field.copyButton(label))
            } else {
                Image(systemName: "doc.on.doc")
                    .imageScale(.medium)
                    .foregroundStyle(isHovered ? Foreground.action : Foreground.muted)
                    .accessibilityLabel(L("Copy %@", label))
                    .accessibilityIdentifier(AccessibilityID.Field.copyButton(label))
            }
        }
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
        guard let onCopy else { return }
        onCopy(copyValue)
        optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            optionalAnimation(.easeInOut(duration: 0.1)) { showCopied = false }
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
