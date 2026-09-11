import copy
import json
import sys
import unittest
from pathlib import Path
from datetime import datetime, timedelta
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from update_agenda import merge_listing, validate, update_event

class AgendaTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.fromisoformat('2026-09-01T00:00:00+00:00')
        self.bundle = json.loads(Path('OXP/Resources/catalog.json').read_text())
        self.bundle['schema_version'] = 1
        self.previous = next(p for p in self.bundle['events'] if p['event']['code'] == 'be')
        self.listing = [{k: t.get(k) for k in ('id', 'name', 'starts_at', 'ends_at', 'speaker_line', 'tag_ids')} for t in self.previous['tracks']]

    def test_preserves_details_updates_time_and_retains_removed_ids(self):
        removed = self.listing.pop()
        self.listing[0]['starts_at'] = '2026-09-24T11:00:00+02:00'
        result = merge_listing(self.previous, self.listing, self.previous['tags'], self.now)
        self.assertEqual(result[0]['description_text'], self.previous['tracks'][0]['description_text'])
        self.assertEqual(result[0]['starts_at'], self.listing[0]['starts_at'])
        self.assertTrue(next(t for t in result if t['id'] == removed['id'])['unavailable'])

    def test_rejects_partial_or_empty_listing(self):
        for listing in ([], self.listing[:100], self.listing + [self.listing[0]]):
            with self.assertRaises(AssertionError): merge_listing(self.previous, listing, [], self.now)

    def test_reappearing_talk_returns_and_changed_speaker_drops_stale_bio(self):
        self.previous['tracks'][0]['unavailable'] = True
        self.listing[0]['speaker_line'] = 'New presenter'
        result = merge_listing(self.previous, self.listing, [], self.now)
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

    def test_started_sessions_are_preserved_when_odoo_hides_them(self):
        self.now = datetime.fromisoformat('2026-09-24T12:00:00+02:00')
        for track in self.previous['tracks'][:200]:
            track['starts_at'] = self.now.isoformat()
            track['ends_at'] = (self.now + timedelta(minutes=30)).isoformat()
        self.previous['tracks'][0]['unavailable'] = True
        result = merge_listing(self.previous, self.listing[200:], [], self.now)
        by_id = {t['id']: t for t in result}
        for track in self.previous['tracks'][:200]:
            self.assertEqual(by_id[track['id']], {**track, 'unavailable': track.get('unavailable', False)})

    def test_future_loss_still_fails_even_with_many_past_sessions(self):
        for track in self.previous['tracks'][:200]:
            track['starts_at'] = (self.now - timedelta(days=1)).isoformat()
        with self.assertRaisesRegex(AssertionError, 'upcoming or undated'):
            merge_listing(self.previous, self.listing[300:], [], self.now)

    def test_live_session_keeps_clock_time(self):
        track = self.previous['tracks'][0]
        self.now = datetime.fromisoformat(track['starts_at'])
        self.listing[0]['starts_at'] = None
        self.listing[0]['ends_at'] = None
        result = merge_listing(self.previous, self.listing, [], self.now)
        self.assertEqual(result[0]['starts_at'], track['starts_at'])
        self.assertEqual(result[0]['ends_at'], track['ends_at'])

    def test_future_schedule_loss_is_not_hidden_by_new_dated_talks(self):
        for row in self.listing:
            row['starts_at'] = None
        additions = [{**t, 'id': t['id'] + 100000} for t in self.previous['tracks']]
        with self.assertRaisesRegex(AssertionError, 'Schedule unexpectedly'):
            merge_listing(self.previous, self.listing + additions, [], self.now)

    def test_empty_listing_requires_finished_sessions_and_valid_page(self):
        with self.assertRaises(AssertionError):
            merge_listing(self.previous, [], [], self.now, listing_present=True)
        self.now = datetime.fromisoformat('2026-10-01T00:00:00+00:00')
        self.previous['tracks'] = [t for t in self.previous['tracks'] if t.get('ends_at')]
        with self.assertRaises(AssertionError):
            merge_listing(self.previous, [], [], self.now)
        result = merge_listing(self.previous, [], [], self.now, listing_present=True)
        self.assertEqual({t['id'] for t in result}, {t['id'] for t in self.previous['tracks']})
        self.assertFalse(any(t['unavailable'] for t in result))

    def test_refresh_keeps_event_dates_and_locations_from_past_days(self):
        past = copy.deepcopy(self.previous['tracks'][0])
        future = copy.deepcopy(self.previous['tracks'][-1])
        past.update(day='2026-09-23', starts_at='2026-09-23T09:00:00+02:00',
                    ends_at='2026-09-23T10:00:00+02:00', location='Past room')
        future.update(day='2026-09-25', starts_at='2026-09-25T09:00:00+02:00',
                      ends_at='2026-09-25T10:00:00+02:00', location='Future room')
        self.now = datetime.fromisoformat('2026-09-24T12:00:00+02:00')
        for t in (past, future):
            t['details_checked_at'] = self.now.isoformat()
        self.previous['tracks'] = [past, future]
        self.previous['event'].update(starts_on='2026-09-22', ends_on='2026-09-26')
        fetcher = Mock()
        fetcher.get.return_value = ('https://www.odoo.com/event/example/track', '<html/>')
        with patch('update_agenda.parse_listing', return_value=[future]):
            result = update_event(self.previous, {'slug': 'example', 'timezone': 'Europe/Brussels'},
                                  fetcher, [], self.now)
        self.assertEqual(result['event']['starts_on'], '2026-09-22')
        self.assertEqual(result['event']['ends_on'], '2026-09-26')
        self.assertEqual(result['locations'], ['Future room', 'Past room'])

if __name__ == '__main__': unittest.main()
