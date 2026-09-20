import SwiftUI

/// Password/passphrase generator popover.
/// Receives a binding to write the generated value into the target field.
struct PasswordGeneratorView: View {

    @ObservedObject var viewModel: PasswordGeneratorViewModel
    @Binding var targetValue: String?
    @Environment(\.dismiss) private var dismiss
    /// Collapsed by default, per the spec. Local to the popover and not persisted: whether the
    /// section was open last time is not worth remembering.
    @State private var isHistoryExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Mode picker
            Picker("Mode", selection: $viewModel.mode) {
                Text("Password").tag(PasswordGeneratorConfig.Mode.password)
                Text("Passphrase").tag(PasswordGeneratorConfig.Mode.passphrase)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.Generator.modePicker)

            Divider()

            // Mode-specific controls
            switch viewModel.mode {
            case .password:
                passwordControls
            case .passphrase:
                passphraseControls
            }

            Divider()

            // Preview area
            previewArea

            Divider()

            // Action row
            actionRow

            Divider()

            // Session history
            historyArea
        }
        .padding()
        .frame(width: 320)
    }

    // MARK: - Password controls

    @ViewBuilder
    private var passwordControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Length: \(viewModel.length)")
                    .font(Typography.fieldLabel)
                Spacer()
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.length) },
                    set: { viewModel.length = Int($0) }
                ),
                in: 5...128,
                step: 1
            )
            .accessibilityIdentifier(AccessibilityID.Generator.lengthSlider)

            Toggle("Uppercase (A–Z)", isOn: $viewModel.includeUppercase)
                .disabled(isLastEnabledSet(\.includeUppercase))
                .accessibilityIdentifier(AccessibilityID.Generator.uppercaseToggle)
            Toggle("Lowercase (a–z)", isOn: $viewModel.includeLowercase)
                .disabled(isLastEnabledSet(\.includeLowercase))
                .accessibilityIdentifier(AccessibilityID.Generator.lowercaseToggle)
            Toggle("Digits (0–9)", isOn: $viewModel.includeDigits)
                .disabled(isLastEnabledSet(\.includeDigits))
                .accessibilityIdentifier(AccessibilityID.Generator.digitsToggle)
            Toggle("Symbols (!@#$…)", isOn: $viewModel.includeSymbols)
                .disabled(isLastEnabledSet(\.includeSymbols))
                .accessibilityIdentifier(AccessibilityID.Generator.symbolsToggle)
            Toggle("Avoid ambiguous characters", isOn: $viewModel.avoidAmbiguous)
                .accessibilityIdentifier(AccessibilityID.Generator.avoidAmbiguousToggle)
        }
    }

    // MARK: - Passphrase controls

    @ViewBuilder
    private var passphraseControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Words: \(viewModel.wordCount)", value: $viewModel.wordCount, in: 3...10)
                .accessibilityIdentifier(AccessibilityID.Generator.wordCountStepper)
            HStack {
                Text("Separator")
                    .font(Typography.fieldLabel)
                TextField("Separator", text: $viewModel.separator)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .accessibilityIdentifier(AccessibilityID.Generator.separatorField)
            }
            Toggle("Capitalize each word", isOn: $viewModel.capitalize)
                .accessibilityIdentifier(AccessibilityID.Generator.capitalizeToggle)
            Toggle("Include number", isOn: $viewModel.includeNumber)
                .accessibilityIdentifier(AccessibilityID.Generator.includeNumberToggle)
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(Typography.fieldValue)
                        .foregroundStyle(.red)
                } else {
                    Text(viewModel.generatedValue)
                        .font(Typography.fieldValue.monospaced())
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(AccessibilityID.Generator.preview)
                }
                Spacer()
                Button {
                    viewModel.generate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Generate new")
                .accessibilityLabel("Generate new password")
                .accessibilityIdentifier(AccessibilityID.Generator.refreshButton)
            }
            .frame(minHeight: 40)

            // The score for the value above it. Not shown while a generation error is on screen —
            // the error is the message, and a strength bar beside it would be about nothing.
            PasswordStrengthReadout(estimate: viewModel.strength)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            Button("Copy") {
                viewModel.copyToClipboard()
            }
            .disabled(viewModel.errorMessage != nil)
            .accessibilityHint("Copies to clipboard")
            .accessibilityIdentifier(AccessibilityID.Generator.copyButton)

            Spacer()

            Button(viewModel.mode == .password ? L("Use Password") : L("Use Passphrase")) {
                // Recorded before the popover closes: this is the moment the value stops being a
                // candidate and becomes the password.
                viewModel.accept()
                targetValue = viewModel.generatedValue
                dismiss()
            }
            .disabled(viewModel.errorMessage != nil)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(AccessibilityID.Generator.useButton)
        }
    }

    // MARK: - History

    /// The values generated and used this session, newest first.
    ///
    /// Collapsed by default (spec `password-generator`): the popover exists to produce one password,
    /// and an expanded list of everything generated this session would dominate it. The footer
    /// states the lifetime because the list is memory-only — nothing on disk, gone on quit — and a
    /// user who assumed otherwise would be trusting a store that does not exist.
    @ViewBuilder
    private var historyArea: some View {
        DisclosureGroup(isExpanded: $isHistoryExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.historyEntries.isEmpty {
                    Text("Values you copy or use will appear here.")
                        .font(Typography.fieldLabel)
                        .foregroundStyle(.secondary)
                } else {
                    // The list is capped at 20 by `GeneratorHistory`, but the popover is only 320pt
                    // wide and would otherwise grow past the bottom of the screen.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(viewModel.historyEntries.enumerated()),
                                    id: \.element.id) { index, entry in
                                historyRow(entry, index: index)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                Text("Kept in memory only. Cleared when the vault locks.")
                    .font(Typography.fieldLabel)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        } label: {
            Text(L("History (%d)", viewModel.historyEntries.count))
                .font(Typography.fieldLabel)
        }
        .accessibilityIdentifier(AccessibilityID.Generator.historySection)
    }

    @ViewBuilder
    private func historyRow(_ entry: GeneratorHistoryEntry, index: Int) -> some View {
        HStack(spacing: 6) {
            Text(entry.value)
                .font(Typography.fieldValue.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(entry.value)

            Spacer(minLength: 4)

            // Time only, no date: everything in the list was generated during this session.
            Text(entry.generatedAt, format: .dateTime.hour().minute())
                .font(Typography.fieldLabel)
                .foregroundStyle(.secondary)

            Button {
                viewModel.copyHistoryEntry(entry)
            } label: {
                Image(systemName: "doc.on.doc")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(L("Copy"))
            .accessibilityLabel(L("Copy %@", entry.value))
            .accessibilityIdentifier(AccessibilityID.Generator.historyCopyButton(index))
        }
    }

    // MARK: - Helpers

    /// Returns `true` if the given toggle is the last enabled character set.
    private func isLastEnabledSet(_ keyPath: KeyPath<PasswordGeneratorViewModel, Bool>) -> Bool {
        let enabled = [
            viewModel.includeUppercase,
            viewModel.includeLowercase,
            viewModel.includeDigits,
            viewModel.includeSymbols
        ].filter { $0 }.count
        return enabled == 1 && viewModel[keyPath: keyPath]
    }
}
