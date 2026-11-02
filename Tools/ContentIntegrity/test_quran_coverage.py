import unittest
from check_content import ayah_coverage_errors


class QuranCoverageTests(unittest.TestCase):
    def rows(self):
        return [dict(surahNumber=s, ayahNumber=a, text='verse')
                for s, a in [(1, 1), (1, 2), (2, 1)]]

    def verify(self, rows):
        return ayah_coverage_errors({1: 2, 2: 1}, rows, 'text')

    def test_complete_unordered_rows(self):
        self.assertEqual([], self.verify(list(reversed(self.rows()))))

    def test_duplicate_cannot_replace_missing_ayah(self):
        rows = self.rows()
        rows[2] = dict(rows[0])
        errors = self.verify(rows)
        self.assertTrue(any('duplicate' in error for error in errors))
        self.assertTrue(any('missing' in error for error in errors))

    def test_missing_and_invalid_ayahs(self):
        self.assertTrue(self.verify(self.rows()[1:]))
        for replacement in [dict(surahNumber=3), dict(ayahNumber=3)]:
            rows = self.rows()
            rows[0].update(replacement)
            self.assertTrue(any('invalid' in error for error in self.verify(rows)))

    def test_blank_text(self):
        for text in ['', '  \n', None]:
            rows = self.rows()
            rows[0]['text'] = text
            self.assertTrue(any('blank' in error for error in self.verify(rows)))


if __name__ == '__main__':
    unittest.main()
