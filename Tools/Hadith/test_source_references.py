"""Placeholder edition numbers must not erase a real in-book reference."""
import unittest
from bs4 import BeautifulSoup
from ingest_sunnah import ref_number_from, INBOOK_RE, split_number


class SourceReferenceTests(unittest.TestCase):
    def reference(self, number):
        return BeautifulSoup(f'<div><table class="hadith_reference"><tr><td>Sunnah.com reference</td><td>: Book 30, Hadith 62</td></tr><tr><td>English translation</td><td>: Book 26, Hadith {number}</td></tr><tr><td>Arabic reference</td><td>: Book 30, Hadith {number}</td></tr></table></div>','html.parser').div

    def test_placeholder_uses_the_sources_book_reference(self):
        block=self.reference(0)
        self.assertEqual('30:62',ref_number_from(block))
        self.assertEqual((62,None),split_number('30:62'))
        self.assertEqual(('30','62'),INBOOK_RE.search(block.get_text(' ',strip=True)).groups())

    def test_valid_global_edition_number_is_preserved(self):
        self.assertEqual('6040',ref_number_from(self.reference(6040)))


if __name__ == '__main__':
    unittest.main()
