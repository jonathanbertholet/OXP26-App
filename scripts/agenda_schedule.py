"""Finite 2026 agenda refresh windows, including the published masterclass days."""
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

WINDOWS = (
    ('in', '2026-09-09', '2026-09-12', 'Asia/Kolkata'),
    ('be', '2026-09-22', '2026-09-26', 'Europe/Brussels'),
)
END = datetime.fromisoformat('2026-09-27T00:00:00+02:00')


def plan(now, last_attempt=None):
    if now >= END:
        return 'disable', []
    events = [code for code, start, end, zone in WINDOWS
              if start <= now.astimezone(ZoneInfo(zone)).date().isoformat() <= end]
    if not events or (last_attempt and (now - last_attempt).total_seconds() < 7200):
        return 'skip', []
    return 'refresh', events


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--attempt', type=Path)
    args = parser.parse_args()
    stamps = []
    if args.baseline:
        stamp = json.loads(args.baseline.read_text()).get('generated_at')
        if stamp: stamps.append(datetime.fromisoformat(stamp))
    if args.attempt and args.attempt.exists() and args.attempt.read_text().strip():
        stamps.append(datetime.fromisoformat(args.attempt.read_text().strip()))
    action, events = plan(datetime.now(timezone.utc), max(stamps) if stamps else None)
    print(f'Agenda schedule: {action}; editions: {", ".join(events) or "none"}')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'action={action}\nevents={" ".join(events)}\n')


if __name__ == '__main__': main()
