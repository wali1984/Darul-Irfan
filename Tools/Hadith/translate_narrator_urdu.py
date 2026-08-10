#!/usr/bin/env python3
"""Agent-authored Urdu for the narrator store — grade terminology pass (no network).

The narrator bios ship with English + Arabic; every entry is flagged
`needsUrdu`. This pass translates the one field that is standard, bounded and
safe to render faithfully by hand: the **grading** (jarḥ wa-taʿdīl verdict),
which across 6,641 narrators is only 261 distinct English phrases built from a
small, well-established vocabulary. It sets `gradeUrdu` on every narrator whose
grade we can render, using an exact-phrase map first and otherwise composing the
verdict from a term glossary.

It deliberately does NOT hand-translate the ~65k appraisal-prose texts (classical
Arabic jarḥ wa-taʿdīl): translating that volume of scholarly text ad-hoc is not
reliable enough to ship as authoritative religious content, so those stay
`needsUrdu` for a reviewed machine-translation pass. Nothing is fabricated: a
grade with no known rendering is left without `gradeUrdu`.

    python Tools/Hadith/translate_narrator_urdu.py --write     # update 4 seeds
    python Tools/Hadith/translate_narrator_urdu.py             # dry-run report
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = IOS_ROOT.parent
SEED_DIRS = [
    IOS_ROOT / "DarulIrfanApp/Resources/SeedData",
    REPO_ROOT / "DarulIrfanAndroid/app/src/main/assets/seed",
    REPO_ROOT / "DarulIrfanHarmony/entry/src/main/resources/rawfile/seed",
    REPO_ROOT / "DarulIrfanWeb/content",
]
STORE = "hadith_narrators.json"

# Exact-phrase renderings for the common verdicts (cover the vast majority).
PHRASE = {
    "Trustworthy": "ثقہ",
    "Truthful, Good Hadith": "صدوق، حسن الحدیث",
    "Acceptable": "مقبول",
    "Companion": "صحابی",
    "Weak in Hadith": "ضعیف الحدیث",
    "Unknown": "مجہول",
    "Unknown Status": "مجہول الحال",
    "Abandoned in Hadith": "متروک الحدیث",
    "Trustworthy, Firm": "ثقہ ثبت",
    "Trustworthy, Expert": "ثقہ حافظ",
    "Denounced in Hadith": "منکر الحدیث",
    "Has Sight": "دیدارِ نبوی رکھنے والا",
    "Disputed Companionship": "صحبت میں اختلاف",
    "Truthful, Makes Errors": "صدوق، غلطیاں کرتا ہے",
    "Truthful, Has Errors": "صدوق، اوہام رکھتا ہے",
    "Young Companion": "صحابی صغیر",
    "Truthful, Prone to Error": "صدوق، خطا کا شکار",
    "Deemed Trustworthy by Ibn Hibban Alone": "صرف ابنِ حبان نے ثقہ کہا",
    "Accused of Fabrication": "وضع کا الزام",
    "Trustworthy, Precise": "ثقہ متقن",
    "Trustworthy, Reliable": "ثقہ معتمد",
    "Accused of Lying": "کذب کا الزام",
    "Truthful, Frequent Errors": "صدوق، کثیر الخطا",
    "Truthful, Poor Memory": "صدوق، سیئ الحفظ",
    "Fabricator": "وضّاع",
    "Has Perception": "دیدار رکھنے والا",
    "Trustworthy, Authority": "ثقہ حجت",
    "Doubly Trustworthy": "ثقہ ثقہ",
    "Liar": "کذاب",
    "Trustworthy, Expert, Imam": "ثقہ حافظ امام",
    "Companionship Not Established": "صحبت ثابت نہیں",
    "Some Weakness in Hadith": "حدیث میں کچھ ضعف",
    "Weak, Poor Memory": "ضعیف، سیئ الحفظ",
}

# Component glossary to compose the long tail ("A, B, C" -> "a، b، c").
TERMS = {
    "Trustworthy": "ثقہ", "Truthful": "صدوق", "Good Hadith": "حسن الحدیث",
    "Good": "حسن", "Acceptable": "مقبول", "Companion": "صحابی",
    "Weak in Hadith": "ضعیف الحدیث", "Weak": "ضعیف", "Unknown Status": "مجہول الحال",
    "Unknown": "مجہول", "Abandoned in Hadith": "متروک الحدیث", "Abandoned": "متروک",
    "Firm": "ثبت", "Expert": "حافظ", "Denounced in Hadith": "منکر الحدیث",
    "Makes Errors": "غلطیاں کرتا ہے", "Has Errors": "اوہام رکھتا ہے",
    "Frequent Errors": "کثیر الخطا", "Frequently Errs": "کثیر الخطا",
    "Occasionally Errs": "کبھی کبھار خطا", "Prone to Error": "خطا کا شکار",
    "Poor Memory": "سیئ الحفظ", "Precise": "متقن", "Reliable": "معتمد",
    "Authority": "حجت", "Jurist": "فقیہ", "Imam": "امام", "Memorizer": "حافظ",
    "Practices Tadlis": "مدلس", "Practiced Tadlis": "مدلس", "Tadlis": "تدلیس",
    "Fabricator": "وضّاع", "Liar": "کذاب", "Virtuous": "فاضل", "Devout": "عابد",
    "Pious": "متقی", "Righteous": "صالح", "Scholar": "عالم", "Ascetic": "زاہد",
    "Well-Known": "مشہور", "Distinguished": "ممتاز", "Senior": "کبیر",
    "Straddles Both Eras": "مخضرم", "Sunni": "سنی", "Young Companion": "صحابی صغیر",
    "Makes Mursal Narrations": "مرسل روایات", "Frequent Mursal Narrations": "کثرت سے مرسل روایات",
    "Became Confused Later": "بعد میں مختلط", "Became Confused": "مختلط",
    "Has Unique Narrations": "غرائب رکھنے والا", "Has Rare Narrations": "نادر روایات",
    "Makes Mistakes": "غلطیاں کرتا ہے", "Makes Errors and Confuses": "غلطی و اختلاط",
    "Has Sight": "دیدارِ نبوی رکھنے والا", "Disputed Companionship": "صحبت میں اختلاف",
    "Accused of Fabrication": "وضع کا الزام", "Accused of Lying": "کذب کا الزام",
    "Accused of Shi'ism": "تشیع کا الزام", "Accused of Qadarism": "قدر کا الزام",
    "Accused of Irja'": "ارجاء کا الزام", "Accused of Nasb": "نصب کا الزام",
    "Accused of Rafidhi Views": "رفض کا الزام", "Accused of Kharijite Views": "خارجیت کا الزام",
    "Inclines to Shi'ism": "تشیع کی طرف مائل", "Has Shi'ite Leanings": "شیعی رجحان",
    "Has Shi'ite Inclinations": "شیعی رجحان", "Staunch Shi'ite": "پکا شیعہ",
    "Some Weakness": "کچھ ضعف", "Some Weakness in Hadith": "حدیث میں کچھ ضعف",
    "Imam": "امام", "Author": "مصنف", "Has Written Works": "تصانیف رکھتا ہے",
    "Knowledgeable": "صاحبِ علم", "Prolific Narrator": "کثیر الروایہ",
    "Prolific in Hadith": "کثیر الحدیث", "Hadith Specialist": "ماہرِ حدیث",
    "Memory Deteriorated": "حافظہ کمزور ہوگیا", "Memory Slightly Deteriorated": "حافظہ قدرے کمزور",
    "Deteriorated": "حافظہ کمزور ہوگیا", "Nasibi": "ناصبی", "Rafidhi": "رافضی",
    "Qadarite": "قدری", "Jahmi": "جہمی",
    # long-tail composites
    "Memorizer": "حافظ", "Good Memory": "قوی الحافظہ", "Faithful": "امین",
    "Likely a Successor": "ظاہراً تابعی", "Likely a Trustworthy Successor": "ظاہراً ثقہ تابعی",
    "Trustworthy Successor": "ثقہ تابعی", "More Likely a Companion": "غالباً صحابی",
    "Occasionally Makes Errors": "کبھی کبھار غلطی", "Occasionally Contradicts": "کبھی مخالفت",
    "Made Mursal Narrations": "مرسل روایات", "Frequent Tadlis": "کثرت سے تدلیس",
    "Practiced Frequent Tadlis": "کثرت سے تدلیس", "One of the Memorizers": "حفاظ میں سے",
    "Established Authority": "مسلّمہ حجت", "Produces Rare Narrations": "نادر روایات",
    "Extreme in Shi'ite Leanings": "غالی شیعہ", "Criticized for Qadarism": "قدر پر تنقید",
    "Criticized for Nasb": "نصب پر تنقید", "Has Nasibi Tendencies": "ناصبی رجحان",
    "Slight Shi'ite Leanings": "خفیف شیعی رجحان", "Prolific Author": "کثیر التصانیف",
    "Best of the People of His Time": "اپنے دور کے بہترین", "Approved": "مقبول",
    "Confused Later": "بعد میں مختلط", "Confused before Death": "وفات سے قبل مختلط",
    "Aged": "معمر", "Wicked": "فاسق", "Some Weakness in Hadith": "حدیث میں کچھ ضعف",
}


def render(grade: str) -> str | None:
    if not grade:
        return None
    g = grade.strip()
    g = re.sub(r"^verified\s+", "", g)   # "verified" = the verdict is documented
    if g in PHRASE:
        return PHRASE[g]
    parts = [p.strip() for p in g.split(",") if p.strip()]
    out, ok = [], True
    for p in parts:
        if p in TERMS:
            out.append(TERMS[p])
        elif p in PHRASE:
            out.append(PHRASE[p])
        else:
            ok = False
            break
    return "، ".join(out) if ok and out else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    src = SEED_DIRS[0] / STORE
    narrators = json.loads(src.read_text(encoding="utf-8"))
    done = 0
    unrendered: dict[str, int] = {}
    for n in narrators:
        if n.get("gradeUrdu"):
            done += 1
            continue
        ur = render(n.get("gradeEnglish", ""))
        if ur:
            n["gradeUrdu"] = ur
            done += 1
        else:
            g = n.get("gradeEnglish", "")
            unrendered[g] = unrendered.get(g, 0) + 1

    total = len(narrators)
    print(f"narrators: {total}")
    print(f"gradeUrdu set: {done}  ({100*done//max(total,1)}%)")
    print(f"grades left un-rendered (distinct): {len(unrendered)}  "
          f"covering {sum(unrendered.values())} narrators")
    for g, c in sorted(unrendered.items(), key=lambda x: -x[1])[:15]:
        print(f"    {c:4}  {g!r}")

    if not args.write:
        print("\n--dry run (pass --write to update the four seeds)")
        return 0

    text = json.dumps(narrators, ensure_ascii=False, indent=1) + "\n"
    for d in SEED_DIRS:
        p = d / STORE
        if p.exists():
            p.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote -> {d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
