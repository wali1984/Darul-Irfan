import SwiftUI
import UIKit
import CoreText

/// Bulletproof custom-font loading. `UIAppFonts` alone can silently fail to
/// register a bundled font (path/flattening quirks), which makes `Font.custom`
/// fall back to the system face. So we ALSO register the bundled `.ttf` files
/// programmatically at launch, then resolve the exact usable font name by
/// probing `UIFont(name:)` across the PostScript and family-name candidates.
enum AppFonts {

    /// Registers the bundled fonts with Core Text. Call once, first thing at
    /// launch (before any `Font.custom` is evaluated). Idempotent — a font
    /// already registered via UIAppFonts just reports an "already registered"
    /// error which we ignore.
    static func registerBundledFonts() {
        for base in ["AlQuran-IndoPak-QuranWBW", "AmiriQuran-Regular"] {
            guard let url = bundleURL(base) else {
                AppLog.presentation("Font not found in bundle: \(base).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            AppLog.presentation("Font \(base): \(ok ? "registered" : "already registered or failed")")
        }
        // Force name resolution now that registration has run.
        _ = quranArabicName
        AppLog.presentation("Apple Nastaliq: \(appleNastaliqName ?? "not on this device")")
    }

    /// The usable font name for Quran Arabic — the IndoPak QuranWBW mushaf face.
    /// The jazm is rendered via U+0652 (a hook) rather than U+06E1 (a ring) in
    /// the bundled text, so it reads like a traditional mushaf, not a field of
    /// circles. Falls back to Amiri Quran, then the system font.
    static let quranArabicName: String = resolve(
        ["AlQuran-IndoPak-by-QuranWBW", "AlQuran IndoPak by QuranWBW",
         "AmiriQuran-Regular", "Amiri Quran", "AmiriQuran"]
    )

    /// Apple's own Noto Nastaliq Urdu, when this device has it; nil otherwise.
    ///
    /// Google's OpenType Nastaliq (which this app used to bundle) relies on
    /// cursive-attachment and contextual lookups that Core Text does not
    /// apply as the font expects: on device the letters did not join. Only
    /// Apple's copy, converted for its own shaper, is ever used now, and only
    /// when the reader chooses it.
    static let appleNastaliqName: String? = UIFont.fontNames(forFamilyName: "Noto Nastaliq Urdu")
        .sorted()
        .first { !$0.localizedCaseInsensitiveContains("bold") }

    /// Settings key: true when the reader chose Nastaliq for Urdu text.
    static let nastaliqPreferenceKey = "reader.urduNastaliq"

    /// The Nastaliq face to use for Urdu, or nil for the system face, whose
    /// Naskh letters always join.
    static var urduNastaliqName: String? {
        guard UserDefaults.standard.bool(forKey: nastaliqPreferenceKey) else { return nil }
        return appleNastaliqName
    }

    // MARK: - Internals

    private static func bundleURL(_ base: String) -> URL? {
        Bundle.main.url(forResource: base, withExtension: "ttf")
            ?? Bundle.main.url(forResource: base, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: base, withExtension: "ttf", subdirectory: "Resources/Fonts")
    }

    /// Returns the first candidate name that Core Text can actually instantiate;
    /// otherwise the first candidate (which makes `Font.custom` fall back to the
    /// system face gracefully).
    private static func resolve(_ candidates: [String]) -> String {
        for name in candidates where UIFont(name: name, size: 16) != nil {
            return name
        }
        AppLog.presentation("No bundled font candidate resolved; falling back to system")
        return candidates.first ?? "System"
    }
}
