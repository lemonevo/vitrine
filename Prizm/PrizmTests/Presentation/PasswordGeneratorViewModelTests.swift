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
    func testStrength_isRecomputedWhenTheLengthChanges() {
        let vm = PasswordGeneratorViewModel(provider: provider, defaults: defaults)
        let before = vm.strength
        vm.length = 128

        XCTAssertNotNil(before)
        XCTAssertNotNil(vm.strength)
        XCTAssertGreaterThan(vm.strength!.guessesLog10, before!.guessesLog10)
    }

    /// A failed generation leaves no value on screen, so it must leave no score either — a bar
    /// beside an error message would be scoring nothing.
    func testStrength_isClearedWhenGenerationFails() {
        let vm = PasswordGeneratorViewModel(provider: FailingRandomnessProvider(),
                                            defaults: defaults)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.strength)
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
