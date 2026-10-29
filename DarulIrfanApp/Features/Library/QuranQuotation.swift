import Foundation

/// Recognises Qur'anic quotations inside book and tafsir text by finding them
/// in the mushaf the app ships (quran_ayahs.json).
///
/// The pages are read from scans. On the original OCR pages most quoted
/// Arabic is corrupt, and every kind of page also quotes hadith, du'as and
/// Arabic sayings that look like a quotation from the Qur'an. Set in the
/// Qur'an face, all of it would read as scripture. So the face is kept for
/// Arabic whose every run of words is in the mushaf, in the same order; the
/// rest is shown as the book's own Arabic.
enum QuranQuotation {
    /// How closely a quotation must follow the mushaf.
    enum Check: Sendable, Equatable {
        /// The same letters in the same order. Vowel marks are not compared,
        /// because a scan and the mushaf write them differently. For pages
        /// re-read from the scan by Claude.
        case letters
        /// The same letters and the same vowel marks. For the original OCR,
        /// whose letters can be right while a vowel is wrong.
        case exact
    }

    /// True when the words, in order, are found in the mushaf. Needs at least
    /// three words: one or two are too common to tell scripture from prose.
    ///
    /// The words are compared as written and once more with every one-letter
    /// word joined to the next (see `keys(of:check:joiningLetters:)`), so a
    /// quotation matches whether or not it divides the words as the mushaf
    /// does.
    static func isVerified<S: Sequence>(_ words: S, check: Check) -> Bool where S.Element == String {
        let list = Array(words)
        return isKnown(keys(of: list, check: check, joiningLetters: false), check: check)
            || isKnown(keys(of: list, check: check, joiningLetters: true), check: check)
    }

    /// True when every run of three or four keys is a run in the mushaf.
    private static func isKnown(_ compared: [String], check: Check) -> Bool {
        guard compared.count >= 3 else { return false }
        let n = min(4, compared.count)
        let known = index.grams(n: n, check: check)
        guard !known.isEmpty else { return false }
        for start in 0...(compared.count - n) where !known.contains(hash(compared[start..<(start + n)])) {
            return false
        }
        return true
    }

    /// Builds the mushaf index now, off the main thread, so the first page or
    /// tafsir entry laid out on the main thread does not pause for it.
    static func warmUp() {
        _ = index
    }

    // MARK: - Mushaf index

    private struct Index: Sendable {
        var letters3: Set<Int>
        var letters4: Set<Int>
        var exact3: Set<Int>
        var exact4: Set<Int>

        func grams(n: Int, check: Check) -> Set<Int> {
            switch check {
            case .letters: return n == 3 ? letters3 : letters4
            case .exact: return n == 3 ? exact3 : exact4
            }
        }
    }

    /// Every run of three and of four consecutive words in the mushaf, across
    /// ayah ends (a quotation can span ayat). Built once, on first use.
    private static let index: Index = {
        let ayahs = SeedBundle.quranAyahs().sorted {
            ($0.surahNumber, $0.ayahNumber) < ($1.surahNumber, $1.ayahNumber)
        }
        // Each ayah keyed on its own, as written and with its one-letter
        // words joined, so a quotation that starts or ends where an ayah
        // does lines up with it word for word.
        var letterKeys: [String] = []
        var joinedLetterKeys: [String] = []
        var exactKeys: [String] = []
        var joinedExactKeys: [String] = []
        for ayah in ayahs {
            let text = [ayah.textArabic]
            letterKeys.append(contentsOf: keys(of: text, check: .letters, joiningLetters: false))
            joinedLetterKeys.append(contentsOf: keys(of: text, check: .letters, joiningLetters: true))
            exactKeys.append(contentsOf: keys(of: text, check: .exact, joiningLetters: false))
            joinedExactKeys.append(contentsOf: keys(of: text, check: .exact, joiningLetters: true))
        }
        return Index(
            letters3: grams(letterKeys, 3).union(grams(joinedLetterKeys, 3)),
            letters4: grams(letterKeys, 4).union(grams(joinedLetterKeys, 4)),
            exact3: grams(exactKeys, 3).union(grams(joinedExactKeys, 3)),
            exact4: grams(exactKeys, 4).union(grams(joinedExactKeys, 4))
        )
    }()

    /// The words reduced to what is compared, in order.
    ///
    /// With `joiningLetters`, a word of a single letter is joined to the word
    /// after it. The bundled mushaf is divided for word-by-word reading and
    /// sometimes sets a letter apart ("وَ قُوْلُوا", "اَ يَّـتُهَا") where a book
    /// prints one word, and a book sometimes does the same where the mushaf
    /// does not; joined on both sides, the spacing no longer decides. A letter
    /// left over at the end belongs to a word the quotation stops before - the
    /// "وَ" of the next ayah, or a sign printed as a letter (ع for a ruku, ط for
    /// a pause) - and is not compared.
    private static func keys<S: Sequence>(of words: S, check: Check, joiningLetters: Bool) -> [String]
        where S.Element == String {
        var result: [String] = []
        var pending = ""
        for word in words {
            for part in parts(of: word) {
                let reduced = key(for: part, check: check)
                if reduced.key.isEmpty { continue }
                if joiningLetters && reduced.letters == 1 {
                    pending += reduced.key
                } else {
                    result.append(pending + reduced.key)
                    pending = ""
                }
            }
        }
        return result
    }

    /// Words split at spaces and at invisible separators: the mushaf text
    /// joins some words with a zero-width space.
    private static func parts(of text: String) -> [String] {
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .format {
                if !current.isEmpty { parts.append(String(current)); current = String.UnicodeScalarView() }
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { parts.append(String(current)) }
        return parts
    }

    /// A word reduced to what is compared, and how many letters it has: its
    /// letters, with the Arabic and Urdu forms of one letter folded together,
    /// and for `.exact` its vowel marks as well. Pause signs, ayah numbers
    /// and punctuation are dropped.
    private static func key(for word: String, check: Check) -> (key: String, letters: Int) {
        var view = String.UnicodeScalarView()
        var letters = 0
        for scalar in word.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .otherLetter:
                letters += 1
                view.append(folded(scalar))
            case .nonspacingMark where check == .exact:
                // The small pause signs are reading aids, not the word.
                if (0x06D6...0x06DC).contains(scalar.value) { continue }
                // The IndoPak jazm and the plain sukun are the same mark.
                view.append(scalar.value == 0x06E1 ? "\u{0652}" : scalar)
            case .modifierLetter where check == .exact && scalar.value != 0x0640:
                view.append(scalar)
            default:
                continue
            }
        }
        return (String(view), letters)
    }

    /// One letter for the forms the mushaf and the books write differently.
    /// The mushaf's IndoPak text seats a medial yeh, and a hamza on one, on a
    /// dotless letter (ٮ, U+066E: اُولٰٓٮِٕكَ, اَدۡرٰٮكَ) where the books write ئ
    /// or ی; without this, an ayah with such a word never matched a book.
    private static func folded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.value == 0x066E { return "\u{06CC}" }
        return SearchNormalizer.foldedLetter(scalar)
    }

    private static func grams(_ keys: [String], _ n: Int) -> Set<Int> {
        guard keys.count >= n else { return [] }
        var result = Set<Int>(minimumCapacity: keys.count)
        for start in 0...(keys.count - n) {
            result.insert(hash(keys[start..<(start + n)]))
        }
        return result
    }

    private static func hash(_ keys: ArraySlice<String>) -> Int {
        var hasher = Hasher()
        for key in keys { hasher.combine(key) }
        return hasher.finalize()
    }
}
