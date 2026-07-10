"""Schema tests: stable IDs, checksums, camelCase emission matching the
Swift Codable models, and validators."""

import conftest  # noqa: F401  (sys.path bootstrap)

import schema


class TestSlugFromUrl:
    def test_lecture_detail_page(self):
        url = ("https://www.naqshbandiaowaisiah.org/lecture/3725/"
               "2026-01-02-dawat-o-tabligh-ke-usool.html")
        assert schema.slug_from_url(url) == "lecture-3725-2026-01-02-dawat-o-tabligh-ke-usool"

    def test_percent_encoded_mp3(self):
        url = "https://www.naqshbandiaowaisiah.org/uploads/3835/06-02-2026%20s.mp3"
        assert schema.slug_from_url(url) == "uploads-3835-06-02-2026-s"

    def test_pdf_path(self):
        url = "https://www.naqshbandiaowaisiah.org/uploads/books/Dalael-us-Salook-Urdu.pdf"
        assert schema.slug_from_url(url) == "uploads-books-dalael-us-salook-urdu"

    def test_stable_across_calls(self):
        url = "https://www.naqshbandiaowaisiah.org/articles"
        assert schema.slug_from_url(url) == schema.slug_from_url(url)


class TestChecksum:
    def test_deterministic(self):
        item = {"id": "x", "title": "One", "downloadUrls": ["https://a/b.pdf"]}
        assert schema.checksum_for(item) == schema.checksum_for(dict(item))

    def test_changes_when_content_changes(self):
        item = {"id": "x", "title": "One"}
        other = {"id": "x", "title": "Two"}
        assert schema.checksum_for(item) != schema.checksum_for(other)

    def test_excludes_checksum_and_curated_keys(self):
        base = {"id": "x", "title": "One"}
        with_flags = dict(base, checksum="stale", curated=True)
        assert schema.checksum_for(base) == schema.checksum_for(with_flags)

    def test_apply_checksum_round_trips(self):
        item = {"id": "x", "title": "One"}
        schema.apply_checksum(item)
        assert item["checksum"] == schema.checksum_for(item)


class TestContentItemEmission:
    def make_item(self):
        return schema.ContentItem(
            id="uploads-books-dalael-us-salook-urdu",
            source_url="https://www.naqshbandiaowaisiah.org/books-on-tasawwuf.html",
            type="book",
            title="Dalael-us-Salook in Urdu",
            language="ur",
            category="books",
            download_urls=["https://www.naqshbandiaowaisiah.org/uploads/books/Dalael-us-Salook-Urdu.pdf"],
        )

    def test_camel_case_keys_match_swift_model(self):
        d = self.make_item().to_dict()
        assert set(d.keys()) == {
            "id", "sourceUrl", "type", "title", "language", "category",
            "rightsStatus", "mediaUrls", "downloadUrls", "checksum",
        }
        assert d["rightsStatus"] == "linkOnly"
        assert d["mediaUrls"] == []

    def test_optional_fields_omitted_not_null(self):
        d = self.make_item().to_dict()
        for absent in ("titleUrdu", "author", "bodyHtml", "bodyPlainText",
                       "excerpt", "publishedAt", "updatedAt"):
            assert absent not in d

    def test_emission_is_idempotent(self):
        assert self.make_item().to_dict() == self.make_item().to_dict()


class TestMediaItemEmission:
    def make_item(self):
        return schema.MediaItem(
            id="lecture-3835-2026-02-06-azmat-mohammad-rasool-ul-allah",
            title="عظمت محمد الرسول اللہ",
            language="ur",
            media_type="audio",
            source_url="https://www.naqshbandiaowaisiah.org/lecture/3835/2026-02-06-azmat-mohammad-rasool-ul-allah.html",
            category="audioLectures",
            speaker="Sheikh-e-Silsila Naqshbandia Owaisiah Hazrat Ameer Abdul Qadeer Awan (MZA)",
            date="2026-02-06T00:00:00Z",
            stream_url="https://www.naqshbandiaowaisiah.org/uploads/3835/06-02-2026%20s.mp3",
            download_url="https://www.naqshbandiaowaisiah.org/uploads/3835/06-02-2026%20s.mp3",
            year=2026,
            month=2,
        )

    def test_camel_case_keys_match_swift_model(self):
        d = self.make_item().to_dict()
        assert set(d.keys()) == {
            "id", "title", "language", "mediaType", "sourceUrl", "category",
            "rightsStatus", "speaker", "date", "streamUrl", "downloadUrl",
            "year", "month", "checksum",
        }
        assert d["mediaType"] == "audio"
        assert d["date"] == "2026-02-06T00:00:00Z"

    def test_stream_url_preserves_percent_encoding(self):
        d = self.make_item().to_dict()
        assert d["streamUrl"].endswith("06-02-2026%20s.mp3")


class TestEventAndEditionEmission:
    def test_event_includes_required_bool(self):
        event = schema.CommunityEvent(
            id="monthly-ijtema",
            kind="monthlyIjtema",
            title="Monthly Ijtema at Dar-ul-Irfan",
            dates_are_approximate=True,
            venue="Dar-ul-Irfan, Munara, District Chakwal",
        )
        d = event.to_dict()
        assert d["datesAreApproximate"] is True
        assert d["kind"] == "monthlyIjtema"
        assert "startDate" not in d

    def test_quran_edition_includes_required_bool(self):
        edition = schema.QuranEdition(
            id="asrar-at-tanzil-en",
            title="Asrar-at-Tanzil",
            kind="tafsir",
            language="en",
            author="Hazrat Ameer Muhammad Akram Awan (RA)",
            source_url="https://www.naqshbandiaowaisiah.org/asrar-at-tanzil",
        )
        d = edition.to_dict()
        assert d["isAvailableOffline"] is False
        assert d["kind"] == "tafsir"
        assert d["rightsStatus"] == "linkOnly"


class TestValidators:
    def test_valid_content_item_passes(self):
        d = schema.ContentItem(
            id="a", source_url="https://x/a.html", type="article",
            title="A", language="en", category="articles").to_dict()
        assert schema.validate_content_item(d) == []

    def test_body_on_link_only_item_is_rejected(self):
        d = schema.ContentItem(
            id="a", source_url="https://x/a.html", type="article",
            title="A", language="en", category="articles",
            body_plain_text="full text").to_dict()
        errors = schema.validate_content_item(d)
        assert any("linkOnly" in e for e in errors)

    def test_unknown_category_is_rejected(self):
        d = schema.ContentItem(
            id="a", source_url="https://x/a.html", type="article",
            title="A", language="en", category="notARealCategory").to_dict()
        errors = schema.validate_content_item(d)
        assert any("category" in e for e in errors)

    def test_wma_stream_url_is_rejected(self):
        d = schema.MediaItem(
            id="m", title="T", language="ur", media_type="audio",
            source_url="https://x/l.html", category="audioLectures",
            stream_url="https://x/uploads/1/file.wma").to_dict()
        errors = schema.validate_media_item(d)
        assert any(".wma" in e for e in errors)

    def test_bad_iso_date_is_rejected(self):
        d = schema.MediaItem(
            id="m", title="T", language="ur", media_type="audio",
            source_url="https://x/l.html", category="audioLectures",
            date="02-Jan-2026").to_dict()
        errors = schema.validate_media_item(d)
        assert any("ISO-8601" in e for e in errors)

    def test_event_missing_bool_is_rejected(self):
        d = {"id": "e", "kind": "other", "title": "T"}
        errors = schema.validate_community_event(d)
        assert any("datesAreApproximate" in e for e in errors)
