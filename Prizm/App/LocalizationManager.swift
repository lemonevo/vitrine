//
//  LocalizationManager.swift
//  Prizm
//

import Combine
import Foundation
import os.log

// MARK: - Lookup helpers

/// Resolves `key` against the currently selected language.
///
/// Equivalent to `String(localized:)`, but routed through `LocalizationManager`
/// explicitly instead of relying on how the standard library implements its own
/// bundle lookup. That matters because the interface language is a *runtime* choice
/// here: a swizzled `Bundle.main` is what `Text("…")` uses, but a direct call is
/// both easier to reason about and immune to standard-library changes.
///
/// Nonisolated so it can be used from error descriptions, formatters, and other
/// places that are not main-actor isolated.
///
/// ```swift
/// alert.messageText = L("Sign Out")
/// let reason = L("%@ is unavailable for this build.", name)
/// ```
nonisolated func L(_ key: String, _ arguments: CVarArg...) -> String {
    let bundle = LocalizedBundle.overrideBundle ?? .main
    let format = bundle.localizedString(forKey: key, value: nil, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, arguments: arguments)
}

/// A nonisolated snapshot of the active language, for code that runs outside the
/// main actor — date formatters, error descriptions, anything reachable from a
/// background task.
///
/// `LocalizationManager` is main-actor isolated because it publishes to SwiftUI, but
/// formatting a sync label or building an error string should not have to hop actors
/// just to read a language code. Values here are written only by
/// `LocalizationManager`, and only on the main actor.
nonisolated enum ActiveLocalization {

    /// The `.lproj` code currently in effect ("en", "zh-Hans").
    nonisolated(unsafe) static var languageCode: String = AppLanguage.systemPreferredCode

    /// A `Locale` matching `languageCode`, for date and number formatting.
    ///
    /// Kept separate from the user's region settings: a Chinese interface should show
    /// Chinese month names even when the region is set to the United States.
    nonisolated(unsafe) static var locale = Locale(identifier: languageCode)
}

// MARK: - LocalizedBundle

/// A `Bundle` subclass whose only job is to redirect string lookups.
///
/// ## Why this exists
///
/// SwiftUI resolves `Text("Some key")` through `Bundle.main`, and it caches the
/// resolved string inside the view value. Setting `\.locale` in the environment
/// changes date and number formatting but does **not** re-point string lookups at a
/// different `.lproj` — so a language picker built on `Locale` alone appears to do
/// nothing at all.
///
/// Swapping `Bundle.main`'s class for this one means every `Text("…")`,
/// `NSLocalizedString`, and `String(localized:)` lookup consults the chosen language
/// instead. That is what lets the whole interface localise without touching ~200
/// `Text` call sites.
///
/// ## Why the override bundle is a static
///
/// `object_setClass` does not allocate storage for subclass ivars — the instance was
/// created as a plain `Bundle`. Adding a stored property here would write past the
/// end of the allocation. A `static` lives outside the instance, so it is safe.
///
/// `nonisolated` because the module defaults to `MainActor` isolation, which would
/// otherwise make the inherited `Bundle` initialisers main-actor isolated and clash
/// with their nonisolated superclass declarations.
nonisolated final class LocalizedBundle: Bundle, @unchecked Sendable {

    /// The bundle for the selected language, or `nil` to let Foundation resolve
    /// normally (which yields the system language).
    ///
    /// `nonisolated(unsafe)` because string lookups happen on whatever thread AppKit
    /// or SwiftUI is on. Writes only ever come from `LocalizationManager` on the main
    /// actor, and the value is only ever replaced wholesale — never mutated in place.
    nonisolated(unsafe) static var overrideBundle: Bundle?

    /// Whether `Bundle.main`'s class has already been swapped.
    nonisolated(unsafe) private static var installed = false

    /// Swaps `Bundle.main`'s class for `LocalizedBundle`. Idempotent.
    static func install() {
        guard !installed else { return }
        guard object_getClass(Bundle.main) !== LocalizedBundle.self else {
            installed = true
            return
        }
        object_setClass(Bundle.main, LocalizedBundle.self)
        installed = true
    }

    /// Called by every string lookup on `Bundle.main`.
    ///
    /// `super` is only reached when no language override is active, which keeps
    /// "follow the system" behaving exactly like a stock app.
    nonisolated override func localizedString(
        forKey key: String,
        value: String?,
        table tableName: String?
    ) -> String {
        guard let override = Self.overrideBundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return override.localizedString(forKey: key, value: value, table: tableName)
    }
}

// MARK: - LocalizationManager

/// Owns the active interface language and keeps `Bundle.main` pointed at the right
/// `.lproj` folder.
///
/// A single shared instance is used because the language is global state that
/// `Bundle.main` has to reflect — there is no sensible way to have two.
///
/// Views still have to be rebuilt for the new strings to appear, which `PrizmApp`
/// forces by keying the root view on `language` with `.id()`.
@MainActor
final class LocalizationManager: ObservableObject {

    static let shared = LocalizationManager()

    /// `UserDefaults` key holding the raw `AppLanguage` value.
    static let defaultsKey = "appLanguage"

    /// The user's picker selection, including `.system`.
    @Published private(set) var selection: AppLanguage

    /// The concrete language in effect — `selection.resolvedCode`.
    ///
    /// Distinct from `selection` because `.system` has no `.lproj` of its own: this
    /// is the language actually being displayed, and it is what the root view is
    /// keyed on.
    @Published private(set) var language: String

    private let logger = Logger(subsystem: "com.prizm", category: "LocalizationManager")

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppLanguage.system.rawValue
        let selection = AppLanguage(rawValue: stored) ?? .system

        self.selection = selection
        self.language  = selection.resolvedCode

        LocalizedBundle.install()
        Self.applyOverride(for: selection)

        ActiveLocalization.languageCode = selection.resolvedCode
        ActiveLocalization.locale       = Locale(identifier: selection.resolvedCode)

        logger.info("Interface language: \(self.language, privacy: .public) (selection: \(selection.rawValue, privacy: .public))")
    }

    /// Switches language, persists the choice, and republishes so SwiftUI rebuilds.
    ///
    /// The `@Published` write on `language` is what drives `.id()` in `PrizmApp`;
    /// without it the bundle would change but the on-screen strings would not.
    func setLanguage(_ newValue: AppLanguage) {
        applyLanguage(newValue, persist: true)
    }

    /// Applies a language, optionally persisting it.
    ///
    /// `persist: false` exists so tests can pin a language without writing to
    /// `UserDefaults`, which would otherwise leak into the user's real settings when
    /// tests run inside the app's container.
    func applyLanguage(_ newValue: AppLanguage, persist: Bool) {
        guard newValue != selection else { return }

        selection = newValue
        if persist {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
        }

        Self.applyOverride(for: newValue)

        // Keep the nonisolated snapshot in step before publishing, so anything that
        // re-renders in response already sees the new language.
        ActiveLocalization.languageCode = newValue.resolvedCode
        ActiveLocalization.locale       = Locale(identifier: newValue.resolvedCode)

        language = newValue.resolvedCode

        logger.info("Interface language changed → \(self.language, privacy: .public)")
    }

    /// Points `Bundle.main` at the right `.lproj`, or clears the override so
    /// Foundation's own resolution — and therefore the system language — applies.
    ///
    /// A missing `.lproj` also clears the override rather than failing loudly: an
    /// untranslated build should fall back to the development language, not crash.
    private static func applyOverride(for selection: AppLanguage) {
        guard selection != .system else {
            LocalizedBundle.overrideBundle = nil
            return
        }

        guard let path = Bundle.main.path(forResource: selection.resolvedCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            LocalizedBundle.overrideBundle = nil
            return
        }

        LocalizedBundle.overrideBundle = bundle
    }
}
