import SwiftUI

/// The IndoPak mushaf face maps some characters to glyphs with no outline.
/// They show as nothing, and as the glyphs exist Core Text never falls back,
/// so those characters are given another face here. The text is never changed.
///
/// Book, hadith and other free text set in that face goes through
/// `Text.mushaf`. The ayat hold none of these characters but U+06DF, and are
/// left as they are.
enum MushafFaceGaps {
    enum Face: Equatable {
        /// Digits, brackets and dashes, in Amiri Quran.
        case signs
        /// U+06DD with its number, whole in Amiri Quran, which sets the number
        /// inside the circle. The mushaf face loses the circle or the number.
        case marker
        /// A whole word holding U+06DF, in Amiri Quran, which has that sign.
        case smallHighZero
        /// A whole word, in the Urdu face, so that its letters join.
        case urdu
    }

    /// A stretch of text, counted in Unicode scalars.
    struct Span: Equatable {
        let range: Range<Int>
        let face: Face
    }

    /// U+0660 is absent: the mushaf face draws it.
    static let signs: Set<UInt32> = [
        0x0028, 0x0029, 0x002D,
        0x0661, 0x0662, 0x0663, 0x0664, 0x0665, 0x0666, 0x0667, 0x0668, 0x0669,
        0x2010, 0x2011, 0x2013, 0x2014
    ]

    /// U+067C, U+069A and U+06BC are empty too, and are left so: the books
    /// have them only as pause signs of an older mushaf encoding, which
    /// another face would show as stray letters inside an ayah.
    static let letters: Set<UInt32> = [
        0x0679, 0x067E, 0x0685, 0x0686, 0x0688, 0x0689, 0x0691,
        0x0693, 0x0696, 0x0698, 0x06A4, 0x06AB, 0x06CD, 0x06D0
    ]

    /// U+06DF, the small high rounded zero, has an empty glyph too. Only book
    /// pages and narrations ask for it to be drawn: the same helper sets ayat
    /// on other screens, and those stay as they are.
    static let smallHighZero: UInt32 = 0x06DF

    /// The stretches of `text` that the mushaf face cannot draw. An ayah's
    /// circle is taken first, then a word with U+06DF where that is asked
    /// for, then a word with an Urdu letter.
    static func spans(in text: some Sequence<Unicode.Scalar>, showsSmallHighZero: Bool = false) -> [Span] {
        let scalars = Array(text)
        var spans: [Span] = []
        var index = 0
        while index < scalars.count {
            let start = index
            if scalars[index].value == 0x06DD, index + 1 < scalars.count, isDigit(scalars[index + 1]) {
                index += 1
                while index < scalars.count, isDigit(scalars[index]) {
                    index += 1
                }
                spans.append(Span(range: start..<index, face: .marker))
            } else if signs.contains(scalars[index].value) {
                while index < scalars.count, signs.contains(scalars[index].value) {
                    index += 1
                }
                spans.append(Span(range: start..<index, face: .signs))
            } else if joins(scalars[index]) {
                var hasGap = false
                var hasZero = false
                while index < scalars.count, joins(scalars[index]) {
                    if letters.contains(scalars[index].value) { hasGap = true }
                    if scalars[index].value == smallHighZero { hasZero = true }
                    index += 1
                }
                if showsSmallHighZero && hasZero {
                    spans.append(Span(range: start..<index, face: .smallHighZero))
                } else if hasGap {
                    spans.append(Span(range: start..<index, face: .urdu))
                }
            } else {
                index += 1
            }
        }
        return spans
    }

    /// `text` with only those stretches given a face of their own, for a
    /// `Text` in `DIFont.quranArabic(scale:)`. Links and colours are kept.
    static func filling(_ text: AttributedString, scale: Double, showsSmallHighZero: Bool = false) -> AttributedString {
        var filled = text
        for span in spans(in: text.unicodeScalars, showsSmallHighZero: showsSmallHighZero) {
            // By scalar, not by character: a span is counted in scalars, and
            // U+06DD with the digit after it is one character.
            let lower = filled.unicodeScalars.index(filled.startIndex, offsetBy: span.range.lowerBound)
            let upper = filled.unicodeScalars.index(lower, offsetBy: span.range.count)
            let face: Font
            switch span.face {
            case .signs: face = DIFont.mushafSigns(scale: scale)
            case .marker: face = DIFont.mushafMarker(scale: scale)
            case .smallHighZero: face = DIFont.mushafAmiriWord(scale: scale)
            case .urdu: face = DIFont.mushafUrduWord(scale: scale)
            }
            filled[lower..<upper].font = face
        }
        return filled
    }

    /// An Arabic-Indic or Urdu digit.
    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x0660...0x0669).contains(scalar.value) || (0x06F0...0x06F9).contains(scalar.value)
    }

    /// A letter, a mark on it, or a joiner: what is shaped as one word.
    private static func joins(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .otherLetter, .modifierLetter, .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return scalar.value == 0x200C || scalar.value == 0x200D
        }
    }
}

extension Text {
    /// `string` in the mushaf face, with what that face cannot draw in a face
    /// that can. `showsSmallHighZero` is for book pages and narrations only.
    static func mushaf(verbatim string: String, scale: Double, showsSmallHighZero: Bool = false) -> Text {
        guard !MushafFaceGaps.spans(in: string.unicodeScalars, showsSmallHighZero: showsSmallHighZero).isEmpty else {
            return Text(verbatim: string).font(DIFont.quranArabic(scale: scale))
        }
        return mushaf(AttributedString(string), scale: scale, showsSmallHighZero: showsSmallHighZero)
    }

    static func mushaf(_ text: AttributedString, scale: Double, showsSmallHighZero: Bool = false) -> Text {
        Text(MushafFaceGaps.filling(text, scale: scale, showsSmallHighZero: showsSmallHighZero))
            .font(DIFont.quranArabic(scale: scale))
    }
}
