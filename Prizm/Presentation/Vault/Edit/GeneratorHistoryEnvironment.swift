import SwiftUI

// MARK: - GeneratorHistory in the environment

/// Carries the session's `GeneratorHistory` down to the password generator popover.
///
/// The generator view model is created deep inside `MaskedEditFieldRow`, as a `@State` object made
/// when the wand button is first pressed. Threading the history down as a parameter would mean four
/// views that otherwise know nothing about it (`ItemEditView`, `LoginEditForm`, the row, the
/// popover) each carrying it. The environment is the mechanism SwiftUI provides for exactly this
/// shape: set once at the vault root, read where it is needed.
///
/// Deliberately optional, with `nil` as the default. `@EnvironmentObject` would trap at runtime when
/// nothing was injected, which would make every preview and every view test that renders the row
/// crash; a generator opened without a history simply records nothing.
private struct GeneratorHistoryEnvironmentKey: EnvironmentKey {
    nonisolated static var defaultValue: GeneratorHistory? { nil }
}

extension EnvironmentValues {
    var generatorHistory: GeneratorHistory? {
        get { self[GeneratorHistoryEnvironmentKey.self] }
        set { self[GeneratorHistoryEnvironmentKey.self] = newValue }
    }
}
