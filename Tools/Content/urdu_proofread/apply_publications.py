"""Apply the Urdu proofreading of the publications to `library_items.json`.

The articles, press releases and announcements are read in the same
proofreading as the books, but their findings are kept apart
(`publication-urdu-review.json` in the register): each names a publication,
the SHA-256 of its body as it stood at BASE, and where in the body the words
are. Like `apply_proofread.py`, this starts again from the BASE file every
time and writes the whole result.

What is done to an Urdu publication's body:

  * a finding that changes form only (spacing, punctuation, vowel marks, a
    final ہ written ے) is applied; one that changes letters waits for a
    reading (`decisions.json`, ids `PUB-…`), exactly as for the books;
  * the same tidying of spacing around marks as every Urdu page gets;
  * Arabic is shielded as in the books.

Three teaching articles opened with a note on how their Urdu came to be. The
owner's decision (21 November 2026): it is removed, from the plain body and
from the HTML copy of it, and not kept. An article's HTML copy follows every
correction made to its plain body, line for line.

    python Tools/Content/urdu_proofread/apply_publications.py            report only
    python Tools/Content/urdu_proofread/apply_publications.py --write    write the iOS seed
    python Tools/Content/urdu_proofread/apply_publications.py --queue    also write the findings that wait for a reading
"""

from __future__ import annotations

import hashlib
import html
import json
import re
import sys
from collections import Counter
from datetime import datetime

import apply_proofread as ap

NOTE_OPENING = "یہ اردو متن سلسلے کی ویب سائٹ پر شائع"


TEXT_BETWEEN_TAGS = re.compile(r"(?:(?<=>)|^)[^<>]+(?=<|$)")


def html_following(markup: str, before: str, after: str) -> str:
    """The HTML copy of a body, with each line as the corrected plain body has it."""
    markup = re.sub(rf"^\s*<p>{re.escape(NOTE_OPENING)}.*?</p>\s*", "", markup, count=1, flags=re.S)
    old = [line.strip() for line in before.split("\n") if line.strip()]
    new = [line.strip() for line in after.split("\n") if line.strip()]
    shown = [match for match in TEXT_BETWEEN_TAGS.finditer(markup) if match.group().strip()]
    if len(old) != len(new) or [html.unescape(match.group()).strip() for match in shown] != old:
        raise SystemExit("an article's HTML copy is not line for line its plain body; nothing written")
    out, at = [], 0
    for match, was, now in zip(shown, old, new):
        out.append(markup[at:match.start()])
        out.append(match.group() if was == now else html.escape(now, quote=False))
        at = match.end()
    return "".join(out) + markup[at:]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    write, queue = "--write" in sys.argv, "--queue" in sys.argv
    items, layout = ap.seed_layout(ap.base_file("library_items.json").read_bytes())
    by_id = {item["id"]: item for item in items}
    base_body = {item["id"]: item.get("bodyPlainText") for item in items}
    reviews = ap.read_json(ap.REGISTER / "publication-urdu-review.json") if (ap.REGISTER / "publication-urdu-review.json").exists() else []
    decisions = json.loads((ap.HERE / "decisions.json").read_text(encoding="utf-8")) if (ap.HERE / "decisions.json").exists() else {}
    mushaf = ap.Mushaf(ap.base_file("quran_ayahs.json"))
    quotations = ap.Quotations(ap.base_file("quran_ayahs.json"))

    ledger: dict[str, dict] = {}
    waiting: list[dict] = []
    for review in reviews:
        item = by_id.get(review["id"])
        body = item.get("bodyPlainText") if item else None
        if body is None or hashlib.sha256(body.encode("utf-8")).hexdigest() != review["bodySha256"]:
            for finding in review["findings"]:
                ledger[finding["id"]] = {"status": "error", "why": "the publication's body is not the text the finding was read from"}
            continue
        shield = ap.Shield(mushaf, body, None)
        accepted: list[tuple[int, int, str]] = []
        for finding in review["findings"]:
            fid, original, proposed, at = finding["id"], finding["original"], finding.get("suggested"), finding["offsetUtf16"]
            if body[at:at + len(original)] != original:
                ledger[fid] = {"status": "error", "why": "the words are not at the offset given"}
                continue
            decision = decisions.get(fid)
            if not proposed or proposed == original:
                ledger[fid] = {"status": "hold", "why": "no replacement proposed"}
                continue
            if any(word in proposed and word not in original for word in ap.NOTE_WORDS):
                ledger[fid] = {"status": "hold", "why": "proposal reads as a note to an editor, not as replacement words"}
                continue
            form_only = ap.form_key(original) == ap.form_key(proposed) or ap.oblique_only(original, proposed)
            if decision and decision["action"] == "hold":
                ledger[fid] = {"status": "hold", "why": "decision: " + decision.get("note", "held")}
                continue
            if not form_only and not (decision and decision["action"] == "apply"):
                ledger[fid] = {"status": "review", "why": "letters change"}
                waiting.append({"id": fid, "confidence": "none given", "category": "publication", "flag": "letters change",
                                "original": original, "proposed": proposed, "reason": finding.get("reasonUrdu", ""),
                                "context": body[max(0, at - 60):at + len(original) + 60]})
                continue
            placed = [(at + s, at + e, r) for s, e, r in ap.atomic_edits(original, proposed)]
            refusal = next((w for w in (shield.refuses(s, e) for s, e, _ in placed) if w), None)
            if refusal:
                as_finding = {"original": original, "suggested": proposed, "confidence": "editorial", "category": ""}
                put, how = ap.arabic_fix(as_finding, body, at, quotations, decided=bool(decision))
                if put is None:
                    ledger[fid] = {"status": "protected", "why": f"{refusal} ({how})"}
                    continue
                placed = [(at + s, at + e, r) for s, e, r in ap.atomic_edits(original, put)]
            if any(s < e2 and s2 < e for s, e, _ in placed for s2, e2, _ in accepted if e > s or e2 > s2):
                ledger[fid] = {"status": "superseded", "why": "another finding changes the same words"}
                continue
            accepted.extend(placed)
            ledger[fid] = {"status": "applied", "why": "decision" if decision else "form only"}
        if accepted:
            item["bodyPlainText"] = ap.apply_edits(body, sorted(set(accepted), key=lambda edit: (edit[0], edit[1])))

    notes = set()
    tidied: Counter = Counter()
    changed = 0
    for item in items:
        body = item.get("bodyPlainText")
        if item.get("language") != "ur" or not body:
            continue
        if body.startswith(NOTE_OPENING):
            notes.add(item["id"])
            body = body.partition("\n")[2].lstrip("\n")
        body, _ = ap.tidy(body, None, mushaf, tidied)
        if body != base_body[item["id"]]:
            ap.protected_survive(mushaf, f"publication {item['id']}", base_body[item["id"]].partition("\n")[2] if item["id"] in notes else base_body[item["id"]], None, body)
            item["bodyPlainText"] = body
            if item.get("bodyHtml"):
                before = base_body[item["id"]]
                before = before.partition("\n")[2].lstrip("\n") if item["id"] in notes else before
                item["bodyHtml"] = html_following(item["bodyHtml"], before, body)
            item["checksum"] = hashlib.sha256(body.encode("utf-8")).hexdigest()
            changed += 1

    summary = {"publicationsReviewed": len(reviews), "findings": sum(len(r["findings"]) for r in reviews),
               "status": dict(Counter(entry["status"] for entry in ledger.values())), "bodiesChanged": changed,
               "notesNotShown": sorted(notes), "tidied": dict(tidied), "written": write}
    (ap.OUT / "publications-ledger.json").write_text(json.dumps(ledger, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if queue and waiting:
        name = f"batch-pub-{datetime.now().strftime('%m%d-%H%M')}.json"
        (ap.OUT / "review").mkdir(exist_ok=True)
        (ap.OUT / "review" / name).write_text(json.dumps(waiting, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"{len(waiting)} findings wait for a reading: {name}")
    if write:
        (ap.SEED / "library_items.json").write_text(layout.render(items), encoding="utf-8", newline="")
        print(f"wrote library_items.json in {ap.SEED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
