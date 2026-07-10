"""End-to-end pipeline tests (offline): fixture HTML → item builders →
output files. Covers idempotent writes, curated-field preservation, and
schema validation of a full output directory."""

import json

from conftest import load_fixture

import ingest
import parsers
import schema

BASE = "https://www.naqshbandiaowaisiah.org"
LECTURES_URL = BASE + "/lectures/2026"
ARCHIVE_URL = BASE + "/almurshid-magazine-1981-to-1985.html"
BOOKS_URL = BASE + "/books-on-tasawwuf.html"
ABOUT_URL = BASE + "/hazrat-ameer-abdul-qadeer-awan.html"
TAFSIR_URL = BASE + "/asrar-at-tanzil"

FIXED_GENERATED_AT = "2026-07-09T00:00:00Z"


def build_payload(rights_status="linkOnly"):
    """Assemble a full crawl payload from fixtures, exactly as `crawl` would."""
    lecture_result = parsers.parse_lectures_year_page(
        load_fixture("lectures_2026_sample.html"), LECTURES_URL)
    media, media_warnings = ingest.media_items_from_lecture_page(
        lecture_result, LECTURES_URL, 2026, rights_status)

    issues = parsers.parse_magazine_archive_page(
        load_fixture("magazine_1981_sample.html"), ARCHIVE_URL)
    documents = ingest.content_items_from_magazine_page(
        issues, ARCHIVE_URL, rights_status)

    books = parsers.parse_books_page(load_fixture("books_sample.html"), BOOKS_URL)
    documents += ingest.content_items_from_books_page(books, BOOKS_URL, rights_status)

    about_meta = parsers.parse_article_page(
        load_fixture("about_page_sample.html"), ABOUT_URL, include_body=False)
    articles = [ingest.content_item_from_about_page(
        about_meta, ABOUT_URL, "sheikhAbdulQadeerAwan", rights_status,
        include_body=False)]

    entries = parsers.parse_tafsir_index(
        load_fixture("tafsir_index_sample.html"), TAFSIR_URL)
    tafsir, _ = ingest.tafsir_manifest_from_index(entries, TAFSIR_URL, rights_status)

    payload = {
        "articles": articles,
        "documents": documents,
        "media": media,
        "events": [],
        "tafsir": tafsir,
    }
    return payload, media_warnings


def read_all_files(directory):
    contents = {}
    for path in sorted(directory.glob("*.json")):
        contents[path.name] = path.read_text(encoding="utf-8")
    return contents


class TestWriteOutputsIdempotency:
    def test_rerun_produces_identical_files(self, tmp_path):
        payload, _ = build_payload()
        out = tmp_path / "output"

        ingest.write_outputs(out, payload, generated_at=FIXED_GENERATED_AT)
        first = read_all_files(out)

        payload_again, _ = build_payload()
        ingest.write_outputs(out, payload_again, generated_at=FIXED_GENERATED_AT)
        second = read_all_files(out)

        assert set(first) == {
            "articles.json", "documents.json", "media.json", "events.json",
            "quran_tafsir_manifest.json", "content_manifest.json",
        }
        assert first == second

    def test_two_directories_get_identical_files(self, tmp_path):
        payload_a, _ = build_payload()
        payload_b, _ = build_payload()
        out_a = tmp_path / "a"
        out_b = tmp_path / "b"
        ingest.write_outputs(out_a, payload_a, generated_at=FIXED_GENERATED_AT)
        ingest.write_outputs(out_b, payload_b, generated_at=FIXED_GENERATED_AT)
        assert read_all_files(out_a) == read_all_files(out_b)

    def test_items_carry_no_run_timestamps(self, tmp_path):
        payload, _ = build_payload()
        out = tmp_path / "output"
        ingest.write_outputs(out, payload, generated_at=FIXED_GENERATED_AT)
        for name in ("articles.json", "documents.json", "media.json"):
            items = json.loads((out / name).read_text(encoding="utf-8"))
            for item in items:
                assert "updatedAt" not in item


class TestManifest:
    def test_counts_and_files(self, tmp_path):
        payload, _ = build_payload()
        out = tmp_path / "output"
        ingest.write_outputs(out, payload, generated_at=FIXED_GENERATED_AT)
        manifest = json.loads((out / "content_manifest.json").read_text(encoding="utf-8"))
        assert manifest["version"] == schema.SCHEMA_VERSION
        assert manifest["generatedAt"] == FIXED_GENERATED_AT
        assert manifest["counts"] == {
            "articles": 1,
            "documents": 5,   # 3 magazine issues + 2 books
            "media": 3,
            "events": 0,
            "quranTafsirPages": 3,
        }
        assert manifest["files"] == sorted([
            "articles.json", "documents.json", "media.json", "events.json",
            "quran_tafsir_manifest.json",
        ])


class TestBuilders:
    def test_media_items_match_verified_lectures(self):
        payload, warnings = build_payload()
        media = payload["media"]
        by_id = {item["id"]: item for item in media}
        assert set(by_id) == {
            "lecture-3725-2026-01-02-dawat-o-tabligh-ke-usool",
            "lecture-3835-2026-02-06-azmat-mohammad-rasool-ul-allah",
            "lecture-4141-2026-05-01-khankah-ki-zimadari",
        }
        irregular = by_id["lecture-3835-2026-02-06-azmat-mohammad-rasool-ul-allah"]
        assert irregular["streamUrl"] == BASE + "/uploads/3835/06-02-2026%20s.mp3"
        assert irregular["date"] == "2026-02-06T00:00:00Z"
        assert irregular["year"] == 2026
        assert irregular["month"] == 2
        assert irregular["mediaType"] == "audio"
        assert irregular["category"] == "audioLectures"
        assert irregular["rightsStatus"] == "linkOnly"
        # The wma exclusion produced a counted warning.
        assert any(".wma" in w for w in warnings)

    def test_magazine_published_at_from_filename_months(self):
        payload, _ = build_payload()
        documents = {item["id"]: item for item in payload["documents"]}
        feb_march = documents["uploads-almurshid-magazines-almurshid-february-march-1981"]
        assert feb_march["publishedAt"] == "1981-02-01T00:00:00Z"
        assert feb_march["type"] == "magazine"
        assert feb_march["category"] == "alMurshidMagazine"
        fallback = documents["uploads-almurshid-magazines-annual-number-1984"]
        assert fallback["publishedAt"] == "1984-11-01T00:00:00Z"

    def test_about_item_is_metadata_only_by_default(self):
        payload, _ = build_payload()
        about = payload["articles"][0]
        assert about["title"] == "Hazrat Ameer Abdul Qadeer Awan (MZA)"
        assert about["rightsStatus"] == "linkOnly"
        assert "bodyPlainText" not in about
        assert "bodyHtml" not in about

    def test_tafsir_manifest_warns_when_not_114_pages(self):
        entries = parsers.parse_tafsir_index(
            load_fixture("tafsir_index_sample.html"), TAFSIR_URL)
        manifest, warnings = ingest.tafsir_manifest_from_index(
            entries, TAFSIR_URL, "linkOnly")
        assert len(manifest["pages"]) == 3
        assert manifest["edition"]["id"] == "asrar-at-tanzil-en"
        assert any("114" in w for w in warnings)


class TestCuratedMerge:
    def test_curated_fields_preserved_urls_updated(self):
        payload, _ = build_payload()
        fresh = payload["documents"]
        target = dict(fresh[0])
        curated = dict(target)
        curated["curated"] = True
        curated["title"] = "A hand-curated title"
        curated["downloadUrls"] = ["https://old.example/old.pdf"]
        schema.apply_checksum(curated)

        merged, conflicts, _ = ingest.merge_items(fresh, [curated])
        merged_item = next(i for i in merged if i["id"] == target["id"])

        assert merged_item["title"] == "A hand-curated title"
        assert merged_item["downloadUrls"] == target["downloadUrls"]
        assert merged_item["curated"] is True
        assert merged_item["checksum"] == schema.checksum_for(merged_item)
        assert any("title" in c for c in conflicts)

    def test_curated_item_missing_upstream_is_kept(self):
        curated = {"id": "zz-removed", "title": "Kept", "curated": True}
        merged, conflicts, notes = ingest.merge_items([], [curated])
        assert any(i["id"] == "zz-removed" for i in merged)
        assert conflicts == []
        assert any("zz-removed" in n for n in notes)

    def test_non_curated_stale_item_kept_unless_pruned(self):
        stale = {"id": "old-item", "title": "Old"}
        merged, _, _ = ingest.merge_items([], [stale])
        assert any(i["id"] == "old-item" for i in merged)
        merged_pruned, _, _ = ingest.merge_items([], [stale], prune=True)
        assert merged_pruned == []

    def test_fresh_crawl_wins_for_non_curated_items(self):
        old = {"id": "x", "title": "Old title"}
        new = {"id": "x", "title": "New title"}
        schema.apply_checksum(new)
        merged, conflicts, _ = ingest.merge_items([new], [old])
        assert merged == [new]
        assert conflicts == []

    def test_crawl_into_existing_out_dir_respects_curation(self, tmp_path):
        payload, _ = build_payload()
        out = tmp_path / "output"
        ingest.write_outputs(out, payload, generated_at=FIXED_GENERATED_AT)

        # Curate one media item by hand.
        media_path = out / "media.json"
        items = json.loads(media_path.read_text(encoding="utf-8"))
        items[0]["curated"] = True
        items[0]["title"] = "Curated lecture title"
        media_path.write_text(schema.json_dumps_stable(items), encoding="utf-8")

        payload_again, _ = build_payload()
        conflicts, _ = ingest.write_outputs(
            out, payload_again, generated_at=FIXED_GENERATED_AT)

        reloaded = json.loads(media_path.read_text(encoding="utf-8"))
        curated_item = next(i for i in reloaded if i.get("curated") is True)
        assert curated_item["title"] == "Curated lecture title"
        assert any("title" in c for c in conflicts)


class TestValidateOutputDir:
    def test_full_output_validates_clean(self, tmp_path):
        payload, _ = build_payload()
        out = tmp_path / "output"
        ingest.write_outputs(out, payload, generated_at=FIXED_GENERATED_AT)
        errors, _ = ingest.validate_output_dir(out)
        assert errors == []

    def test_tampered_checksum_is_caught(self, tmp_path):
        payload, _ = build_payload()
        out = tmp_path / "output"
        ingest.write_outputs(out, payload, generated_at=FIXED_GENERATED_AT)
        media_path = out / "media.json"
        items = json.loads(media_path.read_text(encoding="utf-8"))
        items[0]["title"] = "Silently edited without checksum update"
        media_path.write_text(schema.json_dumps_stable(items), encoding="utf-8")
        errors, _ = ingest.validate_output_dir(out)
        assert any("checksum" in e for e in errors)


class TestYearAndSectionParsing:
    def test_year_range(self):
        assert ingest.parse_years("2024-2026") == [2024, 2025, 2026]

    def test_year_list_and_single(self):
        assert ingest.parse_years("2026") == [2026]
        assert ingest.parse_years("2020,2023") == [2020, 2023]

    def test_sections(self):
        assert ingest.parse_sections("about, lectures") == ["about", "lectures"]

    def test_unknown_section_rejected(self):
        try:
            ingest.parse_sections("about,nonsense")
        except ValueError as error:
            assert "nonsense" in str(error)
        else:
            raise AssertionError("expected ValueError")
