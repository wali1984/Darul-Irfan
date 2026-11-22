import SwiftUI

/// Where laid-out text is shown, for the display rules that hold only there.
enum BookTextPlace: Sendable {
    /// A book's pages.
    case book
    /// An article or a publication.
    case article
    /// A narration's translation.
    case hadith
    /// The tafsir under an ayah, which is drawn as the Qur'an reader draws it.
    case quranReader

    /// The rules of book and article text: the size of the salawat sign.
    var followsBookRules: Bool { self == .book || self == .article }
}

/// How book text is drawn where its face alone would not draw it well. The
/// stored words are never changed.
enum BookTextDrawing {
    /// U+FDFA, the salawat written as one sign.
    static let salawat: Unicode.Scalar = "\u{FDFA}"

    static func holdsSalawat(_ text: String) -> Bool {
        text.unicodeScalars.contains(salawat)
    }

    /// `text`, for an Urdu face at `scale`, with each salawat sign in the
    /// mushaf face a quarter larger than the words around it: Nastaliq draws
    /// the sign over three lines tall. Links and colours are kept.
    static func enlargingSalawat(_ text: AttributedString, scale: Double) -> AttributedString {
        var drawn = text
        let offsets = Array(text.unicodeScalars).enumerated().filter { $0.element == salawat }.map(\.offset)
        for offset in offsets {
            let lower = drawn.unicodeScalars.index(drawn.startIndex, offsetBy: offset)
            let upper = drawn.unicodeScalars.index(after: lower)
            drawn[lower..<upper].font = DIFont.urduSalawat(scale: scale)
        }
        return drawn
    }
}
