import XCTest
@testable import DarulIrfan

/// Whether a stage heard on the leading admin's phone becomes the stage: the
/// live Zikr's order and timing, as proven on Our Sheikh's relay
/// (10 November 2026). Android runs the same cases (ZikrStageRulesTest.kt).
final class ZikrStageRulesTests: XCTestCase {
    /// A bayan's talk, read every second: sentences, never one word over and over.
    private let bayan = ["آج ہم بات کریں گے اس کے بارے میں", "کسی اور تحقیق کی ضرورت نہیں ہے", "دین کی بات جاتی ہے کرنے کی",
                         "ہمارے پاس خیر کا راستہ ہے", "اس میں اللہ کی رحمت ہے اور"]
    /// The Zikr's own sound: nothing, or one or two words over and over.
    private let zikrSound = ["اللہ اللہ اللہ", "", "اللہ ہو اللہ ہو", "اللہ"]

    private func feed(_ rules: inout ZikrStageRules, _ readings: [String], current: String?, from start: Int, to end: Int) {
        for second in start..<end {
            XCTAssertNil(rules.decide(current: current, callout: readings[second % readings.count], at: TimeInterval(second)))
        }
    }

    func testTheOpeningInOrderThenTheFirstLatifa() {
        var rules = ZikrStageRules()
        XCTAssertEqual(rules.decide(current: nil, callout: "سبحان اللہ والحمد للہ ولا الہ الا اللہ واللہ اکبر", at: 10), "tasbih")
        rules.took("tasbih", at: 10)
        XCTAssertEqual(rules.decide(current: "tasbih", callout: "استغفر اللہ ربی من کل ذنب", at: 20), "istighfar")
        XCTAssertEqual(rules.decide(current: "istighfar", callout: "اشہد ان لا الہ الا اللہ", at: 25), "shahadah")
        XCTAssertEqual(rules.decide(current: "shahadah", callout: "اعوذ باللہ من الشیطان الرجیم", at: 30), "taawwudh")
        XCTAssertEqual(rules.decide(current: "taawwudh", callout: "بسم اللہ الرحمن الرحیم", at: 33), "basmalah")
        // The 1st Latifa straight after the opening: no gap, and the recitations' "talk" does not count.
        XCTAssertEqual(rules.decide(current: "basmalah", callout: "پہلا لطیفہ", at: 36), "latifa-1")
    }

    func testTheOpeningNeverGoesBackButMaySkip() {
        var rules = ZikrStageRules()
        XCTAssertNil(rules.decide(current: "shahadah", callout: "استغفر اللہ", at: 40))
        XCTAssertEqual(rules.decide(current: "tasbih", callout: "بسم اللہ الرحمن الرحیم", at: 50), "basmalah")
    }

    func testTheTasbihAsTheArabicAndHindiRecognizersWriteIt() {
        var arabic = ZikrStageRules()
        XCTAssertEqual(arabic.decide(current: nil, callout: "", arabic: "سُبْحَانَ اللّٰهِ وَالْحَمْدُ لِلّٰهِ", at: 10), "tasbih")
        var hindi = ZikrStageRules()
        XCTAssertEqual(hindi.decide(current: nil, callout: "सुब्हान अल्लाह अल्लाहु अकबर", at: 10), "tasbih")
    }

    func testSubhanAllahAloneInABayanDoesNotStartTheZikr() {
        var rules = ZikrStageRules()
        XCTAssertNil(rules.decide(current: nil, callout: "سبحان اللہ کیا بات ہے", at: 10))
        // A bayan opens with "اعوذ باللہ ... بسم اللہ": neither starts the Zikr.
        var bayanOpening = ZikrStageRules()
        XCTAssertNil(bayanOpening.decide(current: nil, callout: "اعوذ باللہ من الشیطان الرجیم", at: 10))
        XCTAssertNil(bayanOpening.decide(current: nil, callout: "بسم اللہ الرحمن الرحیم", at: 13))
    }

    func testALatifaNamedInABayanIsRefused() {
        var rules = ZikrStageRules()
        XCTAssertNil(rules.decide(current: nil, callout: "سبحان اللہ کیا بات ہے", at: 55))
        feed(&rules, bayan, current: nil, from: 60, to: 100)
        XCTAssertNil(rules.decide(current: nil, callout: "پہلا لطیفہ", at: 100))
        // Even once a stage is on: a Latifa named in talk does not move it.
        var later = ZikrStageRules()
        later.observe("latifa-3", at: 0)
        feed(&later, bayan, current: "latifa-3", from: 260, to: 300)
        XCTAssertNil(later.decide(current: "latifa-3", callout: "چوتھا لطیفہ", at: 300))
    }

    func testACallAfterTheZikrSoundIsTaken() {
        var rules = ZikrStageRules()
        rules.observe("latifa-3", at: 0)
        feed(&rules, zikrSound, current: "latifa-3", from: 260, to: 300)
        XCTAssertEqual(rules.decide(current: "latifa-3", callout: "اللہ اللہ چوتھا لطیفہ", at: 300), "latifa-4")
    }

    func testNoNewStageWithinFortySecondsOfTheLast() {
        var rules = ZikrStageRules()
        rules.observe("latifa-2", at: 100)
        XCTAssertNil(rules.decide(current: "latifa-2", callout: "تیسرا لطیفہ", at: 130))
        XCTAssertEqual(rules.decide(current: "latifa-2", callout: "تیسرا لطیفہ", at: 141), "latifa-3")
        // A tap (the stage seen to change) starts the gap too.
        XCTAssertNil(rules.decide(current: "latifa-4", callout: "", at: 200))
        XCTAssertNil(rules.decide(current: "latifa-4", callout: "پانچواں لطیفہ", at: 220))
        XCTAssertEqual(rules.decide(current: "latifa-4", callout: "پانچواں لطیفہ", at: 241), "latifa-5")
    }

    func testAfterTheSeventhALatifaCallIsTheReturnThenAMuraqabaIsTaken() {
        var rules = ZikrStageRules()
        rules.observe("latifa-7", at: 0)
        XCTAssertNil(rules.decide(current: "latifa-7", callout: "پہلا لطیفہ", at: 100))
        XCTAssertNil(rules.decide(current: "latifa-7", callout: "دوسرا لطیفہ", at: 101))
        XCTAssertEqual(rules.decide(current: "latifa-7", callout: "رابطہ", at: 102), "raabta")
        XCTAssertEqual(rules.decide(current: "latifa-7", callout: "مراقبہ احدیت", at: 103), "ahadiyat")
        XCTAssertNil(rules.decide(current: "latifa-7", callout: "معیت", at: 104))
        // The return to the 1st shown on the stage: Raabta still follows, never the 2nd Latifa.
        var returned = ZikrStageRules()
        returned.observe("latifa-7", at: 0)
        returned.observe("latifa-1", at: 50)
        XCTAssertNil(returned.decide(current: "latifa-1", callout: "دوسرا لطیفہ", at: 100))
        XCTAssertEqual(returned.decide(current: "latifa-1", callout: "رابطہ", at: 101), "raabta")
    }

    func testALatifaMayJumpTwoPastTheNextNotThree() {
        var rules = ZikrStageRules()
        rules.observe("latifa-3", at: 0)
        XCTAssertEqual(rules.decide(current: "latifa-3", callout: "پانچواں لطیفہ", at: 100), "latifa-5")
        XCTAssertEqual(rules.decide(current: "latifa-3", callout: "چھٹا لطیفہ", at: 101), "latifa-6")
        XCTAssertNil(rules.decide(current: "latifa-3", callout: "ساتواں لطیفہ", at: 102))
        var muraqaba = ZikrStageRules()
        muraqaba.observe("raabta", at: 0)
        XCTAssertEqual(muraqaba.decide(current: "raabta", callout: "معیت", at: 100), "maiyyat")
        XCTAssertNil(muraqaba.decide(current: "raabta", callout: "اقربیت", at: 101))
    }

    func testNeverBackwards() {
        var rules = ZikrStageRules()
        rules.observe("latifa-4", at: 0)
        XCTAssertNil(rules.decide(current: "latifa-4", callout: "دوسرا لطیفہ", at: 100))
        XCTAssertNil(rules.decide(current: "latifa-4", callout: "چوتھا لطیفہ", at: 101))
        var muraqaba = ZikrStageRules()
        muraqaba.observe("maiyyat", at: 0)
        XCTAssertNil(muraqaba.decide(current: "maiyyat", callout: "احدیت", at: 100))
    }

    func testACustomStageOrTheDuaIsNeverMovedByVoice() {
        for stage in ["dua", "custom-1a2b", "shajra"] {
            var rules = ZikrStageRules()
            rules.observe(stage, at: 0)
            XCTAssertNil(rules.decide(current: stage, callout: "پہلا لطیفہ", at: 100), stage)
            XCTAssertNil(rules.decide(current: stage, callout: "رابطہ", at: 101), stage)
            XCTAssertNil(rules.decide(current: stage, callout: "مسجد نبوی", at: 102), stage)
        }
    }

    func testALatifaIsNeverTakenFromALongReading() {
        var rules = ZikrStageRules()
        rules.observe("latifa-2", at: 0)
        XCTAssertNil(rules.decide(current: "latifa-2", callout: "اس میں تیسرا لطیفہ جو ہے وہ", at: 100))
    }

    func testThreeOpeningRecitationsInARowStartTheZikrEvenInTalk() {
        var rules = ZikrStageRules()
        feed(&rules, bayan, current: nil, from: 0, to: 40)
        XCTAssertNil(rules.decide(current: nil, callout: "استغفر اللہ ربی", at: 41))
        XCTAssertNil(rules.decide(current: nil, callout: "اشہد ان لا الہ", at: 45))
        XCTAssertEqual(rules.decide(current: nil, callout: "اعوذ باللہ", at: 50), "taawwudh")
    }

    func testAFirstLatifaBeforeAnyStageNeedsAnOpeningRecitationFirst() {
        var cold = ZikrStageRules()
        XCTAssertNil(cold.decide(current: nil, callout: "پہلا لطیفہ", at: 100))
        var afterTasbih = ZikrStageRules()
        XCTAssertNil(afterTasbih.decide(current: nil, callout: "سبحان اللہ", at: 60))
        XCTAssertEqual(afterTasbih.decide(current: nil, callout: "پہلا لطیفہ", at: 100), "latifa-1")
    }

    func testTheRecentWordsAreTheLastFewSecondsOfEveryTranscript() {
        var words = ZikrRecentWords()
        words.update(0, transcript: "a b", at: 0)
        words.update(0, transcript: "a b c", at: 3)
        XCTAssertEqual(words.reading(0, at: 4), "a b c")
        XCTAssertEqual(words.reading(0, at: 6), "c")
        // A partial result that changes a word: the new one is heard now, the old one is gone.
        words.update(0, transcript: "a b d", at: 4)
        XCTAssertEqual(words.reading(0, at: 8), "d")
        // Recognition starts afresh: the last transcript still counts for a few seconds.
        words.endAll(at: 5)
        words.update(0, transcript: "e", at: 6)
        XCTAssertEqual(words.reading(0, at: 7), "d e")
        XCTAssertEqual(words.reading(1, at: 7), "")
    }

    func testTheMatcherGivesThePhraseThatNamedTheStage() {
        let match = ZikrSpeechMatcher.match(in: ZikrSpeechMatcher.normalized("اب دوسرا لطیفہ"))
        XCTAssertEqual(match?.stage, "latifa-2")
        XCTAssertEqual(match?.phrase, ZikrSpeechMatcher.normalized("دوسرا لطیفہ"))
    }
}
