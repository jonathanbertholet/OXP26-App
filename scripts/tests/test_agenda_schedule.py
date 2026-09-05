import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agenda_schedule import plan

class ScheduleTests(unittest.TestCase):
    def test_local_boundaries_and_only_active_edition(self):
        for raw, expected in [
            ('2026-09-05T10:00:00+00:00', ('skip', [])),
            ('2026-09-08T18:29:59+00:00', ('skip', [])),
            ('2026-09-08T18:30:00+00:00', ('refresh', ['in'])),
            ('2026-09-12T18:29:59+00:00', ('refresh', ['in'])),
            ('2026-09-12T18:30:00+00:00', ('skip', [])),
            ('2026-09-21T21:59:59+00:00', ('skip', [])),
            ('2026-09-21T22:00:00+00:00', ('refresh', ['be'])),
            ('2026-09-26T21:59:59+00:00', ('refresh', ['be'])),
            ('2026-09-26T22:00:00+00:00', ('disable', [])),
            ('2027-09-09T12:00:00+00:00', ('disable', [])),
        ]:
            with self.subTest(raw=raw): self.assertEqual(plan(datetime.fromisoformat(raw)), expected)

    def test_two_hour_minimum_even_after_failed_attempt(self):
        now = datetime.fromisoformat('2026-09-24T12:00:00+00:00')
        self.assertEqual(plan(now, now - timedelta(seconds=7199)), ('skip', []))
        self.assertEqual(plan(now, now - timedelta(seconds=7200)), ('refresh', ['be']))

if __name__ == '__main__': unittest.main()
