import Combine
import SwiftUI

/// ViewModel for the password generator popover.
/// Owns the config, generated value, and clipboard logic.
/// Instantiated as `@StateObject` inside `EditFieldRow` so plaintext
/// is released when the popover closes (design D7, Constitution §III).
@MainActor
final class PasswordGeneratorViewModel: ObservableObject {

    // MARK: - Published config properties

    @Published var mode: PasswordGeneratorConfig.Mode = .password { didSet { generate() } }
    @Published var length: Int = 16 { didSet { generate() } }
    @Published var includeUppercase: Bool = true { didSet { generate() } }
    @Published var includeLowercase: Bool = true { didSet { generate() } }
    @Published var includeDigits: Bool = true { didSet { generate() } }
    @Published var includeSymbols: Bool = true { didSet { generate() } }
    @Published var avoidAmbiguous: Bool = false { didSet { generate() } }
    @Published var wordCount: Int = 6 { didSet { generate() } }
    @Published var separator: String = "-" { didSet { generate() } }
    @Published var capitalize: Bool = false { didSet { generate() } }
    @Published var includeNumber: Bool = false { didSet { generate() } }

    // MARK: - Output

    @Published private(set) var generatedValue: String = ""
    @Published private(set) var errorMessage: String?

    /// The estimate for `generatedValue`, recomputed on every generation.
    ///
    /// The generator already knows what it produced and why, so scoring it costs nothing extra and
    /// lets the popover show the consequence of the length slider before the password is used.
    /// `nil` when there is nothing to score.
    @Published private(set) var strength: StrengthEstimate?

    /// The session's generated values, newest first.
    ///
    /// Computed, not stored: the list lives in `GeneratorHistory` so it can outlive this popover —
    /// and be cleared when the vault locks — and a copy here would be one more thing to keep in step
    /// with it.
    var historyEntries: [GeneratorHistoryEntry] { history?.entries ?? [] }

    // MARK: - Dependencies

    private let provider: RandomnessProvider
    private let generator = PasswordGenerator()
    private let estimator: PasswordStrengthEstimator
    private let defaults: UserDefaults
    /// The session history. `nil` where there is none to write to — previews, and tests that do not
    /// exercise it — so the view model stays constructible without one.
    private let history: GeneratorHistory?
    /// Keeps the view in step with the history. `historyEntries` is computed, so a change made
    /// anywhere else has to be forwarded or the section would go stale.
    private var historySubscription: AnyCancellable?
    /// The pending clipboard-clear task, or `nil` when nothing is scheduled.
    ///
    /// Not `private` only so the test target can assert that a copy honours the *configured*
    /// interval. The presence of a task is what distinguishes "read the setting" from "hardcoded
    /// 30 seconds", and the alternative is a test that waits the interval out. Production code
    /// never reads it.
    private(set) var clipboardClearTask: Task<Void, Never>?
    private var isInitializing = true

    // MARK: - Init

    init(provider: RandomnessProvider,
         defaults: UserDefaults = .standard,
         estimator: PasswordStrengthEstimator = .application,
         history: GeneratorHistory? = nil) {
        self.provider = provider
        self.defaults = defaults
        self.estimator = estimator
        self.history = history
        let config = PasswordGeneratorConfig.load(from: defaults)
        self.mode = config.mode
        self.length = config.length
        self.includeUppercase = config.includeUppercase
        self.includeLowercase = config.includeLowercase
        self.includeDigits = config.includeDigits
        self.includeSymbols = config.includeSymbols
        self.avoidAmbiguous = config.avoidAmbiguous
        self.wordCount = config.wordCount
        self.separator = config.separator
        self.capitalize = config.capitalize
        self.includeNumber = config.includeNumber
        isInitializing = false

        historySubscription = history?.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }

        generate()
    }

    deinit {
        clipboardClearTask?.cancel()
    }

    // MARK: - Actions

    func generate() {
        guard !isInitializing else { return }
        do {
            let config = currentConfig()
            switch mode {
            case .password:
                generatedValue = try generator.generatePassword(config: config, provider: provider)
            case .passphrase:
                generatedValue = try generator.generatePassphrase(config: config, provider: provider)
            }
            errorMessage = nil
            strength = estimator.estimate(generatedValue)
            config.save(to: defaults)
        } catch {
            errorMessage = L("Generation failed: %@", error.localizedDescription)
            generatedValue = ""
            strength = nil
        }
    }

    /// Copies the current value, applying the configured clipboard-clearing interval, and records
    /// it in the session history.
    func copyToClipboard() {
        copy(generatedValue)
        history?.append(generatedValue)
    }

    /// Records the current value as accepted. The caller writes it into the target field.
    ///
    /// Separate from `copyToClipboard` because they are different acts with the same consequence: a
    /// value the user chose to keep is worth remembering whether or not it passed through the
    /// clipboard.
    func accept() {
        history?.append(generatedValue)
    }

    /// Copies a value from the history back to the clipboard.
    ///
    /// Deliberately does not re-record it. Copying an entry is not a new generation, and
    /// re-appending would move that value to the top — with repeated copies, one value could fill
    /// the whole list.
    func copyHistoryEntry(_ entry: GeneratorHistoryEntry) {
        copy(entry.value)
    }

    /// Writes `value` to the clipboard and schedules the clear.
    ///
    /// The interval comes from Settings (`ClipboardClearInterval`), the same setting the vault
    /// browser honours. It used to be a hardcoded 30 seconds here, which meant the one screen most
    /// likely to put a password on the clipboard was the one screen the setting did not reach.
    private func copy(_ value: String) {
        guard !value.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        // Cancel any outstanding clear task before scheduling a new one: the newest copy owns the
        // clipboard, and an older task firing later would clear it early.
        clipboardClearTask?.cancel()
        clipboardClearTask = nil

        guard let seconds = ClipboardClearInterval.load(from: defaults).seconds else {
            // `.never` — the user has made a decision, and overriding it would be worse than the
            // risk it guards against.
            return
        }

        clipboardClearTask = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
                // Only clear if our value is still on the clipboard.
                if pasteboard.string(forType: .string) == value {
                    pasteboard.clearContents()
                }
            } catch {
                // Task cancelled — a newer copy owns the clipboard now.
            }
        }
    }

    // MARK: - Private

    private func currentConfig() -> PasswordGeneratorConfig {
        var config = PasswordGeneratorConfig()
        config.mode = mode
        config.length = length
        config.includeUppercase = includeUppercase
        config.includeLowercase = includeLowercase
        config.includeDigits = includeDigits
        config.includeSymbols = includeSymbols
        config.avoidAmbiguous = avoidAmbiguous
        config.wordCount = wordCount
        config.separator = separator
        config.capitalize = capitalize
        config.includeNumber = includeNumber
        return config
    }
}
