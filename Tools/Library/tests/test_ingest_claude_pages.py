from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ingest_claude_pages as importer  # noqa: E402


def page(*blocks: tuple[str, str]) -> dict:
    return {"blocks": [{"kind": kind, "text": text} for kind, text in blocks]}


def test_each_block_gets_its_letter_in_reading_order():
    parts = importer.page_parts(page(
        ("heading", "باب اول"),
        ("paragraph", "انسان جو چیز بناتا ہے۔"),
        ("verse", "پہلا مصرع\nدوسرا مصرع"),
        ("arabic", "قُلْ هُوَ اللّٰهُ اَحَدٌ"),
        ("footnote", "١ حاشیہ"),
        ("table", "نام | فرض"),
        ("caption", "ایک منظر"),
    ))
    assert "".join(letter for letter, _ in parts) == "hpvaftc"
    assert parts[2] == ("v", "پہلا مصرع\nدوسرا مصرع")


def test_text_splits_back_into_exactly_one_part_per_letter():
    parts = importer.page_parts(page(
        ("verse", "پہلا مصرع\n\n\nدوسرا مصرع"),
        ("paragraph", "  سطر\r\n \nدوسری سطر  "),
        ("heading", "   "),
        ("caption", ""),
    ))
    text = importer.PART_SEPARATOR.join(part for _, part in parts)
    assert [letter for letter, _ in parts] == ["v", "p"]
    assert text.split(importer.PART_SEPARATOR) == ["پہلا مصرع\nدوسرا مصرع", "سطر\nدوسری سطر"]


def test_an_unknown_block_kind_is_refused():
    with pytest.raises(ValueError):
        importer.page_parts(page(("sidebar", "متن")))


def test_a_page_completed_after_the_reading_is_kept():
    reading = "پہلا حصہ\n\nقاضی نے کہا تم جھوٹ بولتے ہو"
    assert importer.completed_later(reading + " اے حلال الدم۔", reading)
    assert not importer.completed_later(reading, reading)
    assert not importer.completed_later(reading + "\n\nنیا حصہ", reading)
    assert not importer.completed_later("بالکل مختلف متن جو اس سے لمبا ہے", reading)
