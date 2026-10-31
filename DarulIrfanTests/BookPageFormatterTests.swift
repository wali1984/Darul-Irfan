import XCTest
@testable import DarulIrfan

/// The Urdu page layout: headings, joined lines, quotations set apart,
/// contents pages folded, and sentences carried across a page break.
final class BookPageFormatterTests: XCTestCase {

    func testInlineHadithKeepsArabicSeparateFromUrduAndQuran() {
        let quotation = "إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ"
        let source = "رسول اللہ ﷺ نے فرمایا: \(quotation) یہ نیت کے بارے میں ہے۔"
        guard case .paragraph(let runs) = BookPageFormatter.articleParagraph(source).blocks.first else {
            return XCTFail("Expected mixed Urdu and Arabic paragraph")
        }
        XCTAssertEqual(runs.map(\.text).joined(separator: " "), source)
        XCTAssertEqual(runs.filter(\.isArabic).map(\.text), [quotation])
        XCTAssertFalse(runs.contains { $0.isQuranic })
        let urdu = BookPageFormatter.articleParagraph("یہ ایک عام اُردو جملہ ہے۔")
        guard case .paragraph(let ordinary) = urdu.blocks.first else { return XCTFail("Expected Urdu prose") }
        XCTAssertFalse(ordinary.contains { $0.isArabic || $0.isQuranic })
    }

    func testArticleKeepsShortLinesAndUrduAsProse() {
        let text = "اللہ\nیہ ایک عام اردو جملہ ہے۔\nContact: Darul Irfan"
        let page = BookPageFormatter.articleParagraph(text)
        XCTAssertFalse(page.isContents)
        guard case .paragraph(let runs) = page.blocks.first else { return XCTFail("Article prose was misclassified") }
        XCTAssertFalse(runs.contains { $0.isQuranic })
        XCTAssertEqual(runs.map(\.text).joined(separator: "\n"), text)
        XCTAssertEqual(runs.map(\.startsLine), [false, true, true])
    }

    func testArticleRecognizesQuranWithoutRewording() {
        let text = SeedBundle.quranAyahs().first { $0.surahNumber == 2 && $0.ayahNumber == 255 }!.textArabic
        XCTAssertEqual(BookPageFormatter.articleParagraph(text).blocks, [.quran(text)])
    }

    func testLinesBrokenByTheColumnAreJoined() {
        let page = BookPageFormatter.format("جو شخص اپنے طریقے سے یا اپنے خیال کے مطابق\nاپنی رائے سے اصلاح کرنا چاہتا ہے وہ فساد پیدا کرتا ہے۔")
        XCTAssertEqual(page.blocks, [.paragraph([.init(
            text: "جو شخص اپنے طریقے سے یا اپنے خیال کے مطابق اپنی رائے سے اصلاح کرنا چاہتا ہے وہ فساد پیدا کرتا ہے۔",
            isQuranic: false
        )])])
    }

    func testShortLineEndingInAColonIsAHeading() {
        let page = BookPageFormatter.format("فساد کی حقیقت:\n\nانسان جو چیز بناتا ہے اس کے استعمال کا ایک قاعدہ ہے۔")
        XCTAssertEqual(page.blocks.first, .heading("فساد کی حقیقت"))
    }

    func testOrnamentAndPageNumbersAreDropped() {
        let page = BookPageFormatter.format("اللہ\n\n۴۷\n\nانسان جو چیز بناتا ہے اس کے استعمال کا ایک قاعدہ ہے۔")
        XCTAssertEqual(page.blocks.count, 1)
    }

    /// A quotation the mushaf confirms stands apart in the Qur'an face.
    func testQuotationFoundInTheMushafStandsApart() throws {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        let ayah = try XCTUnwrap(ayahs.first { $0.surahNumber == 20 && $0.ayahNumber == 18 })
        let text = "مختصر سوال ہوا کہ \(ayah.textArabic) ﴿۱۸﴾ بات ختم ہو گئی۔"
        let blocks = BookPageFormatter.format(text).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .quran(let quote) = blocks[1] else { return XCTFail("no quotation block: \(blocks)") }
        XCTAssertTrue(quote.hasPrefix("قَالَ"))
        XCTAssertTrue(quote.hasSuffix("﴿۱۸﴾"))
    }

    /// Vowelled Arabic that is not the Qur'an - here a hadith - stays in the
    /// prose as the book's own text, never set as scripture.
    func testVowelledArabicNotInTheMushafStaysProse() {
        let text = "حدیث میں ہے کہ إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى یعنی اعمال کا دارومدار نیتوں پر ہے۔"
        let blocks = BookPageFormatter.format(text).blocks
        for block in blocks {
            if case .quran = block { XCTFail("a hadith was set as Qur'an: \(blocks)") }
            if case .paragraph(let runs) = block { XCTAssertFalse(runs.contains { $0.isQuranic }) }
        }
    }

    /// The original OCR must match the mushaf's vowels too; a page re-read by
    /// Claude is compared by its letters.
    func testOriginalOCRMustMatchTheVowelsToo() throws {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        let ayah = try XCTUnwrap(ayahs.first { $0.surahNumber == 112 && $0.ayahNumber == 1 })
        let words = ayah.textArabic.split(separator: " ").map(String.init)
        XCTAssertTrue(QuranQuotation.isVerified(words, check: .exact))
        var misread = words
        misread[0] = misread[0].replacingOccurrences(of: "\u{064F}", with: "\u{064E}")
        XCTAssertNotEqual(misread, words)
        XCTAssertTrue(QuranQuotation.isVerified(misread, check: .letters))
        XCTAssertFalse(QuranQuotation.isVerified(misread, check: .exact))
    }

    func testUrduWithAnOccasionalVowelMarkStaysProse() {
        let text = "اُس کا مقصود ہی اللہ ہے اور دورِ اول کے مفسرین کا انداز یہی تھا۔"
        XCTAssertEqual(BookPageFormatter.markQuranic(text.split(separator: " ").map(String.init)).filter { $0 }.count, 0)
    }

    func testTwoColumnPageSeparatesArabicFromItsTranslation() {
        let text = """
        وَمِنَ النَّاسِ مَنْ يَقُولُ اٰمَنَّا بِاللّٰهِ اور بعض لوگ ایسے ہیں جو کہتے ہیں
        وَبِالْيَوْمِ الْاٰخِرِ وَمَا هُمْ بِمُؤْمِنِيْنَ کہ ہم خدا پر اور آخرت پر ایمان رکھتے ہیں
        يُخٰدِعُوْنَ اللّٰهَ وَالَّذِيْنَ اٰمَنُوْا حالانکہ وہ ایمان نہیں رکھتے
        """
        let blocks = BookPageFormatter.format(text).blocks
        XCTAssertEqual(blocks.count, 2)
        guard case .quran(let arabic) = blocks[0], case .paragraph(let urdu) = blocks[1] else {
            return XCTFail("expected Arabic then Urdu: \(blocks)")
        }
        XCTAssertTrue(arabic.hasPrefix("وَمِنَ") && arabic.hasSuffix("اٰمَنُوْا"))
        XCTAssertTrue(urdu.first?.text.hasPrefix("اور بعض لوگ") == true)
    }

    func testContentsPageIsFolded() {
        let rows = (1...12).map { "\($0 * 7) اللہ کے حاضر و ناظر ہونے کا احساس \($0)" }.joined(separator: "\n")
        XCTAssertTrue(BookPageFormatter.format("صفحہ نمبر مندرجات نمبر شمار\n" + rows).isContents)
        XCTAssertFalse(BookPageFormatter.format("انسان جو چیز بناتا ہے اس کے استعمال کا ایک قاعدہ ہے۔").isContents)
    }

    /// Prose that mentions a list ("فہرست") is not an index page.
    func testProseMentioningAListIsNotFolded() {
        let sentence = "حضرت نے فرمایا کہ جو لوگ اللہ کی راہ میں نکلے وہ نیک لوگوں کی فہرست میں آ گئے اور ان کے دل روشن ہو گئے۔ "
        XCTAssertFalse(BookPageFormatter.format(String(repeating: sentence, count: 4)).isContents)
    }

    /// A page that opens with one long paragraph keeps it under its own number;
    /// only a short finishing fragment is ever carried back.
    func testALongFirstParagraphStaysOnItsOwnPage() {
        let first = BookPage(bookID: "b", page: 23, text: "جو شخص اپنے طریقے سے یا اپنے خیال کے مطابق اصلاح کرنا چاہتا ہے وہ", blocks: 1,
                             unresolvedBlocks: 0, reviewState: "claudeTranscribed", validator: "test")
        let long = String(repeating: "یہ ایک طویل جملہ ہے جو اگلے صفحے پر جاری رہتا ہے اور ", count: 10) + "ختم ہوا۔"
        let second = BookPage(bookID: "b", page: 24, text: long, blocks: 1,
                              unresolvedBlocks: 0, reviewState: "claudeTranscribed", validator: "test")
        let pages = BookPageFormatter.format(pages: [first, second])
        XCTAssertEqual(pages[second.id]?.blocks.count, 1)
        XCTAssertEqual(pages[first.id]?.blocks, [.paragraph([.init(text: first.text, isQuranic: false)])])
    }

    /// A page that is nothing but the words finishing the last one keeps them.
    func testAPageIsNeverLeftEmpty() {
        let first = BookPage(bookID: "b", page: 4, text: "جو شخص اپنے طریقے سے یا اپنے خیال کے مطابق اصلاح کرنا چاہتا ہے وہ", blocks: 1,
                             unresolvedBlocks: 0, reviewState: "claudeTranscribed", validator: "test")
        let second = BookPage(bookID: "b", page: 5, text: "فساد پیدا کرتا ہے۔", blocks: 1,
                              unresolvedBlocks: 0, reviewState: "claudeTranscribed", validator: "test")
        let pages = BookPageFormatter.format(pages: [first, second])
        XCTAssertEqual(pages[second.id]?.blocks.count, 1)
    }

    func testSentenceCutByThePageContinuesOnIt() {
        let first = BookPage(bookID: "b", page: 4, text: "اللہ کریم نے حضور اکرم ﷺ کو صحابہ کرام کی", blocks: 1,
                             unresolvedBlocks: 0, reviewState: "machineProvisional", validator: "test")
        let second = BookPage(bookID: "b", page: 5, text: "جماعت عطا فرمائی۔\n\nدوسرا پیراگراف یہاں سے شروع ہوتا ہے۔", blocks: 1,
                              unresolvedBlocks: 0, reviewState: "machineProvisional", validator: "test")
        let pages = BookPageFormatter.format(pages: [first, second])
        XCTAssertEqual(pages[first.id]?.blocks, [.paragraph([.init(
            text: "اللہ کریم نے حضور اکرم ﷺ کو صحابہ کرام کی جماعت عطا فرمائی۔", isQuranic: false
        )])])
        XCTAssertEqual(pages[second.id]?.blocks.count, 1)
    }

    // MARK: - Pages that carry their layout

    private func laidOut(_ parts: [String], layout: String, page: Int = 1) -> BookPage {
        BookPage(bookID: "b", page: page, text: parts.joined(separator: "\n\n"), blocks: parts.count,
                 unresolvedBlocks: 0, reviewState: "claudeTranscribed", validator: "test", layout: layout)
    }

    /// A re-read page is set out block by block as it was typed - nothing is
    /// guessed - and its footnote goes to the foot of the page.
    func testLaidOutPageIsSetOutAsTyped() {
        let page = BookPageFormatter.format(page: laidOut([
            "باب اول",
            "انسان جو چیز بناتا ہے اس کے استعمال کا ایک قاعدہ ہے۔",
            "تیرا نام لیتے ہیں غنچے چٹک کر\nکلی تیری عظمت کے گُن گا رہی ہے",
            "١ دیکھئے صفحہ ۲۳",
            "دارالسلام میں کھڑکی سے باہر کا ایک منظر",
        ], layout: "hpvfc"))
        XCTAssertFalse(page.isContents)
        XCTAssertEqual(page.blocks, [
            .heading("باب اول"),
            .paragraph([.init(text: "انسان جو چیز بناتا ہے اس کے استعمال کا ایک قاعدہ ہے۔", isQuranic: false)]),
            .verse("تیرا نام لیتے ہیں غنچے چٹک کر\nکلی تیری عظمت کے گُن گا رہی ہے"),
            .caption("دارالسلام میں کھڑکی سے باہر کا ایک منظر"),
        ])
        XCTAssertEqual(page.footnotes, ["١ دیکھئے صفحہ ۲۳"])
    }

    /// A paragraph keeps the line breaks it was printed with: a signature,
    /// or the numbered lines of the English column on an Asrar page.
    func testPrintedLineBreaksInAParagraphAreKept() {
        let signature = BookPageFormatter.format(page: laidOut(["خادم سلسلہ نقشبندیہ اویسیہ\nمحمد اکرم اعوان گلگت"], layout: "p"))
        XCTAssertEqual(signature.blocks, [.paragraph([
            .init(text: "خادم سلسلہ نقشبندیہ اویسیہ", isQuranic: false),
            .init(text: "محمد اکرم اعوان گلگت", isQuranic: false, startsLine: true),
        ])])
        let english = BookPageFormatter.format(page: laidOut(["70. And when he provided them\n71. They cried, coming towards them"], layout: "p"))
        XCTAssertEqual(english.blocks, [.paragraph([
            .init(text: "70. And when he provided them", isQuranic: false),
            .init(text: "71. They cried, coming towards them", isQuranic: false, startsLine: true),
        ])])
        XCTAssertFalse(ScriptDirection.isRightToLeft("70. And when he provided them", fallbackLanguage: "ur"))
    }

    /// A layout that does not fit the text - another number of parts, or a
    /// letter this version does not know - is ignored, never misapplied.
    func testALayoutThatDoesNotFitIsIgnored() {
        var page = laidOut(["فساد کی حقیقت:", "انسان جو چیز بناتا ہے اس کے استعمال کا ایک قاعدہ ہے۔"], layout: "h")
        XCTAssertNil(BookPageFormatter.laidOutParts(of: page))
        XCTAssertEqual(BookPageFormatter.format(page: page), BookPageFormatter.format(page.text))
        page.layout = "hx"
        XCTAssertNil(BookPageFormatter.laidOutParts(of: page))
        page.layout = nil
        XCTAssertNil(BookPageFormatter.laidOutParts(of: page))
        page.layout = "hp"
        XCTAssertEqual(BookPageFormatter.laidOutParts(of: page)?.map(\.kind), [BookPageFormatter.Kind.heading, .paragraph])
    }

    func testTableRowsAreCutIntoCells() {
        let page = BookPageFormatter.format(page: laidOut(["نام نماز | فرض | نفل\n| فجر | ۲ | |"], layout: "t"))
        XCTAssertEqual(page.blocks, [.table([["نام نماز", "فرض", "نفل"], ["فجر", "۲", ""]])])
    }

    /// An Arabic quotation the mushaf does not hold - here a hadith - is set
    /// apart as Arabic, never as the Qur'an.
    func testArabicQuotationNotInTheMushafIsNotQuran() {
        let hadith = "إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى (بخاری)"
        let page = BookPageFormatter.format(page: laidOut(["حدیث شریف میں ہے:", hadith], layout: "pa"))
        XCTAssertEqual(page.blocks.last, .arabic(hadith))
    }

    /// An ayah is set as the Qur'an when the mushaf holds it, the citation
    /// printed after it included.
    func testAyahWithItsCitationIsSetAsQuran() throws {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        let ayah = try XCTUnwrap(ayahs.first { $0.surahNumber == 20 && $0.ayahNumber == 18 })
        let quote = ayah.textArabic + " (طٰہٰ:۱۸)"
        let page = BookPageFormatter.format(page: laidOut(["موسیٰ علیہ السلام نے عرض کیا", quote], layout: "pa"))
        XCTAssertEqual(page.blocks.last, .quran(quote))
        // The ruku sign printed after an ayah, read as the letter ع, is not
        // a word of the ayah.
        let marked = ayah.textArabic + " ﴿۱۸﴾ ع"
        XCTAssertEqual(BookPageFormatter.format(page: laidOut([marked], layout: "a")).blocks, [.quran(marked)])
    }

    /// A run of ayat that the mushaf holds is set as the Qur'an even when an
    /// ayah inside the quotation is spelled otherwise: that ayah alone stays
    /// the book's Arabic, and nothing unconfirmed is set as scripture.
    func testOnlyTheConfirmedAyatOfAQuotationAreSetAsQuran() throws {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        func ayah(_ number: Int) throws -> String {
            try XCTUnwrap(ayahs.first { $0.surahNumber == 2 && $0.ayahNumber == number })
                .textArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var third = try ayah(3).split(separator: " ").map(String.init)
        third[2] = "كمبيوتر"
        let first = try ayah(2) + " ﴿۲﴾"
        let middle = third.joined(separator: " ") + " ﴿۳﴾"
        let last = try ayah(4) + " ﴿۴﴾"
        let page = BookPageFormatter.format(page: laidOut([[first, middle, last].joined(separator: " ")], layout: "a"))
        XCTAssertEqual(page.blocks, [.quran(first), .arabic(middle), .quran(last)])
    }

    /// A sentence cut by the page still continues on it when the page ends
    /// with a footnote: the footnote is set after the text.
    func testSentenceCutByThePageContinuesPastItsFootnote() {
        let first = laidOut(["اللہ کریم نے حضور اکرم ﷺ کو صحابہ کرام کی", "١ حاشیہ کی عبارت"], layout: "pf", page: 4)
        let second = laidOut(["جماعت عطا فرمائی۔ دوسرا جملہ یہاں سے شروع ہوتا ہے اور آگے چلتا ہے۔"], layout: "p", page: 5)
        let pages = BookPageFormatter.format(pages: [first, second])
        XCTAssertEqual(pages[first.id]?.blocks, [.paragraph([.init(
            text: "اللہ کریم نے حضور اکرم ﷺ کو صحابہ کرام کی جماعت عطا فرمائی۔", isQuranic: false
        )])])
        XCTAssertEqual(pages[first.id]?.footnotes, ["١ حاشیہ کی عبارت"])
        XCTAssertEqual(pages[second.id]?.blocks, [.paragraph([.init(
            text: "دوسرا جملہ یہاں سے شروع ہوتا ہے اور آگے چلتا ہے۔", isQuranic: false
        )])])
    }

    /// Verse is never broken up to finish the prose of the page before.
    func testVerseIsNeverCarriedAcrossAPage() {
        let first = laidOut(["جو شخص اپنے طریقے سے یا اپنے خیال کے مطابق اصلاح کرنا چاہتا ہے وہ"], layout: "p", page: 4)
        let couplet = "کہاں میں اور کہاں یہ نکہت گل۔\nنسیم صبح تیری مہربانی"
        let second = laidOut([couplet], layout: "v", page: 5)
        let pages = BookPageFormatter.format(pages: [first, second])
        XCTAssertEqual(pages[first.id]?.blocks, [.paragraph([.init(text: first.text, isQuranic: false)])])
        XCTAssertEqual(pages[second.id]?.blocks, [.verse(couplet)])
    }

    /// A re-read contents page still folds, and keeps its table to unfold.
    func testLaidOutContentsPageFoldsWithItsBlocks() {
        let rows = (1...12).map { "\($0)- باب \($0) | \($0 * 7)" }.joined(separator: "\n")
        let page = BookPageFormatter.format(page: laidOut(["فہرست", rows], layout: "ht"))
        XCTAssertTrue(page.isContents)
        XCTAssertEqual(page.blocks.first, .heading("فہرست"))
        guard case .table(let table)? = page.blocks.last else { return XCTFail("no table: \(page.blocks)") }
        XCTAssertEqual(table.count, 12)
        XCTAssertEqual(table.first, ["1- باب 1", "7"])
    }

    // MARK: - Matching the mushaf as the books write it

    /// The mushaf sets some letters apart for word-by-word reading (a lone
    /// "وَ"); a book that prints the word whole still matches it.
    func testMushafWordDivisionDoesNotDecide() throws {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        func letters(_ word: String) -> Int {
            word.unicodeScalars.filter { $0.properties.generalCategory == .otherLetter }.count
        }
        var found: (words: [String], lone: Int)?
        for ayah in ayahs {
            let words = ayah.textArabic.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count >= 4 else { continue }
            if let lone = words.indices.dropLast().first(where: { letters(words[$0]) == 1 && letters(words[$0 + 1]) > 1 }) {
                found = (words, lone)
                break
            }
        }
        let (words, lone) = try XCTUnwrap(found, "no ayah sets a letter apart")
        var joined = words
        let next = joined.remove(at: lone + 1)
        joined[lone] += next
        XCTAssertTrue(QuranQuotation.isVerified(words, check: .letters))
        XCTAssertTrue(QuranQuotation.isVerified(joined, check: .letters))
    }

    /// The mushaf seats a hamza, and a medial yeh, on a dotless letter
    /// (اُولٰٓٮِٕكَ); a book that writes ئ still matches it.
    func testIndoPakYehSeatMatchesTheBooksSpelling() throws {
        let ayahs = SeedBundle.quranAyahs()
        try XCTSkipIf(ayahs.isEmpty, "Arabic text pack not bundled in this configuration")
        let ayah = try XCTUnwrap(ayahs.first {
            $0.textArabic.unicodeScalars.contains("\u{066E}") && $0.textArabic.split(separator: " ").count >= 4
        })
        let respelled = String(String.UnicodeScalarView(ayah.textArabic.unicodeScalars.map { scalar -> Unicode.Scalar in
            scalar == "\u{066E}" ? "\u{0626}" : scalar
        }))
        XCTAssertNotEqual(respelled, ayah.textArabic)
        let words = respelled.split(whereSeparator: \.isWhitespace).map(String.init)
        XCTAssertTrue(QuranQuotation.isVerified(words, check: .letters))
    }
}
