import Foundation

/// Forces the app's UI language at the *bundle* level.
///
/// The app previously switched language only through SwiftUI's `\.locale`,
/// which localizes `Text("literal")` but NOT `String(localized:)`, date
/// formatters, or anything resolved against `Bundle.main` directly. That made
/// "English" appear to do nothing on a non-English device and left Urdu
/// half-translated. Swapping `Bundle.main`'s class so its `localizedString`
/// consults the chosen language's `.lproj` makes every localized lookup —
/// `Text`, `String(localized:)`, and framework strings — follow the in-app
/// choice. Combined with `\.locale` (formatting/RTL) it fully switches the UI.
final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = LanguageManager.overrideBundle {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum LanguageManager {
    /// The `.lproj` bundle for the forced language, or nil to follow the system.
    static private(set) var overrideBundle: Bundle?
    private static var installed = false

    /// Apply the chosen app language. Safe to call repeatedly (at launch and
    /// whenever the setting changes). Call on the main thread.
    static func apply(_ language: AppLanguage) {
        if !installed {
            object_setClass(Bundle.main, LanguageBundle.self)
            installed = true
        }
        if let code = language.forcedLocaleIdentifier,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            overrideBundle = bundle
        } else {
            overrideBundle = nil
        }
    }

    /// The locale to drive formatting/RTL for the chosen language.
    static func locale(for language: AppLanguage) -> Locale {
        DisplayNumerals.locale(Locale(identifier: language.forcedLocaleIdentifier ?? Locale.autoupdatingCurrent.identifier))
    }
}

/// Presentation only; identifiers, calculations and stored values retain their original form.
enum DisplayNumerals {
    static func countdown(_ seconds: TimeInterval, locale: Locale) -> String {
        let total = Int(max(0, ceil(seconds)))
        let raw = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
        return text(raw, locale: locale)
    }

    static func locale(_ base: Locale) -> Locale {
        guard base.language.languageCode?.identifier == "ur" else { return base }
        var components = Locale.Components(locale: base)
        components.numberingSystem = Locale.NumberingSystem("arabext")
        return Locale(components: components)
    }

    static func text(_ value: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "ur" else { return value }
        return String(String.UnicodeScalarView(value.unicodeScalars.map { scalar in
            (48...57).contains(scalar.value) ? UnicodeScalar(0x06F0 + scalar.value - 48)! : scalar
        }))
    }
}
