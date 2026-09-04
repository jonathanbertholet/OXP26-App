# OXP — Odoo Experience companion

Unofficial native iOS app and seed data for [Odoo Experience 2026](https://www.odoo.com/event/odoo-experience-2026-9099). Regional editions are **separate events** (Belgium, Americas, LATAM, Africa, India). Talks, speakers, and rooms are never merged. The Brussels Expo map is Belgium-only.

```bash
git clone https://github.com/jonathanbertholet/OXP26-App.git
cd OXP26-App
xcodegen generate
xed OXP.xcodeproj
```

Run the **OXP** scheme on an iPhone. This project is not affiliated with Odoo S.A.

Public sources:

- https://www.odoo.com/event/odoo-experience-2026-9099/track
- https://www.odoo.com/event/odoo-experience-2026-americas-10327/track
- https://www.odoo.com/event/odoo-experience-2026-latam-9992/track
- https://www.odoo.com/event/odoo-experience-2026-africa-9277/track
- https://www.odoo.com/event/odoo-experience-2026-india-10174/track

The official site is an Odoo `website_event_track` page. There is no public track search_read API, so the scraper reads each edition’s talk list HTML, then follows `/event/…/track/{id}` (Odoo redirects to the canonical slug) for descriptions, speaker bios, and photos. Tags come from the public `/event/track_tag/search_read` JSON-RPC route.

## Data

| File | What |
| --- | --- |
| `data/oxp-2026.sqlite` | Relational seed (events, tracks, speakers, tags, exhibitors, FTS) |
| `data/oxp-2026.json` | Same dataset, nested as `{ default_event_id, events: [...] }` |
| `data/events/{code}.json` | One file per edition (`be`, `us`, `mx`, `ke`, `in`) |
| `src/types.ts` | TypeScript types for the JSON |

`starts_at` / `ends_at` are timezone-aware ISO datetimes in that edition’s zone (`Europe/Brussels`, `America/Los_Angeles`, `America/Mexico_City`, `Africa/Nairobi`, `Asia/Kolkata`). `kind` is derived from the title/duration (`masterclass`, `keynote`, `talk`, …), not an Odoo field.

Refresh after agenda changes:

```bash
python3 -m pip install -r requirements.txt
python3 scripts/scrape_oxp.py
# or a subset: python3 scripts/scrape_oxp.py --events be,in
```

HTML is cached in `.cache/` so a re-run only hits the network for new pages. Pass `--no-cache` for a clean pull.

## Preview

```bash
python3 -m http.server 8765
```

Then open http://127.0.0.1:8765/preview/ and pick an edition.

## iOS app

Native SwiftUI app targeting iOS 26. Tabs: **Today**, **Schedule**, **Map** (Brussels Expo only), **Expo**, **Saved**. A globe menu switches edition. Opening another Experience hides the Map tab and “Show on map” actions. Saved talks stay grouped by edition; Odoo track IDs are global so reminders still resolve.

The bundled catalog is `OXP/Resources/catalog.json` (text only, no HTML). Default event is Belgium (`9099`) unless the user already picked another edition.

```bash
xcodegen generate
xed OXP.xcodeproj
```

Run the **OXP** scheme on an iPhone. Before the selected event starts, use Today → the clock button to preview a conference day.

## SQLite sketch

```sql
SELECT day, start_time, location, name, speaker_line
FROM tracks
WHERE event_id = 9099 AND day = '2026-09-24'
ORDER BY start_time, location;

SELECT t.name, s.name, s.company
FROM tracks t
JOIN track_speakers ts ON ts.track_id = t.id
JOIN speakers s ON s.event_id = t.event_id AND s.id = ts.speaker_id
WHERE t.id = 10380;

SELECT name, speaker_line, location
FROM tracks_fts
WHERE tracks_fts MATCH 'gmail CRM';
```

## License

MIT. See [LICENSE](LICENSE).
