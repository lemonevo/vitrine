//
//  AppLanguage.swift
//  Prizm
//

import Foundation

/// A language the interface can be shown in, plus a "follow the system" option.
///
/// `rawValue` is what gets persisted in `UserDefaults`. `.system` stores an empty
/// string, so a missing or unrecognised stored value also resolves to "follow the
/// system" — the default the user asked for on first launch.
///
/// `nonisolated` because the module defaults to `MainActor` isolation, but this is a
/// plain value type that `ActiveLocalization` reads from outside the main actor.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {

    /// Use whatever language macOS is set to, falling back to English.
    case system = ""

    case english = "en"

    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// Label for the language picker.
    ///
    /// Each language is named in its own script ("English", "简体中文") rather than
    /// translated, so the list stays readable no matter which language is active.
    /// Only `.system` needs translating, since it has no native name.
    var displayName: String {
        switch self {
        case .system:            return L("Follow System")
        case .english:           return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    /// The concrete `.lproj` to load — never empty, even for `.system`.
    ///
    /// Used for the SwiftUI `Locale` environment (date and number formatting) and as
    /// the `.id()` that forces a rebuild. `.system` resolves against the user's
    /// preferred languages so the app's own formatting matches the system.
    var resolvedCode: String {
        switch self {
        case .english:           return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .system:            return Self.systemPreferredCode
        }
    }

    /// First shipped language found in the user's preferred-language list.
    ///
    /// Falls back to English. `Locale.preferredLanguages` is the ordered list from
    /// System Settings → General → Language & Region, so the first match is the best
    /// available approximation of "the system language".
    static var systemPreferredCode: String {
        for preferred in Locale.preferredLanguages {
            if let match = match(preferred) { return match }
        }
        return english.rawValue
    }

    /// Maps a BCP-47 identifier (`"zh-Hans-CN"`, `"zh-Hant-TW"`, `"en-US"`) onto a
    /// shipped language, or `nil` when nothing matches.
    ///
    /// Traditional Chinese (`zh-Hant`) is not shipped; it falls back to Simplified
    /// rather than to English, because a Chinese reader gets far more from Simplified
    /// Chinese than from untranslated English.
    private static func match(_ identifier: String) -> String? {
        let lowercased = identifier.lowercased()
        if lowercased.hasPrefix("zh") { return simplifiedChinese.rawValue }
        if lowercased.hasPrefix("en") { return english.rawValue }
        return nil
    }
}
