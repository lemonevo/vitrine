import SwiftUI

// MARK: - PasskeysSection

/// The passkeys registered on a login item, listed read-only.
///
/// **"Read-only" is the whole feature.** Every other list in the detail view offers a copy button
/// or a reveal toggle, so the absence of any control here needs saying rather than leaving to be
/// noticed: the footnote names what Prizm cannot do *and* where it can be done. A list of passkeys
/// with no such note reads as a feature that has failed to load.
///
/// **The one value this section must never touch.** Each credential carries `keyValue`, which is
/// the passkey's **private** key — see `PasskeyCredential`. There is no field for it on the type
/// and no control here that could surface one, which is what makes "never displayed" a property of
/// the code instead of a promise in a comment.
///
/// **Collapsed by default, like the password history**, and for the same reason: opening it is what
/// decrypts anything. Unlike the history it keeps nothing that needs the master-password gate, so
/// it takes no `RevealGateBinding` — there is no secret here to gate.
struct PasskeysSection: View {

    @ObservedObject var viewModel: PasskeysViewModel

    @State private var isExpanded = false

    var body: some View {
        DetailSectionCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                content
                    .padding(.top, 6)
            } label: {
                HStack(spacing: 6) {
                    Text(L("Passkeys"))
                        .font(.headline)

                    if let count = viewModel.credentialCount {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L("%d entries", count))
                            .accessibilityIdentifier(AccessibilityID.Passkeys.countBadge)
                    }
                }
            }
            .padding(.horizontal, Spacing.rowHorizontal)
            .padding(.vertical, 14)
            .accessibilityIdentifier(AccessibilityID.Passkeys.section)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                Task { await viewModel.load() }
            } else {
                viewModel.clear()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(AccessibilityID.Passkeys.progress)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.Passkeys.errorMessage)

        case .loaded(let credentials):
            VStack(alignment: .leading, spacing: 6) {
                if credentials.isEmpty {
                    Text(L("No passkeys recorded."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.Passkeys.emptyState)
                } else {
                    ForEach(Array(credentials.enumerated()), id: \.offset) { index, credential in
                        row(credential, index: index)
                    }
                }

                Text(L("Prizm cannot use these passkeys to sign in. Register, use and remove them from another Bitwarden client."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.Passkeys.limitationNote)
            }
        }
    }

    private func row(_ credential: PasskeyCredential, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.rpId)
                    .font(Typography.fieldValue)
                    .accessibilityIdentifier(AccessibilityID.Passkeys.rpId(index))

                // The name a site gave itself is a nicety; the id above is what identifies it, so
                // this is omitted rather than rendered as an empty second line.
                if let rpName = credential.rpName, !rpName.isEmpty, rpName != credential.rpId {
                    Text(rpName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let userName = credential.userName, !userName.isEmpty {
                    Text(userName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.Passkeys.userName(index))
                }
            }

            Spacer(minLength: 8)

            if let date = credential.creationDate {
                Text(date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier(AccessibilityID.Passkeys.date(index))
            }
        }
    }
}
