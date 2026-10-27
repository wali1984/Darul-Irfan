import XCTest
@testable import DarulIrfan

/// The Urdu page layout: headings, joined lines, quotations set apart,
/// contents pages folded, and sentences carried across a page break.
final class BookPageFormatterTests: XCTestCase {

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

    func testLongQuotationStandsApart() {
        let text = "مختصر سوال ہوا کہ قَالَ هِيَ عَصَايَ أَتَوَكَّأُ عَلَيْهَا وَأَهُشُّ بِهَا عَلَىٰ غَنَمِي ﴿۱۸﴾ بات ختم ہو گئی۔"
        let blocks = BookPageFormatter.format(text).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .quran(let quote) = blocks[1] else { return XCTFail("no quotation block: \(blocks)") }
        XCTAssertTrue(quote.hasPrefix("قَالَ"))
        XCTAssertTrue(quote.hasSuffix("﴿۱۸﴾"))
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
}
