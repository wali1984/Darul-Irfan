import XCTest
@testable import DarulIrfan

/// What the live stage's voice listener makes of Hazrat ji's words, as each
/// recognizer writes them (Arabic for the recitations; Urdu, or Hindi where
/// the phone has no Urdu recognizer, for the stages he calls out).
final class ZikrSpeechMatcherTests: XCTestCase {
    func testOpeningRecitationsAsTheArabicRecognizerWritesThem() {
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("سبحان الله والحمد لله ولا إله إلا الله")), "tasbih")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("أستغفر الله ربي من كل ذنب")), "istighfar")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("أَشْهَدُ أَنْ لَا إِلٰهَ إِلَّا اللّٰهُ")), "shahadah")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("أعوذ بالله من الشيطان الرجيم")), "taawwudh")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("بسم الله الرحمن الرحيم")), "basmalah")
    }

    func testCalledOutStagesInUrduAndHindi() {
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("اب پہلا لطیفہ شروع کریں")), "latifa-1")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("अब पहला लतीफ़ा")), "latifa-1")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("सातवें लतीफे पर")), "latifa-7")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("اب رابطہ")), "raabta")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("मुराक़बा अहदियत")), "ahadiyat")
    }

    func testTheLastStageNamedWins() {
        let transcript = ZikrSpeechMatcher.normalized("پہلا لطیفہ ہو گیا اب دوسرا لطیفہ")
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: transcript), "latifa-2")
    }

    func testOrdinarySpeechNamesNoStage() {
        XCTAssertNil(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("السلام علیکم سب کو")))
        XCTAssertNil(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("आप सब कैसे हैं")))
    }

    func testEveryStageTheListenerCanNameExistsOnTheServer() {
        let server = Set(["tasbih", "istighfar", "shahadah", "taawwudh", "basmalah", "latifa-1", "latifa-2", "latifa-3",
                          "latifa-4", "latifa-5", "latifa-6", "latifa-7", "raabta", "ahadiyat", "maiyyat", "aqrabiyyat"])
        XCTAssertTrue(Set(ZikrSpeechMatcher.phrases.map(\.stage)).isSubset(of: server))
    }
}
