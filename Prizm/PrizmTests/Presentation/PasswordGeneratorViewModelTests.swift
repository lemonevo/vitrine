import XCTest
@testable import Prizm

@MainActor
final class PasswordGeneratorViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var provider: MockRandomnessProvider!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "PasswordGeneratorViewModelTests")!
        defaults.removePersistentDomain(forName: "PasswordGeneratorViewModelTests")
        provider = MockRandomnessProvider()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "PasswordGeneratorViewModelTests")
        try await super.tearDown()
    }

    func testInit_generatesValueImmediately() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        XCTAssertFalse(vm.generatedValue.isEmpty)
    }

    func testConfigChange_triggersRegeneration() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        let first = vm.generatedValue
        vm.length = 32
        // Value should change (different length = different output).
        XCTAssertNotEqual(vm.generatedValue.count, first.count)
    }

    func testModeSwitch_triggersRegeneration() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        vm.mode = .passphrase
        XCTAssertTrue(vm.generatedValue.contains("-"))
    }

    func testCopyToClipboard_writesToPasteboard() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        vm.copyToClipboard()
        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, vm.generatedValue)
    }

    func testSettingsPersisted_toUserDefaults() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        vm.length = 42
        vm.mode = .passphrase

        // Load a new VM from the same defaults — should restore.
        let provider2 = MockRandomnessProvider()
        let vm2 = PasswordGeneratorViewModel(provider: provider2, defaults: defaults)
        XCTAssertEqual(vm2.length, 42)
        XCTAssertEqual(vm2.mode, .passphrase)
    }

    func testDefaultsRestored_onFirstLaunch() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        XCTAssertEqual(vm.mode, .password)
        XCTAssertEqual(vm.length, 16)
        XCTAssertEqual(vm.wordCount, 6)
        XCTAssertTrue(vm.includeUppercase)
        XCTAssertTrue(vm.includeLowercase)
        XCTAssertTrue(vm.includeDigits)
        XCTAssertTrue(vm.includeSymbols)
        XCTAssertFalse(vm.avoidAmbiguous)
        XCTAssertEqual(vm.separator, "-")
        XCTAssertFalse(vm.capitalize)
        XCTAssertFalse(vm.includeNumber)
    }

    // MARK: - Strength readout

    /// The popover shows the score of the value it just produced, so the two must agree. The
    /// estimator is injected rather than defaulted so the assertion does not depend on whether the
    /// EFF word list happens to be reachable from the test bundle.
    func testStrength_scoresTheGeneratedValue() {
        let estimator = PasswordStrengthEstimator()
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults,
                                            estimator: estimator)
        XCTAssertNotNil(vm.strength)
        XCTAssertEqual(vm.strength, estimator.estimate(vm.generatedValue))
    }

    /// Showing the score beside the length slider is only useful if moving the slider moves the
    /// score, so this pins the recomputation rather than any particular value.
    /// Unwrapped with `XCTUnwrap` rather than `!` after an `XCTAssertNotNil`.
    ///
    /// `XCTAssertNotNil` reports a failure and lets execution continue, so the `!` that used to
    /// follow it unwrapped a value the assertion had just said might be nil — and a trap takes the
    /// whole run down, hiding every result after it. Unwrapping by throwing stops at this test
    /// instead of at the process.
    func testStrength_isRecomputedWhenTheLengthChanges() throws {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        let before = try XCTUnwrap(vm.strength, "the initial value should have been scored")
        vm.length = 128

        let after = try XCTUnwrap(vm.strength, "changing the length should re-score the new value")
        XCTAssertGreaterThan(after.guessesLog10, before.guessesLog10)
    }

    /// A failed generation leaves no value on screen, so it must leave no score either — a bar
    /// beside an error message would be scoring nothing.
    func testStrength_isClearedWhenGenerationFails() {
        let vm = PasswordGeneratorViewModel(provider: FailingRandomnessProvider(),
                                            defaults: defaults)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.strength)
    }

    // MARK: - Clipboard interval

    /// The clear delay must come from Settings, not from a constant.
    ///
    /// Asserting on the scheduled task is how that is provable without waiting the interval out:
    /// `.never` means no task at all, and a hardcoded delay would schedule one whatever the setting
    /// says. The delay itself is `ClipboardClearIntervalTests`' subject, not this suite's.
    func testCopy_schedulesNoClearWhenTheIntervalIsNever() {
        ClipboardClearInterval.save(.never, to: defaults)
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)

        vm.copyToClipboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), vm.generatedValue)
        XCTAssertNil(vm.clipboardClearTask)
    }

    func testCopy_schedulesAClearWhenAnIntervalIsConfigured() {
        ClipboardClearInterval.save(.tenSeconds, to: defaults)
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)

        vm.copyToClipboard()

        XCTAssertNotNil(vm.clipboardClearTask)
    }

    // MARK: - History

    func testCopy_recordsTheValueInTheHistory() {
        let history = GeneratorHistory()
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, history: history)

        vm.copyToClipboard()

        XCTAssertEqual(history.entries.map(\.value), [vm.generatedValue])
    }

    func testAccept_recordsTheValueInTheHistory() {
        let history = GeneratorHistory()
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, history: history)

        vm.accept()

        XCTAssertEqual(history.entries.map(\.value), [vm.generatedValue])
    }

    /// The spec records a value when it is *used*. The length slider regenerates on every step, so
    /// recording on generation would fill a 20-slot buffer with values the user never looked at.
    func testRegenerating_doesNotRecordAnything() {
        let history = GeneratorHistory()
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, history: history)

        for _ in 1...5 { vm.generate() }

        XCTAssertTrue(history.entries.isEmpty)
    }

    /// Copying an entry is not a new generation. Re-recording it would move it to the top and, with
    /// repeated copies, let one value fill the list.
    func testCopyingFromTheHistory_doesNotRecordAgain() {
        let history = GeneratorHistory()
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, history: history)
        history.append("older")
        history.append("newer")

        vm.copyHistoryEntry(history.entries[1])

        XCTAssertEqual(history.entries.map(\.value), ["newer", "older"])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "older")
    }

    /// Without a history the view model still works — that is what keeps previews, and every test
    /// above, constructible without one.
    func testWithoutAHistory_copyAndAcceptStillWork() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)

        vm.copyToClipboard()
        vm.accept()

        XCTAssertTrue(vm.historyEntries.isEmpty)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), vm.generatedValue)
    }

    /// The section renders `historyEntries`, and the list is shared: a second popover opened from
    /// another field appends to the same history, so this view model has to reflect that.
    func testHistoryEntries_followTheSharedHistory() {
        let history = GeneratorHistory()
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults, history: history)

        history.append("from-elsewhere")

        XCTAssertEqual(vm.historyEntries.map(\.value), ["from-elsewhere"])
    }
}

// MARK: - FailingRandomnessProvider

/// A provider that always fails, for the generation-error path.
private struct FailingRandomnessProvider: RandomnessProvider {

    struct Failure: Error {}

    func randomBytes(count: Int) throws -> [UInt8] {
        throw Failure()
    }
}
