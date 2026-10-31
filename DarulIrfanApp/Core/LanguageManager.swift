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
        var components = Locale.Components(locale: Locale(identifier: language.forcedLocaleIdentifier ?? Locale.autoupdatingCurrent.identifier))
        components.numberingSystem = Locale.NumberingSystem("latn")
        return Locale(components: components)
    }
}

enum DailyNoorText {
    static func translation(urdu: String?, english: String?, readsUrdu: Bool) -> String? {
        let ur = urdu.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let en = english.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return readsUrdu ? ur : (en ?? ur)
    }

    static func localized(_ key: String, urdu: Bool) -> String {
        guard let path = Bundle.main.path(forResource: urdu ? "ur" : "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func reference(_ value: String, urdu: Bool) -> String {
        guard urdu else { return value }
        return value.replacingOccurrences(of: "Qur'an", with: "قرآن")
            .replacingOccurrences(of: "Quran", with: "قرآن")
            .replacingOccurrences(of: "Sahih al-Bukhari", with: "صحیح بخاری")
            .replacingOccurrences(of: "Sahih Muslim", with: "صحیح مسلم")
    }
}
