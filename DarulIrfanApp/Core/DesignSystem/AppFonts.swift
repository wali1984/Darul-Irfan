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
        for base in ["AmiriQuran-Regular", "NotoNastaliqUrdu-Regular"] {
            guard let url = bundleURL(base) else {
                print("[AppFonts] NOT FOUND in bundle: \(base).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            print("[AppFonts] \(base): \(ok ? "registered" : "already/failed")")
        }
        // Force name resolution now that registration has run.
        _ = quranArabicName
        _ = urduName
    }

    /// The usable font name for Quran Arabic (Amiri Quran), or the system font
    /// name if the bundled face could not be loaded.
    static let quranArabicName: String = resolve(
        ["AmiriQuran-Regular", "Amiri Quran", "AmiriQuran"]
    )

    /// The usable font name for Urdu Nastaliq (Noto Nastaliq Urdu).
    static let urduName: String = resolve(
        ["NotoNastaliqUrdu-Regular", "Noto Nastaliq Urdu", "NotoNastaliqUrdu"]
    )

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
        print("[AppFonts] none of \(candidates) resolved; falling back to system")
        return candidates.first ?? "System"
    }
}
