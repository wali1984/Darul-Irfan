"""Regression checks for restoring omissions without breaking saved bookmarks."""
import copy
import json
import unittest
from pathlib import Path
import check_content as gate


class RestoredIdentityTests(unittest.TestCase):
    def test_reading_order_can_move_without_rekeying_bookmark(self):
        record = dict(bookID='hisn',canonicalID='hisn|75a|268',displayNumber='75a',sourceSequence=75)
        reference = dict(identitySequence=268,displayNumber='75a',sourceSequence=75)
        self.assertEqual([], gate.restored_identity_errors(record,reference))
        record['canonicalID'] = 'hisn|75a|75'
        self.assertTrue(gate.restored_identity_errors(record,reference))

    def test_wrong_order_and_number_are_rejected(self):
        reference = dict(identitySequence=6,sourceSequence=7,displayNumber='6')
        record = dict(bookID='bulugh',canonicalID='bulugh|6|6',sourceSequence=7,displayNumber='6')
        for field, value in [('sourceSequence',6),('displayNumber','7')]:
            changed = dict(record, **{field:value})
            self.assertTrue(gate.restored_identity_errors(changed,reference))

    def test_restored_source_inventory_is_lossless_and_ordered(self):
        registry = gate.load_restored_reading_order()
        for book, expected in [('bulugh',1767),('hisn',268),('adab',1326)]:
            rows = json.loads((gate.IOS_SEED/f'hadith_{book}.json').read_bytes())
            self.assertEqual(expected,len(rows))
            self.assertEqual(list(range(1,expected+1)),[r['sourceSequence'] for r in rows])
            source_ids = []
            for row in rows:
                reference = registry[row['canonicalID']]
                self.assertEqual([],gate.restored_identity_errors(row,reference))
                source_ids.append((reference['sourceURL'],reference['sourceURN']))
            self.assertEqual(expected,len(set(source_ids)))
        hisn = json.loads((gate.IOS_SEED/'hadith_hisn.json').read_bytes())
        self.assertEqual(['74','75a','75','76'],[r['displayNumber'] for r in hisn[73:77]])


if __name__ == '__main__':
    unittest.main()
