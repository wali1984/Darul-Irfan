import Foundation

/// Turns one scanned page into blocks a reader can follow: headings,
/// paragraphs, poetry, footnotes, and Qur'anic quotations set apart.
///
/// A page Claude re-read from the scan comes with its own layout: Claude
/// typed every block as it read it (heading, paragraph, verse, Arabic
/// quotation, footnote, table, caption), and `BookPage.layout` keeps one
/// letter per block, in the order of the text's blank-line-separated parts.
/// Such a page is set out from that; the one thing still decided here is
/// whether an Arabic quotation is the Qur'an.
///
/// The original OCR text arrives as the scanner laid it out: lines broken
/// wherever the printed column ended, the two-column Asrar pages (Arabic
/// beside its Urdu translation) read straight across into one mixed line,
/// contents pages full of page numbers, and the calligraphic "اللہ"
/// ornament read as a word. Its blocks are inferred from the text. Nothing
/// here changes a word of the text; it only decides how the words are
/// grouped and styled.
///
/// Arabic is set as Qur'an only when the mushaf confirms it
/// (`QuranQuotation`). Vowelled Arabic that is not found there - a hadith, a
/// du'a, a saying, or an ayah the scan corrupted - is shown as the book's
/// own Arabic, never dressed as scripture.
enum BookPageFormatter {

    struct Run: Equatable, Sendable {
        var text: String
        /// Qur'anic Arabic quoted inside the prose.
        var isQuranic: Bool
        /// Printed on a line of its own: a re-read paragraph keeps the line
        /// breaks it was printed with (an address, a signature, a list).
        var startsLine = false
    }

    enum Block: Equatable, Sendable {
        case heading(String)
        case paragraph([Run])
        /// A quotation the mushaf confirms, standing on its own.
        case quran(String)
        /// An Arabic quotation the mushaf does not confirm - a hadith, a
        /// du'a, a saying - set apart as the book prints it, not as scripture.
        case arabic(String)
        /// A couplet or stanza, one printed line to a line.
        case verse(String)
        /// Rows of cells.
        case table([[String]])
        /// The words under a picture.
        case caption(String)
    }

    struct Page: Equatable, Sendable {
        /// A contents (index) page: shown folded, not as reading text.
        var isContents: Bool
        var blocks: [Block]
        /// The page's footnotes, set after its text.
        var footnotes: [String] = []
    }

    /// The kinds of block a page's layout names, one letter each.
    enum Kind: Character, Sendable {
        case heading = "h"
        case paragraph = "p"
        case verse = "v"
        case arabic = "a"
        case footnote = "f"
        case table = "t"
        case caption = "c"
    }

    /// One block of a page that carries its layout.
    struct Part: Equatable, Sendable {
        var kind: Kind
        var text: String
    }

    /// - Parameter quranCheck: how closely Arabic must follow the mushaf to be
    ///   set as Qur'an: `.letters` for pages re-read by Claude, `.exact` for
    ///   the original OCR.
    static func format(_ text: String, quranCheck: QuranQuotation.Check = .letters) -> Page {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if isContentsPage(normalized) {
            return Page(isContents: true, blocks: [.paragraph([Run(text: normalized, isQuranic: false)])])
        }
        var blocks: [Block] = []
        for chunk in normalized.components(separatedBy: "\n\n") {
            let lines = chunk
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !isNoise($0) }
            guard !lines.isEmpty else { continue }
            blocks.append(contentsOf: self.blocks(for: lines, check: quranCheck))
        }
        return Page(isContents: false, blocks: blocks)
    }

    /// One page: from its own layout when it has one that fits its text,
    /// otherwise from the text alone.
    static func format(page: BookPage) -> Page {
        let check = quranCheck(for: page)
        guard let parts = laidOutParts(of: page) else { return format(page.text, quranCheck: check) }
        return format(parts: parts, text: page.text, check: check)
    }

    /// The Qur'an check a page's provenance calls for.
    static func quranCheck(for page: BookPage) -> QuranQuotation.Check {
        page.isMachineProvisional ? .exact : .letters
    }

    /// Formats a run of consecutive pages. When a printed page stops in the
    /// middle of a sentence, only the few words that finish it are carried
    /// back from the next page - never a whole paragraph, so every page keeps
    /// its own text under its own number and no page is left empty. A page's
    /// footnotes do not stand in the way: they are set after its text.
    static func format(pages: [BookPage]) -> [String: Page] {
        var result: [String: Page] = [:]
        var previous: BookPage?
        for page in pages {
            var formatted = format(page: page)
            if let before = previous, before.page + 1 == page.page,
               var earlier = result[before.id], !earlier.isContents, !formatted.isContents,
               case .paragraph(let tail)? = earlier.blocks.last, endsMidSentence(tail),
               case .paragraph(let head)? = formatted.blocks.first,
               case let (fragment, rest)? = finishingFragment(of: head),
               !(rest.isEmpty && formatted.blocks.count == 1) {
                earlier.blocks[earlier.blocks.count - 1] = .paragraph(merge(tail, fragment))
                if rest.isEmpty {
                    formatted.blocks.removeFirst()
                } else {
                    formatted.blocks[0] = .paragraph(rest)
                }
                result[before.id] = earlier
            }
            result[page.id] = formatted
            previous = page
        }
        return result
    }

    /// The words at the start of a paragraph up to and including the end of
    /// its first sentence, when that comes within a short distance, and what
    /// is left after them. Nil when the paragraph opens with a quotation, its
    /// first sentence runs on, or it crosses a printed line break (a title or
    /// a verse): then nothing is carried across.
    private static func finishingFragment(of head: [Run]) -> (fragment: [Run], rest: [Run])? {
        guard let first = head.first, !first.isQuranic else { return nil }
        let text = first.text
        var offset = 0
        var cut: String.Index?
        for index in text.indices {
            if offset > maximumCarriedCharacters { break }
            if sentenceEnds.contains(text[index]) { cut = text.index(after: index); break }
            offset += 1
        }
        guard let cut else { return nil }
        let fragment = text[..<cut].trimmingCharacters(in: .whitespaces)
        let remainder = text[cut...].trimmingCharacters(in: .whitespaces)
        guard !fragment.isEmpty, !fragment.contains("\n") else { return nil }
        var rest: [Run] = remainder.isEmpty ? [] : [Run(text: remainder, isQuranic: false)]
        rest.append(contentsOf: head.dropFirst())
        return ([Run(text: fragment, isQuranic: false)], rest)
    }

    // MARK: - Pages that carry their layout

    /// The page's text cut into the blocks its layout names, or nil when it
    /// has no layout or the layout does not fit the text - a letter this
    /// version does not know, or a different number of parts. Such a page is
    /// laid out from its text alone, as before.
    static func laidOutParts(of page: BookPage) -> [Part]? {
        guard let layout = page.layout, !layout.isEmpty else { return nil }
        var kinds: [Kind] = []
        for letter in layout {
            guard let kind = Kind(rawValue: letter) else { return nil }
            kinds.append(kind)
        }
        let texts = blankLineParts(of: page.text)
        guard texts.count == kinds.count else { return nil }
        return zip(kinds, texts).map { Part(kind: $0.0, text: $0.1) }
    }

    /// The text cut at every blank line ("\n\n"), compared scalar by scalar
    /// so that a mark or joiner after a line break can never hide a cut.
    private static func blankLineParts(of text: String) -> [String] {
        var pieces: [String] = []
        var current = String.UnicodeScalarView()
        var afterNewline = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" && afterNewline {
                current.removeLast()
                pieces.append(String(current))
                current = String.UnicodeScalarView()
                afterNewline = false
            } else {
                current.append(scalar)
                afterNewline = scalar == "\n"
            }
        }
        pieces.append(String(current))
        return pieces
    }

    /// A page set out from its own layout. Its footnotes go after its text,
    /// where a printed page sets them, in whatever order they were read.
    private static func format(parts: [Part], text: String, check: QuranQuotation.Check) -> Page {
        var blocks: [Block] = []
        var footnotes: [String] = []
        for part in parts {
            switch part.kind {
            case .heading:
                blocks.append(.heading(part.text))
            case .paragraph:
                blocks.append(.paragraph(proseRuns(part.text, check: check)))
            case .verse:
                blocks.append(.verse(part.text))
            case .arabic:
                blocks.append(contentsOf: arabicBlocks(part.text, check: check))
            case .footnote:
                footnotes.append(part.text)
            case .table:
                blocks.append(.table(tableRows(part.text)))
            case .caption:
                blocks.append(.caption(part.text))
            }
        }
        return Page(isContents: isContentsPage(text), blocks: blocks, footnotes: footnotes)
    }

    /// An Arabic quotation is the Qur'an when all of it, up to a short
    /// citation in brackets at its end ("(البقرۃ:۲۵۵)"), is found in the
    /// mushaf in the same order. It is compared whole, as Claude read it: a
    /// hadith that quotes an ayah, or a formula made of Qur'anic phrases, must
    /// not pass piece by piece.
    static func isQuranQuotation(_ text: String, check: QuranQuotation.Check) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let end = trailingCitationStart(words) ?? words.count
        return QuranQuotation.isVerified(words[..<end], check: check)
    }

    /// An Arabic quotation, set as the Qur'an where the mushaf confirms it.
    /// Confirmed whole, it is one Qur'an block, its citation included.
    /// Otherwise it is cut after each printed ayah number, and each run of
    /// whole ayat the mushaf confirms is set as the Qur'an, while the rest -
    /// an ayah the page spells differently, a hadith, a du'a - stays the
    /// book's own Arabic. A quotation with nothing confirmed stays one block.
    private static func arabicBlocks(_ text: String, check: QuranQuotation.Check) -> [Block] {
        if isQuranQuotation(text, check: check) { return [.quran(text)] }
        let ayat = ayahRanges(in: text)
        guard ayat.count > 1 else { return [.arabic(text)] }
        func span(_ first: Int, _ last: Int) -> String {
            String(text[ayat[first].lowerBound..<ayat[last].upperBound])
        }
        var result: [Block] = []
        var plainStart: Int?
        var start = 0
        while start < ayat.count {
            // The longest run of whole ayat from here that the mushaf holds.
            var end = start
            while end < ayat.count, isQuran(ayat[start...end], in: text, check: check) { end += 1 }
            if end > start {
                if let first = plainStart { result.append(.arabic(span(first, start - 1))) }
                plainStart = nil
                result.append(.quran(span(start, end - 1)))
                start = end
            } else {
                if plainStart == nil { plainStart = start }
                start += 1
            }
        }
        if let first = plainStart { result.append(.arabic(span(first, ayat.count - 1))) }
        let confirmed = result.contains { block in
            if case .quran = block { return true }
            return false
        }
        return confirmed ? result : [.arabic(text)]
    }

    /// Where each ayah of a quotation lies, as printed: it ends with its
    /// number (﴿۱۸﴾, ۝۱, ○). The text after the last number is a piece too.
    private static func ayahRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var end = text.startIndex
        for word in text.split(whereSeparator: \.isWhitespace) {
            if start == nil { start = word.startIndex }
            end = word.endIndex
            if endsAyah(word), let first = start {
                ranges.append(first..<end)
                start = nil
            }
        }
        if let first = start { ranges.append(first..<end) }
        return ranges
    }

    /// An ayah number, or the sign closing an ayah. Read scalar by scalar:
    /// ۝ joins the digits after it into one Character.
    private static func endsAyah(_ word: Substring) -> Bool {
        let scalars = word.unicodeScalars
        if scalars.contains("\u{06DD}") || scalars.contains("\u{25CB}") { return true }
        return scalars.last == "\u{FD3E}" && scalars.contains { $0.properties.numericType == .decimal }
    }

    private static func isQuran(_ ayat: ArraySlice<Range<String.Index>>, in text: String,
                                check: QuranQuotation.Check) -> Bool {
        let words = ayat.flatMap { text[$0].split(whereSeparator: \.isWhitespace).map(String.init) }
        return QuranQuotation.isVerified(words, check: check)
    }

    /// Where a short citation in brackets that closes a quotation begins:
    /// one to a few words after it, the first opening a bracket and the last
    /// closing one.
    private static func trailingCitationStart(_ words: [String]) -> Int? {
        guard words.count >= 2,
              let close = words[words.count - 1].trimmingCharacters(in: citationPunctuation).last,
              citationClosers.contains(close) else { return nil }
        let earliest = max(1, words.count - maximumCitationWords)
        for start in stride(from: words.count - 1, through: earliest, by: -1) {
            if let open = words[start].first, citationOpeners.contains(open) { return start }
        }
        return nil
    }

    /// A re-read paragraph's words in runs, with a Qur'anic quotation the
    /// mushaf confirms marked for the Qur'an face. The quotation stays in the
    /// sentence, where the page printed it, and the paragraph keeps its
    /// printed line breaks.
    private static func proseRuns(_ text: String, check: QuranQuotation.Check) -> [Run] {
        var runs: [Run] = []
        for line in text.split(separator: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty else { continue }
            let quranic = verifiedQuranic(tokens, check: check)
            var startsLine = !runs.isEmpty
            var index = 0
            while index < tokens.count {
                var end = index
                while end < tokens.count && quranic[end] == quranic[index] { end += 1 }
                runs.append(Run(
                    text: tokens[index..<end].joined(separator: " "),
                    isQuranic: quranic[index],
                    startsLine: startsLine
                ))
                startsLine = false
                index = end
            }
        }
        return runs
    }

    /// A table's rows, one to a line, cut into cells at "|". A rule at either
    /// end of a row ("| a | b |") does not make an empty cell.
    private static func tableRows(_ text: String) -> [[String]] {
        text.split(separator: "\n").map { line -> [String] in
            let row = line.trimmingCharacters(in: .whitespaces)
            var cells = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count > 1, row.hasPrefix("|") { cells.removeFirst() }
            if cells.count > 1, row.hasSuffix("|") { cells.removeLast() }
            return cells
        }
    }

    // MARK: - Page kinds

    static func isContentsPage(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let numbers = tokens.filter { token in
            token.allSatisfy { noiseCharacters.contains($0) } && token.contains { digits.contains($0) }
        }
        let numberShare = tokens.isEmpty ? 0 : Double(numbers.count) / Double(tokens.count)
        // A page that names itself an index must still read like one - rows
        // ending in page numbers. Prose that mentions a list stays prose.
        let head = String(text.prefix(200))
        if head.contains("فہرست") || head.contains("نمبر شمار") { return numberShare >= 0.10 }
        guard tokens.count >= 40 else { return false }
        return numberShare >= 0.15
    }

    /// Page numbers, rules and the lone calligraphic "اللہ" ornament.
    private static func isNoise(_ line: String) -> Bool {
        line == "اللہ" || line.allSatisfy { noiseCharacters.contains($0) }
    }

    // MARK: - Blocks

    private static func blocks(for lines: [String], check: QuranQuotation.Check) -> [Block] {
        if let interlinear = interlinearBlocks(lines, check: check) { return interlinear }

        // Short lines are a title page or verse: kept as printed.
        let average = Double(lines.reduce(0) { $0 + $1.count }) / Double(lines.count)
        if lines.count > 1 && average < 30 {
            return [.paragraph([Run(text: lines.joined(separator: "\n"), isQuranic: false)])]
        }

        let joined = lines.joined(separator: " ")
        let tokens = joined.split(whereSeparator: \.isWhitespace).map(String.init)
        let quranic = verifiedQuranic(tokens, check: check)
        if tokens.count <= 8, !quranic.contains(true), let last = joined.last,
           last == ":" || !(terminators.contains(last) || last == "،" || last == ",") {
            return [.heading(joined.trimmingCharacters(in: CharacterSet(charactersIn: ": ")))]
        }

        var result: [Block] = []
        var runs: [Run] = []
        var index = 0
        while index < tokens.count {
            var end = index
            while end < tokens.count && quranic[end] == quranic[index] { end += 1 }
            let text = tokens[index..<end].joined(separator: " ")
            if quranic[index] && end - index >= 6 {
                if !runs.isEmpty { result.append(.paragraph(runs)); runs = [] }
                result.append(.quran(text))
            } else if let last = runs.last, last.isQuranic == quranic[index] {
                runs[runs.count - 1].text += " " + text
            } else {
                runs.append(Run(text: text, isQuranic: quranic[index]))
            }
            index = end
        }
        if !runs.isEmpty { result.append(.paragraph(runs)) }
        return result
    }

    /// Two-column pages scanned straight across: most lines open with Arabic
    /// and end with its Urdu. The Arabic is gathered into one quotation and
    /// the Urdu into the paragraph after it. The quotation is set as Qur'an
    /// only when the mushaf confirms it.
    private static func interlinearBlocks(_ lines: [String], check: QuranQuotation.Check) -> [Block]? {
        guard lines.count >= 3 else { return nil }
        var arabic: [String] = []
        var urdu: [String] = []
        var hits = 0
        for line in lines {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            let quranic = markQuranic(tokens)
            let split = quranic.firstIndex(of: false) ?? tokens.count
            if split >= 2 && split < tokens.count { hits += 1 }
            if split > 0 { arabic.append(tokens[..<split].joined(separator: " ")) }
            if split < tokens.count { urdu.append(tokens[split...].joined(separator: " ")) }
        }
        guard Double(hits) >= 0.6 * Double(lines.count) else { return nil }
        let arabicText = arabic.joined(separator: " ")
        let arabicTokens = arabicText.split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [Block] = QuranQuotation.isVerified(arabicTokens, check: check)
            ? [.quran(arabicText)]
            : [.paragraph([Run(text: arabicText, isQuranic: false)])]
        if !urdu.isEmpty {
            result.append(.paragraph([Run(text: urdu.joined(separator: " "), isQuranic: false)]))
        }
        return result
    }

    // MARK: - Quranic Arabic

    /// Which tokens belong to a Qur'anic quotation: voweled Arabic (Urdu
    /// prose carries a vowel mark only now and then), ayah markers, and an
    /// unmarked Arabic word between two of them. A run shorter than three
    /// words is ordinary Urdu with a vowel mark.
    static func markQuranic(_ tokens: [String]) -> [Bool] {
        var marks = tokens.map(isQuranicWord)
        if tokens.count > 2 {
            for index in 1..<(tokens.count - 1) where !marks[index] && marks[index - 1] && marks[index + 1] {
                if !hasUrduLetters(tokens[index]) && tokens[index].count <= 8 { marks[index] = true }
            }
        }
        var index = 0
        while index < tokens.count {
            guard marks[index] else { index += 1; continue }
            var end = index
            while end < tokens.count && marks[end] { end += 1 }
            if end - index < 3 && !tokens[index..<end].contains(where: isAyahMarker) {
                for position in index..<end { marks[position] = false }
            }
            index = end
        }
        return marks
    }

    /// `markQuranic`, keeping only the runs the mushaf confirms. Arabic that
    /// only looked like a quotation stays in the prose as ordinary text.
    static func verifiedQuranic(_ tokens: [String], check: QuranQuotation.Check) -> [Bool] {
        var marks = markQuranic(tokens)
        var index = 0
        while index < tokens.count {
            guard marks[index] else { index += 1; continue }
            var end = index
            while end < tokens.count && marks[end] { end += 1 }
            if !QuranQuotation.isVerified(tokens[index..<end], check: check) {
                for position in index..<end { marks[position] = false }
            }
            index = end
        }
        return marks
    }

    private static func isQuranicWord(_ word: String) -> Bool {
        if isAyahMarker(word) { return true }
        let vowels = word.unicodeScalars.filter { harakat.contains($0.value) }.count
        return vowels >= 2 || (vowels >= 1 && !hasUrduLetters(word))
    }

    private static func isAyahMarker(_ word: String) -> Bool {
        word.contains("﴿") || word.contains("﴾")
    }

    private static func hasUrduLetters(_ word: String) -> Bool {
        word.unicodeScalars.contains { urduOnlyLetters.contains($0.value) }
    }

    // MARK: - Joining pages

    private static func endsMidSentence(_ runs: [Run]) -> Bool {
        guard let last = runs.last?.text.trimmingCharacters(in: .whitespaces).last else { return false }
        return !terminators.contains(last)
    }

    private static func merge(_ tail: [Run], _ head: [Run]) -> [Run] {
        guard let first = head.first, let last = tail.last, first.isQuranic == last.isQuranic else {
            return tail + head
        }
        var merged = tail
        merged[merged.count - 1].text += " " + first.text
        return merged + head.dropFirst()
    }

    // MARK: - Character sets

    private static let harakat = Set<UInt32>(0x064B...0x0652).union([0x0670])
    /// Letters Urdu writes and Qur'anic Arabic does not (ک ی ہ are the Urdu
    /// forms of ك ي ه). Compared as scalars: a letter carrying a vowel mark
    /// is one Character with the mark.
    private static let urduOnlyLetters = Set("ٹڈڑںےۓھہکیگپچژ".unicodeScalars.map(\.value))
    private static let digits: Set<Character> = Set("0123456789٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹")
    private static let noiseCharacters: Set<Character> = digits.union(" .,:;-–—()[]/۔،*")
    private static let terminators: Set<Character> = Set("۔؟!.:”\"؛")
    /// Where a sentence carried across a page break may end.
    private static let sentenceEnds: Set<Character> = Set("۔؟!.?")
    /// The most text carried back to the page before; longer than this, the
    /// sentence stays on its own page.
    private static let maximumCarriedCharacters = 240
    /// Brackets around a citation after a quotation: "(البقرۃ:۲۵۵)", "[الزمر: ٤٥]".
    private static let citationOpeners: Set<Character> = ["(", "["]
    private static let citationClosers: Set<Character> = [")", "]"]
    /// What may follow a citation's closing bracket.
    private static let citationPunctuation = CharacterSet(charactersIn: ".,،۔:;؛")
    /// The longest citation, in words: "(سورۃ آل عمران: ۱۴۴)" is four.
    private static let maximumCitationWords = 5
}
