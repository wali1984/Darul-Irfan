"""OCR the English Asrar-at-Tanzil tafseer PDFs into native, inline per-surah
text for the Quran reader.

The Sheikh's tafseer is published only as image-scan PDFs (no text layer). This
renders each page with PyMuPDF and reads it with RapidOCR (ONNX, no external
binary), producing verbatim English text with a clear provenance note. English
scans OCR reliably; Urdu Nastaliq is a separate, verification-heavy pass and is
NOT run here.

Usage:
  python ocr_tafseer.py --surahs 1,103,108,112,113,114 --lang en
Outputs/merges quran_tafsir.json entries (editionID asrar-at-tanzil-en).
"""
import argparse, json, re, sys, urllib.request, io, os
sys.stdout.reconfigure(encoding="utf-8")

import fitz  # PyMuPDF
import numpy as np
from rapidocr_onnxruntime import RapidOCR

SEED = os.path.join(os.path.dirname(__file__), "..", "..",
                    "DarulIrfanApp", "Resources", "SeedData")
UA = "DarulIrfanContentIngest/1.0 (+mailto:wajidali1984@hotmail.com)"
_engine = None

def engine():
    global _engine
    if _engine is None:
        _engine = RapidOCR()
    return _engine

def download(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read()

def ocr_pdf(data, max_pages=60, dpi=200):
    doc = fitz.open(stream=data, filetype="pdf")
    lines = []
    zoom = dpi / 72.0
    mat = fitz.Matrix(zoom, zoom)
    for i, page in enumerate(doc):
        if i >= max_pages:
            break
        pix = page.get_pixmap(matrix=mat)
        img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, pix.n)
        if pix.n == 4:
            img = img[:, :, :3]
        result, _ = engine()(img)
        if result:
            for box, text, conf in result:
                t = text.strip()
                if t:
                    lines.append(t)
    doc.close()
    return lines

def fix_spacing(s):
    # RapidOCR sometimes glues words; split on lower->Upper and letter/digit
    # boundaries, and normalize spaces. Conservative: only case/type boundaries.
    s = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", s)
    s = re.sub(r"(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])", " ", s)
    s = re.sub(r"\s{2,}", " ", s)
    return s

def clean(lines):
    text = "\n".join(fix_spacing(ln) for ln in lines)
    # Drop obvious page-chrome/boilerplate lines.
    out = []
    for ln in text.split("\n"):
        s = ln.strip()
        if not s:
            continue
        if re.fullmatch(r"[\d\W]{0,4}", s):  # page numbers / stray marks
            continue
        if re.search(r"(naqshbandiaowaisiah|www\.|http|Asrar-ut-Tanzil\s*$)", s, re.I):
            continue
        out.append(s)
    # Rejoin wrapped lines into paragraphs (heuristic: join unless line ends a sentence).
    paras, cur = [], ""
    for s in out:
        cur = (cur + " " + s).strip() if cur else s
        if re.search(r"[.!?:”\")]$", s):
            paras.append(cur); cur = ""
    if cur:
        paras.append(cur)
    return "\n\n".join(paras).strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--surahs", default="1")
    ap.add_argument("--lang", default="en", choices=["en"])
    ap.add_argument("--max-pages", type=int, default=60)
    ap.add_argument("--preview", action="store_true", help="print text, do not write JSON")
    args = ap.parse_args()

    surahs = [int(x) for x in args.surahs.split(",") if x.strip()]
    li = json.load(open(os.path.join(SEED, "library_items.json"), encoding="utf-8"))
    by_id = {it["id"]: it for it in li}
    surah_meta = {s["id"]: s for s in json.load(open(os.path.join(SEED, "quran_surahs.json"), encoding="utf-8"))}

    entries = []
    for sn in surahs:
        item = by_id.get(f"asrar-{sn}-{args.lang}")
        if not item or not item.get("downloadUrls"):
            print(f"surah {sn}: no {args.lang} tafseer PDF in catalog"); continue
        url = item["downloadUrls"][0]
        print(f"surah {sn}: downloading {url.rsplit('/',1)[-1]} ...")
        try:
            data = download(url)
        except Exception as e:
            print(f"  download failed: {e}"); continue
        print(f"  OCR ({round(len(data)/1024)} KB) ...")
        text = clean(ocr_pdf(data, max_pages=args.max_pages))
        words = len(text.split())
        print(f"  -> {words} words")
        if args.preview:
            print("  ---- preview ----")
            print("\n".join(text.split("\n")[:12]))
            print("  -----------------")
            continue
        if words < 20:
            print("  too little text; skipping"); continue
        meta = surah_meta.get(sn, {})
        entries.append({
            "editionID": "asrar-at-tanzil-en",
            "surahNumber": sn, "ayahStart": 1,
            "ayahEnd": meta.get("ayahCount", 1),
            "text": text + "\n\n— Asrar-at-Tanzil (English), Hazrat Ameer Muhammad Akram Awan (RA). "
                           "Transcribed by OCR from the official PDF; the original is on naqshbandiaowaisiah.org.",
            "sourceUrl": item.get("sourceUrl"),
        })

    if args.preview:
        return
    # Merge into quran_tafsir.json (replace same edition+surah).
    path = os.path.join(SEED, "quran_tafsir.json")
    existing = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else []
    keep = [e for e in existing
            if not (e.get("editionID") == "asrar-at-tanzil-en"
                    and e.get("surahNumber") in surahs and (e.get("text") or "").count(" ") > 30)]
    # remove old link-only stubs for these surahs too
    keep = [e for e in keep if not (e.get("editionID") == "asrar-at-tanzil-en" and e.get("surahNumber") in surahs)]
    merged = keep + entries
    json.dump(merged, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"\nwrote {len(entries)} tafsir entries; quran_tafsir.json now {len(merged)} total")

if __name__ == "__main__":
    main()
