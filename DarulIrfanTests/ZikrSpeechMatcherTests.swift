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
                          "latifa-4", "latifa-5", "latifa-6", "latifa-7", "raabta", "ahadiyat", "maiyyat", "aqrabiyyat",
                          "sair-kaaba", "rauza-athar", "masjid-nabawi"])
        XCTAssertTrue(Set(ZikrSpeechMatcher.phrases.map(\.stage)).isSubset(of: server))
    }

    /// Each call-out as Whisper wrote it from the Daily Zikr of 2 and 3 Nov 2026, in Urdu and in Hindi.
    func testTheCallOutsOfRealDailyZikrSessions() {
        let heard: [(String, String)] = [
            ("دوسرا لطیفہ", "latifa-2"), ("تیسرے لطیفہ", "latifa-3"), ("چوتھا لطیفہ", "latifa-4"),
            ("پانچوا لطیفہ", "latifa-5"), ("پانچو لطیفہ", "latifa-5"), ("چھتا لطیفہ", "latifa-6"),
            ("ساتوا لطیفہ", "latifa-7"), ("ساتھو لطیفہ", "latifa-7"), ("اہلا لطیفہ", "latifa-1"), ("پہلے لطیفہ", "latifa-1"),
            ("مراقبہ عادیت", "ahadiyat"), ("معیت", "maiyyat"), ("اقربیت", "aqrabiyyat"),
            ("سہر کعبہ", "sair-kaaba"), ("روز اثر", "rauza-athar"), ("روزہ اثر", "rauza-athar"), ("مسجد نبی", "masjid-nabawi"),
            ("कि दूसरे लदीफा", "latifa-2"), ("पांचवा लदीफा", "latifa-5"), ("छटने लदीफा", "latifa-6"),
            ("छट्टे लदीफा", "latifa-6"), ("साथ लदीफा", "latifa-7"), ("पहले लदीफा", "latifa-1"),
            ("मुराक्व आधियत", "ahadiyat"), ("माईयत", "maiyyat"), ("अक्रबियत", "aqrabiyyat"),
            ("सहर काबा", "sair-kaaba"), ("रोजा अथर", "rauza-athar"), ("मस्चे नवी", "masjid-nabawi"),
        ]
        for (words, expected) in heard {
            XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized(words)), expected, words)
        }
        // A whole run of call-outs names the last one.
        XCTAssertEqual(ZikrSpeechMatcher.stage(in: ZikrSpeechMatcher.normalized("مراقبہ عادیت معیت اقربیت سہر کعبہ روزہ اثر مسجد نبوی آمین")),
                       "masjid-nabawi")
    }
}
