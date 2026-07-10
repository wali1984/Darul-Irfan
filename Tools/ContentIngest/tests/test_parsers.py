"""Parser tests against saved HTML fixtures.

The lecture/magazine/book fixtures reproduce the entries verified in
Docs/RESEARCH_NOTES.md — including the irregular ``06-02-2026%20s.mp3``
filename — and the tests assert parser outputs exactly.
"""

from conftest import load_fixture

import parsers

BASE = "https://www.naqshbandiaowaisiah.org"

LECTURES_PAGE_URL = BASE + "/lectures/2026"
SPEAKER = ("Sheikh-e-Silsila Naqshbandia Owaisiah Hazrat Ameer "
           "Abdul Qadeer Awan (MZA)")

EXPECTED_LECTURES = [
    {
        "title": "دعوت و تبلیغ کے اصول",
        "speaker": SPEAKER,
        "date_iso": "2026-01-02T00:00:00Z",
        "mp3_url": BASE + "/uploads/3725/02-01-2026.mp3",
        "detail_url": BASE + "/lecture/3725/2026-01-02-dawat-o-tabligh-ke-usool.html",
    },
    {
        "title": "عظمت محمد الرسول اللہ",
        "speaker": SPEAKER,
        "date_iso": "2026-02-06T00:00:00Z",
        "mp3_url": BASE + "/uploads/3835/06-02-2026%20s.mp3",
        "detail_url": BASE + "/lecture/3835/2026-02-06-azmat-mohammad-rasool-ul-allah.html",
    },
    {
        "title": "خانقاہ کی ذمہ داری",
        "speaker": SPEAKER,
        "date_iso": "2026-05-01T00:00:00Z",
        "mp3_url": BASE + "/uploads/4141/01-05-2026.mp3",
        "detail_url": BASE + "/lecture/4141/2026-05-01-khankah-ki-zimadari.html",
    },
]


class TestLectureYearPage:
    def test_parses_three_rows_exactly(self):
        html = load_fixture("lectures_2026_sample.html")
        result = parsers.parse_lectures_year_page(html, LECTURES_PAGE_URL)
        assert result.items == EXPECTED_LECTURES

    def test_mp3_hrefs_are_harvested_never_constructed(self):
        """The irregular '%20s' filename must round-trip byte-for-byte."""
        html = load_fixture("lectures_2026_sample.html")
        result = parsers.parse_lectures_year_page(html, LECTURES_PAGE_URL)
        assert result.items[1]["mp3_url"].endswith("/uploads/3835/06-02-2026%20s.mp3")

    def test_wma_links_are_excluded_and_counted(self):
        html = load_fixture("lectures_2026_sample.html")
        result = parsers.parse_lectures_year_page(html, LECTURES_PAGE_URL)
        assert result.skipped_wma == 3
        for item in result.items:
            for value in item.values():
                if isinstance(value, str):
                    assert ".wma" not in value.lower()

    def test_parsing_twice_is_idempotent(self):
        html = load_fixture("lectures_2026_sample.html")
        first = parsers.parse_lectures_year_page(html, LECTURES_PAGE_URL)
        second = parsers.parse_lectures_year_page(html, LECTURES_PAGE_URL)
        assert first.items == second.items
        assert first.skipped_wma == second.skipped_wma


class TestMagazineArchivePage:
    ARCHIVE_URL = BASE + "/almurshid-magazine-1981-to-1985.html"

    def test_parses_issues_exactly(self):
        html = load_fixture("magazine_1981_sample.html")
        issues = parsers.parse_magazine_archive_page(html, self.ARCHIVE_URL)
        assert issues == [
            {
                "title": "February - March 1981",
                "year": 1981,
                "months": [2, 3],
                "pdf_url": BASE + "/uploads/almurshid-magazines/almurshid_february_march_1981.pdf",
            },
            {
                "title": "May 1983",
                "year": 1983,
                "months": [5],
                "pdf_url": BASE + "/uploads/almurshid-magazines/almurshid_may_1983.pdf",
            },
            {
                # Filename does not match the almurshid_{months}_{year}
                # pattern, so month/year fall back to the link text.
                "title": "November 1984",
                "year": 1984,
                "months": [11],
                "pdf_url": BASE + "/uploads/almurshid-magazines/annual-number-1984.pdf",
            },
        ]

    def test_parsing_twice_is_idempotent(self):
        html = load_fixture("magazine_1981_sample.html")
        assert (parsers.parse_magazine_archive_page(html, self.ARCHIVE_URL)
                == parsers.parse_magazine_archive_page(html, self.ARCHIVE_URL))


class TestBooksPage:
    BOOKS_URL = BASE + "/books-on-tasawwuf.html"

    def test_parses_books_exactly(self):
        html = load_fixture("books_sample.html")
        books = parsers.parse_books_page(html, self.BOOKS_URL)
        assert books == [
            {
                "title": "Dalael-us-Salook in Urdu",
                "pdf_url": BASE + "/uploads/books/Dalael-us-Salook-Urdu.pdf",
            },
            {
                "title": "Hayyat-e-Tayyabah - I",
                "pdf_url": BASE + "/uploads/books/Hayyat-e-Tayyabah-I.pdf",
            },
        ]

    def test_parsing_twice_is_idempotent(self):
        html = load_fixture("books_sample.html")
        assert (parsers.parse_books_page(html, self.BOOKS_URL)
                == parsers.parse_books_page(html, self.BOOKS_URL))


class TestTafsirIndex:
    INDEX_URL = BASE + "/asrar-at-tanzil"

    def test_parses_surah_links_in_order(self):
        html = load_fixture("tafsir_index_sample.html")
        entries = parsers.parse_tafsir_index(html, self.INDEX_URL)
        assert entries == [
            {
                "surah_number": 1,
                "title": "Surah Al-Fatihah",
                "url": BASE + "/asrar-at-tanzil/1229/tafseer-quran-in-english-surah-al-fatihah.html",
            },
            {
                "surah_number": 2,
                "title": "Surah Al-Baqarah",
                "url": BASE + "/asrar-at-tanzil/1230/tafseer-quran-in-english-surah-al-baqarah.html",
            },
            {
                # Image-only link: title is derived from the URL slug.
                "surah_number": 3,
                "title": "Aal-E-Imran",
                "url": BASE + "/asrar-at-tanzil/1231/tafseer-quran-in-english-surah-aal-e-imran.html",
            },
        ]


class TestArticlePage:
    PAGE_URL = BASE + "/hazrat-ameer-abdul-qadeer-awan.html"

    def test_metadata_only_by_default(self):
        html = load_fixture("about_page_sample.html")
        meta = parsers.parse_article_page(html, self.PAGE_URL)
        assert meta["title"] == "Hazrat Ameer Abdul Qadeer Awan (MZA)"
        assert meta["excerpt"] == ("Introduction to Sheikh-e-Silsila "
                                   "Naqshbandia Owaisiah, Hazrat Ameer "
                                   "Abdul Qadeer Awan (MZA).")
        assert meta["body_plain_text"] is None

    def test_body_extracted_only_when_requested(self):
        html = load_fixture("about_page_sample.html")
        meta = parsers.parse_article_page(html, self.PAGE_URL, include_body=True)
        body = meta["body_plain_text"]
        assert body is not None
        assert "present Sheikh-e-Silsila" in body
        assert "26 March 1973" in body
        # Chrome (nav/footer) is not part of the main text.
        assert "Home" not in body
        assert "Copyright" not in body


class TestIndexHarvesters:
    def test_magazine_archive_index(self):
        html = ('<body><a href="/almurshid-magazine-1981-to-1985.html">1981-1985</a>'
                '<a href="/almurshid-magazine-1986-to-1990.html">1986-1990</a>'
                '<a href="/almurshid-magazine.html">index</a></body>')
        urls = parsers.parse_magazine_archive_index(html, BASE + "/almurshid-magazine.html")
        assert urls == [
            BASE + "/almurshid-magazine-1981-to-1985.html",
            BASE + "/almurshid-magazine-1986-to-1990.html",
        ]

    def test_books_index(self):
        html = ('<body><a href="/books-on-tasawwuf.html">Books on Tasawwuf</a>'
                '<a href="/lectures/2026">Lectures</a></body>')
        urls = parsers.parse_books_index(html, BASE + "/download")
        assert urls == [BASE + "/books-on-tasawwuf.html"]

    def test_article_index_prefers_articles_paths(self):
        html = ('<body>'
                '<a href="/articles/on-gratitude.html">On Gratitude</a>'
                '<a href="/lectures/2026">Lectures</a>'
                '<a href="https://elsewhere.example/x.html">External</a>'
                '</body>')
        links = parsers.parse_article_index(html, BASE + "/articles")
        assert links == [{"title": "On Gratitude",
                          "url": BASE + "/articles/on-gratitude.html"}]


class TestDisplayDate:
    def test_dd_mmm_yyyy(self):
        assert parsers.parse_display_date("02-Jan-2026") == "2026-01-02T00:00:00Z"
        assert parsers.parse_display_date("06-Feb-2026") == "2026-02-06T00:00:00Z"
        assert parsers.parse_display_date("01-May-2026") == "2026-05-01T00:00:00Z"

    def test_full_month_names_accepted(self):
        assert parsers.parse_display_date("15-September-1999") == "1999-09-15T00:00:00Z"

    def test_no_date_returns_none(self):
        assert parsers.parse_display_date("no date here") is None
