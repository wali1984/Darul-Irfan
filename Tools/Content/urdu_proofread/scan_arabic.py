"""A different road from the shield: every applied edit that could be a change to Arabic, listed to be read.

A finding is listed when, outside what the owner approved, any of these holds:
  A  a changed word carries two or more harakat;
  B  the change lies in a block the layout marks as Arabic;
  C  with the change made, the changed word stands in three words of the mushaf (a bare quotation
     whose slip hid it from the shield);
  D  a changed pair of words, both free of Urdu-only letters, is a pair in the mushaf;
  E  the reader filed it, or explains it, as a Qur'an, hadith, du'a or Arabic matter and letters change;
  F  a well-known phrase of the Qur'an or of dhikr changes (typed bare, the shield cannot see it);
  G  the proposal puts in a vowelled or Arabic-spelt word where the print had none;
  N  the name of a surah or para changes.
"""
import json
import re
import sys
from collections import Counter

import apply_proofread as ap

sys.stdout.reconfigure(encoding="utf-8")
base = {(r["bookID"], r["page"]): r for r in json.loads(ap.base_file("book_pages.json").read_bytes())}
findings = {f["id"]: f for f in ap.read_json(ap.REGISTER / "findings.json")}
ledger = json.loads((ap.OUT / "ledger.json").read_text(encoding="utf-8"))
mushaf = ap.Mushaf(ap.base_file("quran_ayahs.json"))
URDU_ONLY = set("ٹپچڈڑژگںےۂ")
CATEGORY = ("quran", "arab", "hadith", "dua", "ayah", "verse", "scripture", "kalima")
REASON = ("آیت", "قرآنی", "مصحف", "عربی", "حدیث", "دعائیہ", "کلمہ طیبہ")

PHRASE = re.compile("الر[ّ]?ح[یي]?م|الراحم|العالم|العلم[یي]ن|النب[یيّ]+ن|ا?ن ?شا[ءئ]? ?ال|بسم|سبحان|الحمد|العیاذ|اعوذ"
                    "|لاحول|لا حول|استغفر|جزاک|الا اللہ|ما ?شا[ءئ]? ?ال|للعالم|من اللہ|حقُّ")
NAME = re.compile(r"(?:سور[ہۃۂت]|پار[ہۂ])\s*[0-9۰-۹]*\s*([^\s،۔]+)")
counts, rows = Counter(), []
for fid, entry in ledger.items():
    if entry["status"] != "applied" or fid in ap.APPROVED or fid not in findings:
        continue
    f = findings[fid]
    proposed = f.get("suggested")
    if not proposed:
        continue
    original, at = f["original"], f["offsetUtf16"]
    page = base[(f["bookID"], f["page"])]
    old = page["text"]
    atoms = ap.atomic_edits(original, proposed)
    changed_letters = ap.skeleton_words(original) != ap.skeleton_words(proposed)
    flags = set()
    if page.get("layout"):
        for (s, e), kind in zip(ap.block_bounds(old), page["layout"]):
            if kind == "a" and any(s <= at + a and at + b <= e for a, b, _ in atoms):
                flags.add("B")
    for a, b, r in atoms:
        if any(sum(c in ap.HARAKAT for c in t) >= 2 for _, _, t in ap.tokens(original[a:b])):
            flags.add("A")
        if ap.skeleton_words(original[a:b]) == ap.skeleton_words(r):
            continue
        left = old[max(0, at + a - 70):at + a]
        new = left + r + old[at + b:at + b + 70]
        words = [(s, e, t) for s, e, t in ap.tokens(new) if ap.is_word_char(t[0]) and ap.skeleton(t)]
        frames = [ap.skeleton(t) for _, _, t in words]
        put = {i for i, (s, e, _) in enumerate(words) if s < len(left) + len(r) and len(left) < e}
        for i in range(len(words) - 2):
            if put & {i, i + 1, i + 2} and tuple(frames[i:i + 3]) in mushaf.trigrams:
                flags.add("C")
        for i in range(len(words) - 1):
            if put & {i, i + 1} and tuple(frames[i:i + 2]) in mushaf.bigrams and len(frames[i] + frames[i + 1]) >= 6 \
                    and not URDU_ONLY & set(words[i][2] + words[i + 1][2]):
                flags.add("D")
    if changed_letters and (any(w in f.get("category", "").lower() for w in CATEGORY)
                            or any(w in f.get("reasonUrdu", "") for w in REASON)):
        flags.add("E")
    if PHRASE.findall(original) != PHRASE.findall(proposed):
        flags.add("F")
    old_words = {t for _, _, t in ap.tokens(original)}
    for _, _, t in ap.tokens(proposed):
        if t in old_words or URDU_ONLY & set(t):
            continue
        if sum(c in ap.HARAKAT for c in t) >= 2 or any(c in "ةإأيكٱ" for c in t):
            flags.add("G")
    if changed_letters and NAME.findall(original) != NAME.findall(proposed):
        flags.add("N")
    if flags:
        tag = "".join(sorted(flags))
        counts[tag] += 1
        rows.append((tag, fid, f["bookID"], f["page"], f.get("category", ""), original, proposed, f.get("reasonUrdu", "")))

rows.sort()
(ap.OUT / "arabic-scan.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(rows), dict(counts))
for tag, fid, book, page, category, original, proposed, _ in rows:
    print(f"{tag} {fid} {category[:28]}\n   - {original[:110]!r}\n   + {proposed[:110]!r}")
