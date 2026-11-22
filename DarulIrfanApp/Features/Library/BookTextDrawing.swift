import SwiftUI
import UIKit

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
    /// Any other screen: none of these rules.
    case other

    /// The rules of book and article text: the size of the salawat sign and
    /// the order of its numbers.
    var followsBookRules: Bool { self == .book || self == .article }

    /// U+06DF is drawn in books and narrations. An article also sets ayat from
    /// the mushaf's own text, which stay as they are.
    var showsSmallHighZero: Bool { self == .book || self == .hadith }
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

    // MARK: - Links

    /// The words of a link: tappable, with a thin dotted underline in the
    /// link's colour, as colour alone does not tell a link from a quotation
    /// that opens nothing.
    static func link(_ string: String, index: Int) -> AttributedString {
        var attributed = AttributedString(string)
        guard let url = URL(string: "\(BookLinkTaps.scheme):\(index)") else { return attributed }
        attributed.link = url
        attributed[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] =
            Text.LineStyle(pattern: .dot, color: DIColor.actionForeground)
        return attributed
    }

    // MARK: - Numbers in right-to-left text

    /// LEFT-TO-RIGHT ISOLATE and POP DIRECTIONAL ISOLATE.
    static let isolateStart = "\u{2066}"
    static let isolateEnd = "\u{2069}"

    /// LEFT-TO-RIGHT OVERRIDE and POP DIRECTIONAL FORMATTING. Arabic-Indic
    /// digits need them inside an isolate: their groups still turn round
    /// in left-to-right text.
    static let overrideStart = "\u{202D}"
    static let overrideEnd = "\u{202C}"

    /// WORD JOINER: no line breaks at it. One follows each sign and space
    /// inside such a number, so that the number never takes two lines.
    static let wordJoiner = "\u{2060}"

    private static let anyDigit = #"0-9٠-٩۰-۹"#
    /// Digit groups joined by a dash, slash or stop: a date when there are three.
    private static let threeGroups = pattern("(?<![\(anyDigit)])[\(anyDigit)]+(?:[ ]?[-/–.][ ]?[\(anyDigit)]+){2,}")
    /// "3 : 164", and "79:18-19" with its range.
    private static let colonGroups = pattern(
        "(?<![\(anyDigit)])[\(anyDigit)]+(?:[ ]+:[ ]*|[ ]*:[ ]+)[\(anyDigit)]+(?:[ ]?[-–][ ]?[\(anyDigit)]+)?"
            + "|(?<![\(anyDigit)])[\(anyDigit)]+:[\(anyDigit)]+[ ]?[-–][ ]?[\(anyDigit)]+"
    )
    /// A telephone number.
    private static let telephone = pattern(#"(?<![\d.])(?:\+|0)[0-9]{1,4}(?:[- ][0-9]{2,8}){1,3}(?!\d)"#)
    /// "12-13", "1981-82".
    private static let span = pattern(#"(?<![\d:./–-])([0-9]{1,4})[-–]([0-9]{1,4})(?![\d:./–-])"#)

    private static func pattern(_ source: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: source)
    }

    /// The numbers that must be read left to right inside right-to-left text,
    /// in order and not overlapping, counted in UTF-16. After Urdu letters a
    /// hyphen or a spaced colon turns their groups round. Only these four
    /// shapes are taken: the books also store some dates back to front
    /// ("70-7-4", "57-1956"), and those read correctly as they are. So does
    /// a number after Latin letters ("Ph:+92 41 2615359"), which an isolate
    /// would part from its word.
    static func numberTokens(in text: String) -> [NSRange] {
        guard text.unicodeScalars.contains(where: { $0.properties.numericType == .decimal }) else { return [] }
        let whole = text as NSString
        let all = NSRange(location: 0, length: whole.length)
        var found: [NSRange] = []

        for match in threeGroups?.matches(in: text, range: all) ?? [] {
            let groups = digitGroups(whole.substring(with: match.range))
            if groups.count == 3, number(groups[0]) <= 31, number(groups[1]) <= 12 {
                found.append(match.range)
            }
        }
        found += (colonGroups?.matches(in: text, range: all) ?? []).map(\.range)
        for match in telephone?.matches(in: text, range: all) ?? [] {
            let western = whole.substring(with: match.range).unicodeScalars.filter { (0x30...0x39).contains($0.value) }
            if western.count >= 9 { found.append(match.range) }
        }
        for match in span?.matches(in: text, range: all) ?? [] {
            let first = whole.substring(with: match.range(at: 1))
            let second = whole.substring(with: match.range(at: 2))
            let rises = number(first) < number(second)
                && ((first.count <= 3 && second.count <= 3) || (first.count == 4 && second.count == 4))
            if rises || (first.count == 4 && second.count == 2) { found.append(match.range) }
        }

        // A number after the ayah sign stands inside its circle.
        found.removeAll { $0.location > 0 && whole.character(at: $0.location - 1) == ayahSign }
        var tokens: [NSRange] = []
        for range in found.sorted(by: { $0.location < $1.location }) {
            if let last = tokens.last, range.location < NSMaxRange(last) {
                tokens[tokens.count - 1] = NSUnionRange(last, range)
            } else {
                tokens.append(range)
            }
        }
        return tokens.filter { token in
            holdsArabicIndicDigits(whole.substring(with: token)) || !followsLatin(whole, token.location)
        }
    }

    /// The last letter before `location` on its line is Latin.
    private static func followsLatin(_ text: NSString, _ location: Int) -> Bool {
        var index = location
        while index > 0 {
            index -= 1
            guard let scalar = Unicode.Scalar(text.character(at: index)) else { continue }
            if scalar == "\n" { return false }
            if scalar.properties.isAlphabetic { return scalar.value < 0x0250 }
        }
        return false
    }

    private static let ayahSign: unichar = 0x06DD
    private static let noBreakSpace = "\u{00A0}"

    /// A Western, Arabic-Indic or Urdu digit.
    private static func isDigit(_ unit: unichar) -> Bool {
        (0x30...0x39).contains(unit) || (0x0660...0x0669).contains(unit) || (0x06F0...0x06F9).contains(unit)
    }

    /// `text`'s words for measuring, where each such number is one word: it
    /// never takes two lines.
    static func unbrokenWords(of text: String) -> [String] {
        let joined = NSMutableString(string: text)
        for token in numberTokens(in: text) {
            joined.replaceOccurrences(of: " ", with: noBreakSpace, options: .literal, range: token)
        }
        return (joined as String)
            .split(whereSeparator: { $0.isWhitespace && String($0) != noBreakSpace })
            .map(String.init)
    }

    private static func holdsArabicIndicDigits(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) }
    }

    /// `pieces` of one stretch of right-to-left text with each such number in
    /// an isolate and unbroken, for drawing only. Found in the whole stretch,
    /// as a link may end inside a number.
    static func isolatingNumbers(_ pieces: [String]) -> [String] {
        let joined = pieces.joined()
        let tokens = numberTokens(in: joined)
        guard !tokens.isEmpty else { return pieces }
        let whole = joined as NSString
        let overridden = tokens.map { holdsArabicIndicDigits(whole.substring(with: $0)) }
        // Where a line could break inside each: after a sign or a space.
        let joints = tokens.map { token in
            (token.location + 1..<NSMaxRange(token)).filter { !isDigit(whole.character(at: $0 - 1)) }
        }
        var drawn: [String] = []
        var start = 0
        for piece in pieces {
            let shown = NSMutableString(string: piece)
            let end = start + shown.length
            // From the last, so that the places before it do not move.
            for index in tokens.indices.reversed() {
                let token = tokens[index]
                let overrides = overridden[index]
                let tokenEnd = NSMaxRange(token)
                if tokenEnd > start && tokenEnd <= end {
                    shown.insert(overrides ? overrideEnd + isolateEnd : isolateEnd, at: tokenEnd - start)
                }
                for joint in joints[index].reversed() where joint > start && joint <= end {
                    shown.insert(wordJoiner, at: joint - start)
                }
                if token.location >= start && token.location < end {
                    shown.insert(overrides ? isolateStart + overrideStart : isolateStart, at: token.location - start)
                }
            }
            drawn.append(shown as String)
            start = end
        }
        return drawn
    }

    private static func digitGroups(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.wholeNumberValue == nil }).map(String.init)
    }

    /// A group's value in Western, Arabic-Indic or Urdu digits. A group too
    /// long to be a day, a month or a year is above all of them.
    private static func number(_ group: String) -> Int {
        guard group.count <= 9 else { return Int.max }
        return group.reduce(0) { $0 * 10 + ($1.wholeNumberValue ?? 0) }
    }
}

/// Measures a table's words, so that none is broken inside.
enum BookTableMeasure {
    private static let measured = NSCache<NSString, NSNumber>()

    /// Each column's longest word at the cells' size. The row naming the
    /// columns is measured bold; a row naming a section spans the table and
    /// is left out.
    /// - Parameters:
    ///   - enlargesSalawat: the cells are Urdu, with the salawat sign drawn
    ///     larger.
    ///   - keepsNumbersWhole: the cells run right to left, where a date or a
    ///     telephone number never takes two lines.
    static func columnMinimums(
        _ rows: [[String]],
        layout: BookPageFormatter.TableLayout,
        font: UIFont,
        enlargesSalawat: Bool,
        keepsNumbersWhole: Bool = false
    ) -> [Double] {
        let columns = max(1, rows.map(\.count).max() ?? 1)
        var minimums = Array(repeating: 0.0, count: columns)
        let heading = bold(font)
        for (index, row) in rows.enumerated() where !BookPageFormatter.isSectionRow(row, columns: columns) {
            let isHeader = index == 0 && layout.hasHeaderRow
            for (column, cell) in row.enumerated() {
                let words = keepsNumbersWhole
                    ? BookTextDrawing.unbrokenWords(of: cell)
                    : cell.split(whereSeparator: \.isWhitespace).map(String.init)
                for word in words {
                    var widest = width(of: word, font: font, enlargesSalawat: enlargesSalawat)
                    if isHeader {
                        widest = max(widest, width(of: word, font: heading, enlargesSalawat: enlargesSalawat))
                    }
                    minimums[column] = max(minimums[column], widest)
                }
            }
        }
        return minimums
    }

    /// Rounded up, with a point to spare: a width short by a fraction breaks
    /// the word.
    static func width(of word: String, font: UIFont, enlargesSalawat: Bool) -> Double {
        let key = "\(font.fontName)|\(font.pointSize)|\(enlargesSalawat)|\(word)" as NSString
        if let known = measured.object(forKey: key) { return known.doubleValue }
        let text = NSMutableAttributedString(string: word, attributes: [NSAttributedString.Key.font: font])
        if enlargesSalawat, BookTextDrawing.holdsSalawat(word),
           let face = UIFont(name: AppFonts.quranArabicName, size: font.pointSize * 1.25) {
            for (offset, unit) in word.utf16.enumerated() where UInt32(unit) == BookTextDrawing.salawat.value {
                text.addAttribute(NSAttributedString.Key.font, value: face, range: NSRange(location: offset, length: 1))
            }
        }
        let width = Double(text.size().width.rounded(.up)) + 1
        measured.setObject(NSNumber(value: width), forKey: key)
        return width
    }

    private static func bold(_ font: UIFont) -> UIFont {
        let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

/// Selecting a block's text. SwiftUI's selection on iOS takes the whole of
/// a `Text`, to Copy or Share it, as drawn. Where numbers were isolated or
/// joined for drawing, a menu of the same two gives the book's own words
/// instead, without those marks.
struct BookTextSelection: ViewModifier {
    /// The block as the book has it.
    let text: String
    /// The block is drawn with isolates.
    let isIsolated: Bool

    func body(content: Content) -> some View {
        if isIsolated {
            content
                .textSelection(.disabled)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
        } else {
            content.textSelection(.enabled)
        }
    }
}
