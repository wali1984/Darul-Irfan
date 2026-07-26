from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import import_akram_ut_tarajum as importer  # noqa: E402


def row(number: int, urdu: str, english: str) -> str:
    return f"""
    <div class="ayat-row">
      <a id="ayat-{number}"></a>
      <span class="ayat-urdu-title">{urdu}</span>
      <span class="ayat-english-title">{english}</span>
    </div>
    """


def test_discovers_exactly_all_114_surahs():
    html = "".join(f'<a href="/quran/{number}-Surah-{number}">S{number}</a>' for number in range(1, 115))
    urls = importer.discover_surah_urls(html)
    assert list(sorted(urls)) == list(range(1, 115))
    assert urls[114].endswith("/quran/114-Surah-114")


def test_regular_surah_discards_display_basmalah(monkeypatch):
    html = row(0, "بسملہ", "Basmalah") + row(1, "پہلی", "First") + row(2, "دوسری", "Second")
    monkeypatch.setattr(importer, "fetch", lambda _: html)
    parsed = importer.parse_surah(2, "https://example.test/quran/2", 2)
    assert [(item.ayah, item.urdu, item.english) for item in parsed] == [
        (1, "پہلی", "First"),
        (2, "دوسری", "Second"),
    ]


def test_fatihah_maps_basmalah_and_combines_final_source_rows(monkeypatch):
    html = "".join(row(number, f"اردو {number}", f"English {number}") for number in range(8))
    monkeypatch.setattr(importer, "fetch", lambda _: html)
    parsed = importer.parse_surah(1, "https://example.test/quran/1", 7)
    assert [item.ayah for item in parsed] == list(range(1, 8))
    assert parsed[0].urdu == "اردو 0"
    assert parsed[1].english == "English 1"
    assert parsed[6].urdu == "اردو 6 اردو 7"
    assert parsed[6].english == "English 6 English 7"


def test_rejects_missing_numbered_ayah(monkeypatch):
    html = row(0, "بسملہ", "Basmalah") + row(1, "پہلی", "First")
    monkeypatch.setattr(importer, "fetch", lambda _: html)
    try:
        importer.parse_surah(2, "https://example.test/quran/2", 2)
    except ValueError as error:
        assert "missing=[2]" in str(error)
    else:
        raise AssertionError("Missing ayah should fail validation")
