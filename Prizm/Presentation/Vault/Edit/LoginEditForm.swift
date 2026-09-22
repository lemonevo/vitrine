import SwiftUI

// MARK: - LoginEditForm

/// Edit form for Login vault items.
///
/// Mirrors the layout of `LoginDetailView`: Credentials card, Websites card,
/// Notes card, Custom Fields card. URIs can be added, removed, and reordered.
/// Password is masked by default.
struct LoginEditForm: View {

    @Binding var draft: DraftLoginContent

    /// The estimate for `draft.password`, supplied by `ItemEditViewModel`.
    ///
    /// Passed in rather than computed here so there is exactly one estimator in the app and the
    /// form stays a form. `nil` draws nothing.
    var passwordStrength: StrengthEstimate? = nil

    /// Whether the seed currently in the field will produce a code, or `nil` when the field is
    /// empty. `false` is the only interesting case and draws a warning; see
    /// `ItemEditViewModel.totpSeedProducesCode`.
    var seedProducesCode: Bool? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                DetailSectionCard(L("Credentials")) {
                    OptionalEditFieldRow(label: L("Username"), value: $draft.username)
                    Divider()
                    MaskedEditFieldRow(label: L("Password"), value: $draft.password, generatorBinding: $draft.password)
                    if passwordStrength != nil {
                        PasswordStrengthReadout(
                            estimate: passwordStrength,
                            identifier: AccessibilityID.Edit.passwordStrength
                        )
                        .padding(.horizontal, Spacing.rowHorizontal)
                        .padding(.bottom, Spacing.rowVertical)
                    }
                }

                DetailSectionCard(L("Authenticator Key (TOTP)")) {
                    MaskedEditFieldRow(label: L("Key"), value: $draft.totp)
                    Divider()
                    if seedProducesCode == false {
                        Label {
                            Text(L("This key will not produce a code. Paste the secret, or the otpauth:// URL the site shows when you cannot scan its QR code."))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.rowHorizontal)
                        .padding(.vertical, Spacing.rowVertical)
                        .accessibilityIdentifier(AccessibilityID.Edit.totpSeedWarning)
                    } else {
                        Text(L("Paste the secret, or the otpauth:// URL the site shows when you cannot scan its QR code."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.rowHorizontal)
                            .padding(.vertical, Spacing.rowVertical)
                    }
                }

                DetailSectionCard(L("Websites")) {
                    ForEach(draft.uris) { uri in
                        if let index = draft.uris.firstIndex(where: { $0.id == uri.id }) {
                            if index > 0 { Divider() }
                            URIEditRow(
                                uri: $draft.uris[index],
                                canMoveUp: index > 0,
                                canMoveDown: index < draft.uris.count - 1,
                                showReorderButtons: draft.uris.count > 1,
                                onMoveUp: {
                                    guard let i = draft.uris.firstIndex(where: { $0.id == uri.id }), i > 0 else { return }
                                    draft.uris.swapAt(i, i - 1)
                                },
                                onMoveDown: {
                                    guard let i = draft.uris.firstIndex(where: { $0.id == uri.id }), i < draft.uris.count - 1 else { return }
                                    draft.uris.swapAt(i, i + 1)
                                },
                                onRemove: {
                                    guard let i = draft.uris.firstIndex(where: { $0.id == uri.id }) else { return }
                                    draft.uris.remove(at: i)
                                }
                            )
                        }
                    }
                    if !draft.uris.isEmpty { Divider() }
                    Button {
                        draft.uris.append(DraftLoginURI())
                    } label: {
                        Label("Add Website", systemImage: "plus")
                            .font(Typography.fieldValue)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, Spacing.rowVertical)
                    .padding(.horizontal, Spacing.rowHorizontal)
                }

                DetailSectionCard(L("Notes")) {
                    OptionalEditFieldRow(label: L("Notes"), value: $draft.notes)
                }

                CustomFieldsEditSection(fields: $draft.customFields, itemType: .login)
            }
        }
    }
}

// MARK: - URIEditRow

/// An editable row for a single LoginURI, with match-type picker, reorder, and remove controls.
private struct URIEditRow: View {

    @Binding var uri: DraftLoginURI
    let canMoveUp: Bool
    let canMoveDown: Bool
    let showReorderButtons: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    @State private var showMatchType = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if showReorderButtons {
                    VStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(Typography.utility)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Move up")
                        .disabled(!canMoveUp)

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(Typography.utility)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Move down")
                        .disabled(!canMoveDown)
                    }
                    .padding(.leading, Spacing.rowHorizontal)
                }

                EditFieldRow(label: L("Website"), text: $uri.uri)

                Button {
                    optionalAnimation(.easeInOut(duration: 0.2)) {
                        showMatchType.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(showMatchType ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Match type settings")

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove website")
                .padding(.trailing, Spacing.rowHorizontal)
            }
            if showMatchType {
                Divider()
                HStack {
                    Text("Match Type")
                        .font(Typography.fieldLabel)
                        .foregroundStyle(.secondary)
                        .padding(.leading, Spacing.rowHorizontal)
                    Spacer()
                    Picker("Match Type", selection: $uri.matchType) {
                        Text(L("Default")).tag(URIMatchType?.none)
                        ForEach(URIMatchType.selectable, id: \.self) { type in
                            Text(type.displayName).tag(URIMatchType?.some(type))
                        }
                        // A strategy this build cannot name is shown as the number it is, so the row
                        // neither disappears nor silently becomes "Default" under the user's cursor.
                        if let current = uri.matchType, case .unknown(let raw) = current {
                            Text(L("Unknown (%d)", raw)).tag(URIMatchType?.some(current))
                        }
                    }
                    .labelsHidden()
                    .padding(.trailing, Spacing.rowHorizontal)
                }
                .padding(.vertical, Spacing.rowVertical)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - URIMatchType + Helpers

private extension URIMatchType {
    var displayName: String {
        switch self {
        case .defaultMatch:      return L("Default")
        case .baseDomain:        return L("Base domain")
        case .host:              return L("Host")
        case .startsWith:        return L("Starts With")
        case .exact:             return L("Exact")
        case .regularExpression: return L("Regular Expression")
        case .never:             return L("Never")
        case .unknown(let raw):  return L("Unknown (%d)", raw)
        }
    }
}
