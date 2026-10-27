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
        // The bundled Noto Nastaliq is registered only on a system that lacks
        // its own copy. See `urduName` for why the system one must win.
        var bundled = ["AlQuran-IndoPak-QuranWBW", "AmiriQuran-Regular"]
        if UIFont(name: systemUrduName, size: 16) == nil {
            bundled.append("NotoNastaliqUrdu-Regular")
        }
        for base in bundled {
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
        _ = urduName
    }

    /// The usable font name for Quran Arabic — the IndoPak QuranWBW mushaf face.
    /// The jazm is rendered via U+0652 (a hook) rather than U+06E1 (a ring) in
    /// the bundled text, so it reads like a traditional mushaf, not a field of
    /// circles. Falls back to Amiri Quran, then the system font.
    static let quranArabicName: String = resolve(
        ["AlQuran-IndoPak-by-QuranWBW", "AlQuran IndoPak by QuranWBW",
         "AmiriQuran-Regular", "Amiri Quran", "AmiriQuran"]
    )

    /// The usable font name for Urdu Nastaliq (Noto Nastaliq Urdu).
    ///
    /// iOS's own copy comes first. The bundled file is Google's variable
    /// OpenType build, whose Nastaliq relies on cursive-attachment and
    /// contextual lookups that Core Text does not apply as the font expects:
    /// letters lose their joins and long passages read as runs of detached
    /// bowls ("noon noon"). Apple ships the same design converted for its own
    /// shaper, so the system face renders correctly; the bundled one is kept
    /// only as a fallback for a system without it.
    static let urduName: String = resolve(
        [systemUrduName, "NotoNastaliqUrdu-Regular", "Noto Nastaliq Urdu"]
    )

    /// PostScript name of the Noto Nastaliq Urdu that ships with iOS.
    private static let systemUrduName = "NotoNastaliqUrdu"

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
