"""Refresh live listings without discarding detail text or saved-talk identities."""
import argparse
import copy
import json
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from scrape_oxp import EVENTS, BASE, Fetcher, fetch_tags, parse_listing, parse_track_detail, slim_track, soupify


def validate(bundle):
    assert bundle.get('schema_version') == 1, 'Unsupported feed schema'
    assert {p['event']['id'] for p in bundle['events']} == {s['id'] for s in EVENTS}, 'Missing editions'
    assert len(bundle['events']) == len(EVENTS), 'Duplicate editions'
    all_ids = []
    for payload in bundle['events']:
        tracks = payload['tracks']
        for track in tracks:
            assert isinstance(track['id'], int) and track['name'].strip(), 'Invalid talk'
            all_ids.append(track['id'])
            if track.get('starts_at') and track.get('ends_at'):
                assert datetime.fromisoformat(track['ends_at']) >= datetime.fromisoformat(track['starts_at']), 'Invalid duration'
    assert len(all_ids) == len(set(all_ids)), 'Duplicate talk IDs'


def merge_listing(previous, listing, tags, now, *, listing_present=False):
    old = {t['id']: t for t in previous['tracks']}
    live = {t['id'] for t in listing}
    # Odoo omits finished talks and can remove reminder IDs / clock times
    # from live talks. Their absence is not evidence of cancellation.
    started = {t['id'] for t in previous['tracks']
               if t.get('starts_at') and datetime.fromisoformat(t['starts_at']) <= now}
    active = {t['id'] for t in previous['tracks']
              if not t.get('unavailable') and t['id'] not in started}
    finished = bool(old) and all(t.get('unavailable') or (
        t.get('ends_at') and datetime.fromisoformat(t['ends_at']) <= now
    ) for t in old.values())
    assert (listing or (listing_present and finished)) and len(live) == len(listing), 'Empty or duplicate listing'
    missing = active - live
    assert len(missing) <= max(2, len(active) * .10), (
        f'{len(missing)}/{len(active)} upcoming or undated talks disappeared '
        '(more than 10%); review source'
    )
    dated = sum(bool(t.get('starts_at')) for t in listing if t['id'] in active)
    old_dated = sum(bool(old[i].get('starts_at')) for i in active)
    assert dated >= old_dated * .9, 'Schedule unexpectedly disappeared'
    merged = []
    by_tag = {t['id']: t for t in tags}
    for row in listing:
        track = {**copy.deepcopy(old.get(row['id'], {})), **row, 'unavailable': False}
        if row['id'] in started and not row.get('starts_at'):
            for key in ('day', 'weekday', 'time_label', 'start_time', 'end_time',
                        'starts_at', 'ends_at', 'duration_minutes', 'duration_label'):
                track[key] = old[row['id']].get(key)
        track['tags'] = [by_tag[i] for i in row['tag_ids'] if i in by_tag]
        track.setdefault('speakers', [])
        track.setdefault('speaker_ids', [])
        track.setdefault('url', row.get('listing_url'))
        if old.get(row['id'], {}).get('speaker_line') != row.get('speaker_line'):
            track['speakers'] = []
            track['speaker_ids'] = []
            track.pop('details_checked_at', None)
        merged.append(track)
    merged.extend({**copy.deepcopy(old[i]),
                   'unavailable': old[i].get('unavailable', False) if i in started else True}
                  for i in sorted(set(old) - live))
    return merged


def update_event(previous, spec, fetcher, tags, now):
    _, html = fetcher.get(f"{BASE}/event/{spec['slug']}/track")
    listing = parse_listing(html, spec['timezone'])
    tracks = merge_listing(previous, listing, tags, now,
                           listing_present=bool(soupify(html).select_one('.o_wesession_list > ul > li')))
    def detail(track):
        stamp = track.get('details_checked_at')
        if track.get('unavailable') or (stamp and (now - datetime.fromisoformat(stamp)).total_seconds() < 86400):
            return track
        try:
            url, body = fetcher.get(f"{BASE}/event/{spec['slug']}/track/{track['id']}")
            if 'o_wesession_track_main_description' not in body:
                raise ValueError('Unexpected detail page')
            parsed = parse_track_detail(track['id'], url, body)
            for key in ('url', 'slug', 'description_text', 'image_url'):
                track[key] = parsed[key]
            speaker = parsed['speaker']
            track['speakers'] = [{**speaker, 'id': track['id']}] if speaker.get('name') else []
            track['speaker_ids'] = [s['id'] for s in track['speakers']]
            track['details_checked_at'] = now.isoformat(timespec='seconds')
        except Exception as exc:
            print(f"Detail {track['id']} retained: {exc}", flush=True)
        return track
    with ThreadPoolExecutor(max_workers=4) as pool:
        tracks = list(pool.map(detail, tracks))
    result = copy.deepcopy(previous)
    result['tracks'] = [{**slim_track(t), 'unavailable': t.get('unavailable', False), 'details_checked_at': t.get('details_checked_at')} for t in tracks]
    result['tags'] = tags
    available = [t for t in tracks if not t.get('unavailable')]
    result['locations'] = sorted({t['location'] for t in available if t.get('location')})
    result['event']['source_checked_at'] = now.isoformat(timespec='seconds')
    days = sorted({t['day'] for t in available if t.get('day')} |
                  {previous['event'][key] for key in ('starts_on', 'ends_on')
                   if previous['event'].get(key)})
    if days:
        result['event'].update(starts_on=days[0], ends_on=days[-1])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--events', nargs='+', choices=['in', 'be'], default=['in', 'be'])
    args = parser.parse_args()
    bundle = json.loads(args.baseline.read_text())
    bundle['schema_version'] = 1
    validate(bundle)
    now = datetime.now(timezone.utc)
    fetcher = Fetcher(cache=False, timeout=25, retries=2)
    try:
        _, tags = fetch_tags(fetcher)
    except Exception:
        tags = list({t['id']: t for p in bundle['events'] for t in p['tags']}.values())
    specs = {s['id']: s for s in EVENTS}
    results, failures = [], []
    attempted = 0
    for previous in bundle['events']:
        if previous['event']['code'] not in args.events:
            results.append(previous)
            continue
        attempted += 1
        try:
            updated = update_event(previous, specs[previous['event']['id']], fetcher, tags, now)
            print(f"Updated {previous['event']['name']}: {len(updated['tracks'])} talks", flush=True)
            results.append(updated)
        except Exception as exc:
            failures.append(previous['event']['code'])
            print(f"::warning::Retaining {previous['event']['code']}: {exc}", flush=True)
            results.append(previous)
    if len(failures) == attempted:
        raise RuntimeError('All sources failed; previous feed retained')
    bundle.update(events=results, generated_at=now.isoformat(timespec='seconds'), failed_events=failures)
    validate(bundle)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temp = args.output.with_suffix('.tmp')
    encoded = json.dumps(bundle, ensure_ascii=False, separators=(',', ':'))
    assert len(encoded.encode()) <= 8_000_000, 'Feed exceeds app size limit'
    temp.write_text(encoded)
    os.replace(temp, args.output)


if __name__ == '__main__':
    main()
