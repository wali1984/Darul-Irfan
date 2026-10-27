import Foundation

/// Turns one scanned Urdu page into blocks a reader can follow: headings,
/// paragraphs, and Qur'anic quotations set apart.
///
/// The page text arrives as the scanner laid it out: lines broken wherever
/// the printed column ended, the two-column Asrar pages (Arabic beside its
/// Urdu translation) read straight across into one mixed line, contents
/// pages full of page numbers, and the calligraphic "اللہ" ornament read as
/// a word. Nothing here changes a word of the text; it only decides how the
/// words are grouped and styled.
enum BookPageFormatter {

    struct Run: Equatable, Sendable {
        var text: String
        /// Qur'anic Arabic quoted inside Urdu prose.
        var isQuranic: Bool
    }

    enum Block: Equatable, Sendable {
        case heading(String)
        case paragraph([Run])
        /// A quotation long enough to stand on its own.
        case quran(String)
    }

    struct Page: Equatable, Sendable {
        /// A contents (index) page: shown folded, not as reading text.
        var isContents: Bool
        var blocks: [Block]
    }

    static func format(_ text: String) -> Page {
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
            blocks.append(contentsOf: self.blocks(for: lines))
        }
        return Page(isContents: false, blocks: blocks)
    }

    /// Formats a run of consecutive pages, carrying a sentence the printed
    /// page cut off into the page where it finishes.
    static func format(pages: [BookPage]) -> [String: Page] {
        var result: [String: Page] = [:]
        var previous: BookPage?
        for page in pages {
            var formatted = format(page.text)
            if let before = previous, before.page + 1 == page.page,
               var earlier = result[before.id], !earlier.isContents, !formatted.isContents,
               case .paragraph(let tail)? = earlier.blocks.last, endsMidSentence(tail),
               case .paragraph(let head)? = formatted.blocks.first {
                earlier.blocks[earlier.blocks.count - 1] = .paragraph(merge(tail, head))
                formatted.blocks.removeFirst()
                result[before.id] = earlier
            }
            result[page.id] = formatted
            previous = page
        }
        return result
    }

    // MARK: - Page kinds

    static func isContentsPage(_ text: String) -> Bool {
        let head = String(text.prefix(200))
        if head.contains("فہرست") || head.contains("نمبر شمار") { return true }
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 40 else { return false }
        let numbers = tokens.filter { token in
            token.allSatisfy { noiseCharacters.contains($0) } && token.contains { digits.contains($0) }
        }
        return Double(numbers.count) / Double(tokens.count) >= 0.15
    }

    /// Page numbers, rules and the lone calligraphic "اللہ" ornament.
    private static func isNoise(_ line: String) -> Bool {
        line == "اللہ" || line.allSatisfy { noiseCharacters.contains($0) }
    }

    // MARK: - Blocks

    private static func blocks(for lines: [String]) -> [Block] {
        if let interlinear = interlinearBlocks(lines) { return interlinear }

        // Short lines are a title page or verse: kept as printed.
        let average = Double(lines.reduce(0) { $0 + $1.count }) / Double(lines.count)
        if lines.count > 1 && average < 30 {
            return [.paragraph([Run(text: lines.joined(separator: "\n"), isQuranic: false)])]
        }

        let joined = lines.joined(separator: " ")
        let tokens = joined.split(whereSeparator: \.isWhitespace).map(String.init)
        let quranic = markQuranic(tokens)
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
    /// the Urdu into the paragraph after it.
    private static func interlinearBlocks(_ lines: [String]) -> [Block]? {
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
        var result: [Block] = [.quran(arabic.joined(separator: " "))]
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
}
