import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from update_agenda import merge_listing, validate

class AgendaTests(unittest.TestCase):
    def setUp(self):
        self.bundle = json.loads(Path('OXP/Resources/catalog.json').read_text())
        self.bundle['schema_version'] = 1
        self.previous = next(p for p in self.bundle['events'] if p['event']['code'] == 'be')
        self.listing = [{k: t.get(k) for k in ('id', 'name', 'starts_at', 'ends_at', 'speaker_line', 'tag_ids')} for t in self.previous['tracks']]

    def test_preserves_details_updates_time_and_retains_removed_ids(self):
        removed = self.listing.pop()
        self.listing[0]['starts_at'] = '2026-09-24T11:00:00+02:00'
        result = merge_listing(self.previous, self.listing, self.previous['tags'])
        self.assertEqual(result[0]['description_text'], self.previous['tracks'][0]['description_text'])
        self.assertEqual(result[0]['starts_at'], self.listing[0]['starts_at'])
        self.assertTrue(next(t for t in result if t['id'] == removed['id'])['unavailable'])

    def test_rejects_partial_or_empty_listing(self):
        for listing in ([], self.listing[:100]):
            with self.assertRaises(AssertionError): merge_listing(self.previous, listing, [])

    def test_reappearing_talk_returns_and_changed_speaker_drops_stale_bio(self):
        self.previous['tracks'][0]['unavailable'] = True
        self.listing[0]['speaker_line'] = 'New presenter'
        result = merge_listing(self.previous, self.listing, [])
        self.assertFalse(result[0]['unavailable'])
        self.assertEqual(result[0]['speakers'], [])

    def test_schema_editions_and_duplicates(self):
        validate(self.bundle)
        invalid = copy.deepcopy(self.bundle)
        invalid['events'].pop()
        with self.assertRaises(AssertionError): validate(invalid)
        invalid = copy.deepcopy(self.bundle)
        invalid['events'][-1]['tracks'].append(invalid['events'][-1]['tracks'][0])
        with self.assertRaises(AssertionError): validate(invalid)

if __name__ == '__main__': unittest.main()
